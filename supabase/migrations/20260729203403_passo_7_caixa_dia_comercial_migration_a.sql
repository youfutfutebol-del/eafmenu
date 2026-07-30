create or replace function public.dia_comercial_atual()
returns date language sql stable set search_path=pg_catalog as $$
 select ((statement_timestamp() at time zone 'America/Sao_Paulo')-interval '7 hours')::date
$$;
create or replace function public.inicio_dia_comercial(p_data date)
returns timestamptz language sql stable strict set search_path=pg_catalog as $$
 select (p_data + time '07:00') at time zone 'America/Sao_Paulo'
$$;
create or replace function public.fim_dia_comercial(p_data date)
returns timestamptz language sql stable strict set search_path=pg_catalog as $$
 select ((p_data + 1) + time '07:00') at time zone 'America/Sao_Paulo'
$$;
revoke all on function public.dia_comercial_atual() from public;
revoke all on function public.inicio_dia_comercial(date) from public;
revoke all on function public.fim_dia_comercial(date) from public;
grant execute on function public.dia_comercial_atual() to anon,authenticated,service_role;
grant execute on function public.inicio_dia_comercial(date) to authenticated,service_role;
grant execute on function public.fim_dia_comercial(date) to authenticated,service_role;
alter table public.fechamentos_caixa add column if not exists data_comercial date;
update public.fechamentos_caixa set data_comercial=(((aberto_em at time zone 'America/Sao_Paulo')-interval '7 hours')::date) where data_comercial is null and aberto_em is not null;
do $$ begin if exists(select 1 from public.fechamentos_caixa where status='aberto' group by restaurante_id having count(*)>1) then raise exception 'Existem restaurantes com mais de um caixa aberto.'; end if; end $$;
create unique index if not exists fechamentos_caixa_um_aberto_por_restaurante_uidx on public.fechamentos_caixa(restaurante_id) where status='aberto';
create index if not exists fechamentos_caixa_restaurante_data_comercial_idx on public.fechamentos_caixa(restaurante_id,data_comercial desc);
create index if not exists movimentacoes_financeiras_restaurante_criado_em_idx on public.movimentacoes_financeiras(restaurante_id,criado_em);
alter table public.movimentacoes_financeiras add column if not exists ajuste_de_id uuid, add column if not exists motivo_ajuste text;
do $$ begin if not exists(select 1 from pg_catalog.pg_constraint where conrelid='public.movimentacoes_financeiras'::regclass and conname='movimentacoes_financeiras_ajuste_de_id_fkey') then alter table public.movimentacoes_financeiras add constraint movimentacoes_financeiras_ajuste_de_id_fkey foreign key(ajuste_de_id) references public.movimentacoes_financeiras(id) on delete restrict; end if; end $$;
alter table public.movimentacoes_financeiras drop constraint if exists movimentacoes_financeiras_origem_check, drop constraint if exists movimentacoes_financeiras_origem_pedido_check;
alter table public.movimentacoes_financeiras add constraint movimentacoes_financeiras_origem_check check(origem in('lancamento_manual','recebimento_pedido','estorno_pedido','ajuste_compensatorio')), add constraint movimentacoes_financeiras_origem_pedido_check check((origem='lancamento_manual' and pedido_id is null and ajuste_de_id is null and motivo_ajuste is null) or (origem in('recebimento_pedido','estorno_pedido') and pedido_id is not null and ajuste_de_id is null and motivo_ajuste is null) or (origem='ajuste_compensatorio' and pedido_id is null and ajuste_de_id is not null and nullif(btrim(motivo_ajuste),'') is not null));
create unique index if not exists movimentacoes_ajuste_original_uidx on public.movimentacoes_financeiras(ajuste_de_id) where origem='ajuste_compensatorio';
create or replace function public.serializar_movimentacao_financeira() returns trigger language plpgsql security invoker set search_path=pg_catalog as $$
declare v_restaurante_id uuid;
begin
 v_restaurante_id:=case when tg_op='DELETE' then old.restaurante_id else new.restaurante_id end;
 if v_restaurante_id is null then raise exception 'Movimentação financeira sem restaurante.'; end if;
 if tg_op='UPDATE' and new.restaurante_id is distinct from old.restaurante_id then raise exception 'Não é permitido transferir uma movimentação entre restaurantes.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_restaurante_id::text,8675309));
 if tg_op='INSERT' then new.criado_em:=pg_catalog.clock_timestamp(); return new; end if;
 if tg_op='UPDATE' then new.criado_em:=old.criado_em; return new; end if;
 return old;
end $$;
revoke all on function public.serializar_movimentacao_financeira() from public,anon,authenticated,service_role;
drop trigger if exists trg_000_serializar_movimentacao_financeira on public.movimentacoes_financeiras;
create trigger trg_000_serializar_movimentacao_financeira before insert or update or delete on public.movimentacoes_financeiras for each row execute function public.serializar_movimentacao_financeira();
create or replace function public.trg_proteger_movimento_financeiro_pedido() returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if tg_op='INSERT' then
  if new.origem in('recebimento_pedido','estorno_pedido') or new.pedido_id is not null then
   if coalesce(current_setting('eafmenu.via_movimento_pedido',true),'')<>'true' then raise exception 'Movimento financeiro de pedido só pode ser criado pelo fluxo financeiro do sistema.'; end if;
  end if;
  if new.origem='ajuste_compensatorio' or new.ajuste_de_id is not null then
   if coalesce(current_setting('eafmenu.via_ajuste_financeiro',true),'')<>'true' then raise exception 'Ajuste financeiro só pode ser criado pelo fluxo de compensação.'; end if;
  end if;
  return new;
 end if;
 raise exception 'Movimentação financeira é imutável e não pode ser alterada ou apagada.';
end $$;
alter function public.trg_proteger_movimento_financeiro_pedido() owner to postgres;
revoke all on function public.trg_proteger_movimento_financeiro_pedido() from public,anon,authenticated,service_role;
create or replace function public.calcular_caixa_dinheiro_interno(p_restaurante_id uuid,p_aberto_em timestamptz,p_fim_exclusivo timestamptz)
returns table(entradas_dinheiro numeric,saidas_dinheiro numeric,valor_liquido numeric)
language sql stable security definer set search_path=pg_catalog as $$
 select coalesce(sum(m.valor) filter(where m.tipo='receita' and lower(coalesce(m.forma_pagamento,''))='dinheiro'),0), coalesce(sum(m.valor) filter(where m.tipo='despesa' and lower(coalesce(m.forma_pagamento,''))='dinheiro'),0), coalesce(sum(case when m.tipo='receita' and lower(coalesce(m.forma_pagamento,''))='dinheiro' then m.valor when m.tipo='despesa' and lower(coalesce(m.forma_pagamento,''))='dinheiro' then -m.valor else 0 end),0)
 from public.movimentacoes_financeiras m where m.restaurante_id=p_restaurante_id and m.criado_em>=p_aberto_em and m.criado_em<p_fim_exclusivo
$$;
revoke all on function public.calcular_caixa_dinheiro_interno(uuid,timestamptz,timestamptz) from public,anon,authenticated,service_role;
create or replace function public.compatibilizar_escrita_caixa_legado() returns trigger language plpgsql security definer set search_path=pg_catalog as $$
declare v_usuario public.usuarios%rowtype; v_fechado_em timestamptz; v_mov record; v_esperado numeric; v_diferenca numeric; c_limite constant numeric:=99999999.99;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para operar o caixa.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if new.restaurante_id is distinct from v_usuario.restaurante_id then raise exception 'O caixa não pertence ao seu restaurante.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_usuario.restaurante_id::text,8675309));
 if tg_op='INSERT' then
  if new.status is distinct from 'aberto' then raise exception 'Um novo caixa deve iniciar aberto.'; end if;
  if new.valor_abertura is null or new.valor_abertura<0 or new.valor_abertura>c_limite then raise exception 'Informe um valor de abertura válido.'; end if;
  new.restaurante_id:=v_usuario.restaurante_id; new.aberto_por:=v_usuario.id; new.aberto_em:=pg_catalog.clock_timestamp(); new.data_comercial:=(((new.aberto_em at time zone 'America/Sao_Paulo')-interval '7 hours')::date); new.fechado_por:=null; new.fechado_em:=null; new.valor_dinheiro_esperado:=null; new.valor_dinheiro_informado:=null; new.diferenca:=null; return new;
 end if;
 if old.status='fechado' then raise exception 'Um caixa fechado não pode ser alterado.'; end if;
 if old.status='aberto' and new.status='aberto' then raise exception 'Um caixa aberto só pode ser alterado para fechado.'; end if;
 if not(old.status='aberto' and new.status='fechado') then raise exception 'Transição de status do caixa inválida.'; end if;
 if new.valor_dinheiro_informado is null or new.valor_dinheiro_informado<0 or new.valor_dinheiro_informado>c_limite then raise exception 'Informe um valor contado válido.'; end if;
 v_fechado_em:=pg_catalog.clock_timestamp();
 select * into v_mov from public.calcular_caixa_dinheiro_interno(old.restaurante_id,old.aberto_em,v_fechado_em);
 v_esperado:=round(old.valor_abertura+v_mov.valor_liquido,2);
 if abs(v_esperado)>c_limite then raise exception 'O valor esperado excede o limite suportado.'; end if;
 v_diferenca:=round(new.valor_dinheiro_informado-v_esperado,2);
 if abs(v_diferenca)>c_limite then raise exception 'A diferença excede o limite suportado.'; end if;
 new.restaurante_id:=old.restaurante_id; new.valor_abertura:=old.valor_abertura; new.aberto_por:=old.aberto_por; new.aberto_em:=old.aberto_em; new.data_comercial:=old.data_comercial; new.valor_dinheiro_esperado:=v_esperado; new.valor_dinheiro_informado:=round(new.valor_dinheiro_informado,2); new.diferenca:=v_diferenca; new.fechado_por:=v_usuario.id; new.fechado_em:=v_fechado_em; return new;
end $$;
revoke all on function public.compatibilizar_escrita_caixa_legado() from public,anon,authenticated,service_role;
drop trigger if exists trg_000_compatibilizar_escrita_caixa_legado on public.fechamentos_caixa;
create trigger trg_000_compatibilizar_escrita_caixa_legado before insert or update on public.fechamentos_caixa for each row execute function public.compatibilizar_escrita_caixa_legado();
create or replace function public.gerar_entrada_financeira_pedido() returns trigger language plpgsql security definer set search_path=pg_catalog as $$
declare v_mov public.movimentacoes_financeiras%rowtype; v_flag_anterior text; v_constraint text;
begin
 if new.pago=true and (tg_op='INSERT' or coalesce(old.pago,false)=false) then
  if new.restaurante_id is null then raise exception 'Pedido sem restaurante.'; end if;
  v_flag_anterior:=current_setting('eafmenu.via_movimento_pedido',true);
  begin
   perform pg_catalog.set_config('eafmenu.via_movimento_pedido','true',true);
   begin
    insert into public.movimentacoes_financeiras(restaurante_id,tipo,origem,descricao,valor,pedido_id,criado_por,forma_pagamento) values(new.restaurante_id,'receita','recebimento_pedido',case when new.numero_diario is not null then 'Pedido #'||new.numero_diario else 'Pedido #'||upper(substr(new.id::text,1,8)) end,new.total,new.id,auth.uid(),new.forma_pagamento);
   exception when unique_violation then
    get stacked diagnostics v_constraint=constraint_name;
    if v_constraint is distinct from 'movimentacoes_recebimento_pedido_uidx' then raise; end if;
   end;
   perform pg_catalog.set_config('eafmenu.via_movimento_pedido',coalesce(v_flag_anterior,''),true);
  exception when others then perform pg_catalog.set_config('eafmenu.via_movimento_pedido',coalesce(v_flag_anterior,''),true); raise; end;
  select m.* into v_mov from public.movimentacoes_financeiras m where m.pedido_id=new.id and m.origem='recebimento_pedido';
  if v_mov.id is null or v_mov.restaurante_id is distinct from new.restaurante_id or v_mov.tipo is distinct from 'receita' or round(v_mov.valor,2) is distinct from round(new.total,2) or v_mov.forma_pagamento is distinct from new.forma_pagamento then raise exception 'Falha de conciliação financeira do pedido.'; end if;
 end if;
 return new;
end $$;
alter function public.gerar_entrada_financeira_pedido() owner to postgres;
revoke all on function public.gerar_entrada_financeira_pedido() from public,anon,authenticated,service_role;
create or replace function public.abrir_caixa_v2(p_valor_abertura numeric) returns public.fechamentos_caixa language plpgsql security definer set search_path=pg_catalog as $$
declare v_usuario public.usuarios%rowtype; v_caixa public.fechamentos_caixa%rowtype; v_constraint text;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para abrir o caixa.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if p_valor_abertura is null or p_valor_abertura<0 or p_valor_abertura>99999999.99 then raise exception 'Informe um valor de abertura válido.'; end if;
 begin insert into public.fechamentos_caixa(restaurante_id,status,valor_abertura,aberto_por,aberto_em,data_comercial) values(v_usuario.restaurante_id,'aberto',round(p_valor_abertura,2),v_usuario.id,pg_catalog.clock_timestamp(),public.dia_comercial_atual()) returning * into v_caixa;
 exception when unique_violation then get stacked diagnostics v_constraint=constraint_name; if v_constraint is distinct from 'fechamentos_caixa_um_aberto_por_restaurante_uidx' then raise; end if; raise exception 'Já existe um caixa aberto para este restaurante.'; end;
 return v_caixa;
end $$;
create or replace function public.fechar_caixa_v2(p_valor_contado numeric,p_observacoes text default null) returns public.fechamentos_caixa language plpgsql security definer set search_path=pg_catalog as $$
declare v_usuario public.usuarios%rowtype; v_caixa public.fechamentos_caixa%rowtype;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para fechar o caixa.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if p_valor_contado is null or p_valor_contado<0 or p_valor_contado>99999999.99 then raise exception 'Informe um valor contado válido.'; end if;
 select f.* into v_caixa from public.fechamentos_caixa f where f.restaurante_id=v_usuario.restaurante_id and f.status='aberto' for update;
 if v_caixa.id is null then raise exception 'Não existe caixa aberto para este restaurante.'; end if;
 update public.fechamentos_caixa f set status='fechado',valor_dinheiro_informado=round(p_valor_contado,2),observacoes=nullif(btrim(p_observacoes),'') where f.id=v_caixa.id and f.status='aberto' returning * into v_caixa;
 return v_caixa;
end $$;
create or replace function public.registrar_despesa_v2(p_descricao text,p_valor numeric,p_forma_pagamento text) returns public.movimentacoes_financeiras language plpgsql security definer set search_path=pg_catalog as $$
declare v_usuario public.usuarios%rowtype; v_mov public.movimentacoes_financeiras%rowtype; v_descricao text:=btrim(coalesce(p_descricao,'')); v_forma text:=lower(btrim(coalesce(p_forma_pagamento,'')));
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para lançar despesas.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if length(v_descricao)<3 then raise exception 'Informe a descrição da despesa.'; end if;
 if p_valor is null or p_valor<=0 or p_valor>99999999.99 then raise exception 'Informe um valor válido.'; end if;
 if v_forma not in('dinheiro','pix','cartao') then raise exception 'Informe uma forma de pagamento válida.'; end if;
 insert into public.movimentacoes_financeiras(restaurante_id,tipo,descricao,valor,criado_por,forma_pagamento,origem) values(v_usuario.restaurante_id,'despesa',v_descricao,round(p_valor,2),v_usuario.id,v_forma,'lancamento_manual') returning * into v_mov;
 return v_mov;
end $$;
create or replace function public.registrar_ajuste_financeiro_v1(p_movimentacao_original_id uuid,p_motivo text) returns table(movimentacao_id uuid,movimentacao_original_id uuid,reutilizado boolean) language plpgsql security definer set search_path=pg_catalog as $$
declare v_usuario public.usuarios%rowtype; v_original public.movimentacoes_financeiras%rowtype; v_ajuste public.movimentacoes_financeiras%rowtype; v_motivo text:=btrim(coalesce(p_motivo,'')); v_flag_anterior text; v_constraint text; v_reutilizado boolean:=false; v_tipo_inverso text;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para registrar ajustes.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if length(v_motivo)<3 then raise exception 'Informe o motivo do ajuste.'; end if;
 select m.* into v_original from public.movimentacoes_financeiras m where m.id=p_movimentacao_original_id for share;
 if v_original.id is null or v_original.restaurante_id is distinct from v_usuario.restaurante_id then raise exception 'Movimentação não encontrada nesse restaurante.'; end if;
 if v_original.origem='ajuste_compensatorio' then raise exception 'Um ajuste compensatório não pode ser ajustado novamente.'; end if;
 v_tipo_inverso:=case when v_original.tipo='receita' then 'despesa' else 'receita' end;
 v_flag_anterior:=current_setting('eafmenu.via_ajuste_financeiro',true);
 begin
  perform pg_catalog.set_config('eafmenu.via_ajuste_financeiro','true',true);
  begin
   insert into public.movimentacoes_financeiras(restaurante_id,tipo,descricao,valor,criado_por,forma_pagamento,origem,ajuste_de_id,motivo_ajuste) values(v_usuario.restaurante_id,v_tipo_inverso,'Ajuste: '||v_motivo,v_original.valor,v_usuario.id,v_original.forma_pagamento,'ajuste_compensatorio',v_original.id,v_motivo) returning * into v_ajuste;
  exception when unique_violation then
   get stacked diagnostics v_constraint=constraint_name;
   if v_constraint is distinct from 'movimentacoes_ajuste_original_uidx' then raise; end if;
   select m.* into v_ajuste from public.movimentacoes_financeiras m where m.ajuste_de_id=v_original.id and m.origem='ajuste_compensatorio';
   v_reutilizado:=true;
  end;
  perform pg_catalog.set_config('eafmenu.via_ajuste_financeiro',coalesce(v_flag_anterior,''),true);
 exception when others then perform pg_catalog.set_config('eafmenu.via_ajuste_financeiro',coalesce(v_flag_anterior,''),true); raise; end;
 if v_ajuste.id is null or v_ajuste.restaurante_id is distinct from v_original.restaurante_id or v_ajuste.origem is distinct from 'ajuste_compensatorio' or v_ajuste.valor is distinct from v_original.valor or v_ajuste.tipo is distinct from v_tipo_inverso or v_ajuste.forma_pagamento is distinct from v_original.forma_pagamento then raise exception 'Falha ao validar o ajuste financeiro.'; end if;
 if v_ajuste.motivo_ajuste is distinct from v_motivo then raise exception 'Esta movimentação já possui ajuste com outro motivo.'; end if;
 return query select v_ajuste.id,v_original.id,v_reutilizado;
end $$;
create or replace function public.listar_movimentos_dinheiro_sem_caixa_v1(p_data_inicio date default null,p_data_fim date default null) returns table(id uuid,tipo text,descricao text,valor numeric,criado_em timestamptz,forma_pagamento text,origem text,pedido_id uuid,ajuste_de_id uuid) language plpgsql security definer set search_path=pg_catalog as $$
declare v_usuario public.usuarios%rowtype; v_inicio timestamptz; v_fim timestamptz;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para consultar a auditoria.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if (p_data_inicio is null)<>(p_data_fim is null) then raise exception 'Informe as duas datas ou nenhuma delas.'; end if;
 if p_data_inicio is not null and p_data_inicio>p_data_fim then raise exception 'A data inicial não pode ser posterior à final.'; end if;
 if p_data_inicio is not null then v_inicio:=public.inicio_dia_comercial(p_data_inicio); v_fim:=public.fim_dia_comercial(p_data_fim); end if;
 return query select m.id,m.tipo,m.descricao,m.valor,m.criado_em,m.forma_pagamento,m.origem,m.pedido_id,m.ajuste_de_id from public.movimentacoes_financeiras m where m.restaurante_id=v_usuario.restaurante_id and lower(coalesce(m.forma_pagamento,''))='dinheiro' and (v_inicio is null or (m.criado_em>=v_inicio and m.criado_em<v_fim)) and not exists(select 1 from public.fechamentos_caixa f where f.restaurante_id=m.restaurante_id and m.criado_em>=f.aberto_em and m.criado_em<coalesce(f.fechado_em,'infinity'::timestamptz)) order by m.criado_em desc,m.id;
end $$;
create or replace function public.listar_movimentacoes_financeiras_v2(p_periodo text default 'hoje') returns table(id uuid,tipo text,descricao text,valor numeric,pedido_id uuid,criado_em timestamptz,forma_pagamento text,origem text,criado_por uuid,ajuste_de_id uuid,motivo_ajuste text) language plpgsql security definer set search_path=pg_catalog as $$
declare v_usuario public.usuarios%rowtype; v_periodo text:=lower(btrim(coalesce(p_periodo,'hoje'))); v_dia date:=public.dia_comercial_atual(); v_inicio timestamptz; v_fim timestamptz;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para consultar o financeiro.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if v_periodo='hoje' then v_inicio:=public.inicio_dia_comercial(v_dia); elsif v_periodo='7dias' then v_inicio:=public.inicio_dia_comercial(v_dia-6); elsif v_periodo='30dias' then v_inicio:=public.inicio_dia_comercial(v_dia-29); else raise exception 'Período inválido.'; end if;
 v_fim:=public.fim_dia_comercial(v_dia);
 return query select m.id,m.tipo,m.descricao,m.valor,m.pedido_id,m.criado_em,m.forma_pagamento,m.origem,m.criado_por,m.ajuste_de_id,m.motivo_ajuste from public.movimentacoes_financeiras m where m.restaurante_id=v_usuario.restaurante_id and m.criado_em>=v_inicio and m.criado_em<v_fim order by m.criado_em desc,m.id;
end $$;
revoke all on function public.abrir_caixa_v2(numeric) from public;
revoke all on function public.fechar_caixa_v2(numeric,text) from public;
revoke all on function public.registrar_despesa_v2(text,numeric,text) from public;
revoke all on function public.registrar_ajuste_financeiro_v1(uuid,text) from public;
revoke all on function public.listar_movimentos_dinheiro_sem_caixa_v1(date,date) from public;
revoke all on function public.listar_movimentacoes_financeiras_v2(text) from public;
grant execute on function public.abrir_caixa_v2(numeric) to authenticated,service_role;
grant execute on function public.fechar_caixa_v2(numeric,text) to authenticated,service_role;
grant execute on function public.registrar_despesa_v2(text,numeric,text) to authenticated,service_role;
grant execute on function public.registrar_ajuste_financeiro_v1(uuid,text) to authenticated,service_role;
grant execute on function public.listar_movimentos_dinheiro_sem_caixa_v1(date,date) to authenticated,service_role;
grant execute on function public.listar_movimentacoes_financeiras_v2(text) to authenticated,service_role;