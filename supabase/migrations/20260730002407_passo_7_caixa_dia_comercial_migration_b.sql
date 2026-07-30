begin;
create or replace function public.abrir_caixa_v2(p_valor_abertura numeric) returns public.fechamentos_caixa language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare v_usuario public.usuarios%rowtype; v_caixa public.fechamentos_caixa%rowtype; v_aberto_em timestamptz; v_data_comercial date; v_constraint text;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para abrir o caixa.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if p_valor_abertura is null or p_valor_abertura<0 or p_valor_abertura>99999999.99 then raise exception 'Informe um valor de abertura válido.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_usuario.restaurante_id::text,8675309));
 v_aberto_em:=pg_catalog.clock_timestamp();
 v_data_comercial:=(((v_aberto_em at time zone 'America/Sao_Paulo')-interval '7 hours')::date);
 begin
  insert into public.fechamentos_caixa(restaurante_id,status,valor_abertura,aberto_por,aberto_em,data_comercial) values(v_usuario.restaurante_id,'aberto',round(p_valor_abertura,2),v_usuario.id,v_aberto_em,v_data_comercial) returning * into v_caixa;
 exception when unique_violation then
  get stacked diagnostics v_constraint=constraint_name;
  if v_constraint is distinct from 'fechamentos_caixa_um_aberto_por_restaurante_uidx' then raise; end if;
  raise exception 'Já existe um caixa aberto para este restaurante.';
 end;
 return v_caixa;
end $function$;
create or replace function public.fechar_caixa_v2(p_valor_contado numeric,p_observacoes text default null) returns public.fechamentos_caixa language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare v_usuario public.usuarios%rowtype; v_caixa public.fechamentos_caixa%rowtype; v_mov record; v_fechado_em timestamptz; v_esperado numeric; v_diferenca numeric; c_limite constant numeric:=99999999.99;
begin
 select u.* into v_usuario from public.usuarios u where u.id=auth.uid();
 if v_usuario.id is null or v_usuario.ativo is not true or v_usuario.role not in('dono','gerente') then raise exception 'Você não tem permissão para fechar o caixa.'; end if;
 if v_usuario.restaurante_id is null then raise exception 'Seu usuário não possui restaurante.'; end if;
 if p_valor_contado is null or p_valor_contado<0 or p_valor_contado>c_limite then raise exception 'Informe um valor contado válido.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_usuario.restaurante_id::text,8675309));
 select f.* into v_caixa from public.fechamentos_caixa f where f.restaurante_id=v_usuario.restaurante_id and f.status='aberto' for update;
 if v_caixa.id is null then raise exception 'Não existe caixa aberto para este restaurante.'; end if;
 v_fechado_em:=pg_catalog.clock_timestamp();
 select * into v_mov from public.calcular_caixa_dinheiro_interno(v_caixa.restaurante_id,v_caixa.aberto_em,v_fechado_em);
 v_esperado:=round(v_caixa.valor_abertura+v_mov.valor_liquido,2);
 if abs(v_esperado)>c_limite then raise exception 'O valor esperado excede o limite suportado.'; end if;
 v_diferenca:=round(p_valor_contado-v_esperado,2);
 if abs(v_diferenca)>c_limite then raise exception 'A diferença excede o limite suportado.'; end if;
 update public.fechamentos_caixa f set status='fechado',valor_dinheiro_esperado=v_esperado,valor_dinheiro_informado=round(p_valor_contado,2),diferenca=v_diferenca,observacoes=nullif(btrim(p_observacoes),''),fechado_por=v_usuario.id,fechado_em=v_fechado_em where f.id=v_caixa.id and f.status='aberto' returning * into v_caixa;
 if v_caixa.id is null then raise exception 'Não foi possível fechar o caixa.'; end if;
 return v_caixa;
end $function$;
drop trigger if exists trg_000_compatibilizar_escrita_caixa_legado on public.fechamentos_caixa;
drop function if exists public.compatibilizar_escrita_caixa_legado();
revoke all privileges on table public.fechamentos_caixa from public,anon,authenticated;
revoke all privileges on table public.movimentacoes_financeiras from public,anon,authenticated;
grant select on table public.fechamentos_caixa to authenticated;
grant select on table public.movimentacoes_financeiras to authenticated;
drop policy if exists staff_abre_caixa on public.fechamentos_caixa;
drop policy if exists staff_fecha_caixa on public.fechamentos_caixa;
drop policy if exists somente_gerente_dono_edita_financeiro on public.movimentacoes_financeiras;
do $c$ begin
 if not exists(select 1 from pg_catalog.pg_constraint where conrelid='public.fechamentos_caixa'::regclass and conname='fechamentos_caixa_valor_abertura_limite_check') then alter table public.fechamentos_caixa add constraint fechamentos_caixa_valor_abertura_limite_check check(valor_abertura>=0 and valor_abertura<=99999999.99); end if;
 if not exists(select 1 from pg_catalog.pg_constraint where conrelid='public.fechamentos_caixa'::regclass and conname='fechamentos_caixa_valores_fechamento_limite_check') then alter table public.fechamentos_caixa add constraint fechamentos_caixa_valores_fechamento_limite_check check((valor_dinheiro_informado is null or(valor_dinheiro_informado>=0 and valor_dinheiro_informado<=99999999.99))and(valor_dinheiro_esperado is null or abs(valor_dinheiro_esperado)<=99999999.99)and(diferenca is null or abs(diferenca)<=99999999.99)); end if;
 if not exists(select 1 from pg_catalog.pg_constraint where conrelid='public.fechamentos_caixa'::regclass and conname='fechamentos_caixa_status_campos_check') then alter table public.fechamentos_caixa add constraint fechamentos_caixa_status_campos_check check((status='aberto' and fechado_por is null and fechado_em is null and valor_dinheiro_esperado is null and valor_dinheiro_informado is null and diferenca is null)or(status='fechado' and fechado_por is not null and fechado_em is not null and valor_dinheiro_esperado is not null and valor_dinheiro_informado is not null and diferenca is not null)); end if;
end $c$;
alter table public.fechamentos_caixa alter column aberto_por set not null,alter column data_comercial set not null;
revoke all on function public.abrir_caixa_v2(numeric) from public,anon;
revoke all on function public.fechar_caixa_v2(numeric,text) from public,anon;
revoke all on function public.registrar_despesa_v2(text,numeric,text) from public,anon;
revoke all on function public.registrar_ajuste_financeiro_v1(uuid,text) from public,anon;
revoke all on function public.listar_movimentacoes_financeiras_v2(text) from public,anon;
revoke all on function public.listar_movimentos_dinheiro_sem_caixa_v1(date,date) from public,anon;
grant execute on function public.abrir_caixa_v2(numeric) to authenticated,service_role;
grant execute on function public.fechar_caixa_v2(numeric,text) to authenticated,service_role;
grant execute on function public.registrar_despesa_v2(text,numeric,text) to authenticated,service_role;
grant execute on function public.registrar_ajuste_financeiro_v1(uuid,text) to authenticated,service_role;
grant execute on function public.listar_movimentacoes_financeiras_v2(text) to authenticated,service_role;
grant execute on function public.listar_movimentos_dinheiro_sem_caixa_v1(date,date) to authenticated,service_role;
do $a$ declare v_table text; v_priv text; begin
 foreach v_table in array array['public.fechamentos_caixa','public.movimentacoes_financeiras'] loop
  foreach v_priv in array array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
   if has_table_privilege('anon',v_table,v_priv) then raise exception 'anon mantém % em %.',v_priv,v_table; end if;
   if has_table_privilege('authenticated',v_table,v_priv) then raise exception 'authenticated mantém % em %.',v_priv,v_table; end if;
  end loop;
  if has_table_privilege('anon',v_table,'SELECT') then raise exception 'anon mantém SELECT em %.',v_table; end if;
  if not has_table_privilege('authenticated',v_table,'SELECT') then raise exception 'authenticated perdeu SELECT em %.',v_table; end if;
  foreach v_priv in array array['SELECT','INSERT','UPDATE','DELETE'] loop if not has_table_privilege('service_role',v_table,v_priv) then raise exception 'service_role perdeu % em %.',v_priv,v_table; end if; end loop;
 end loop;
 if exists(select 1 from pg_catalog.pg_class c cross join lateral pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) x where c.oid in('public.fechamentos_caixa'::regclass,'public.movimentacoes_financeiras'::regclass) and x.grantee=0) then raise exception 'PUBLIC mantém privilégios nas tabelas financeiras.'; end if;
 if exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.fechamentos_caixa'::regclass and tgname='trg_000_compatibilizar_escrita_caixa_legado' and not tgisinternal) then raise exception 'O trigger temporário ainda existe.'; end if;
 if to_regprocedure('public.compatibilizar_escrita_caixa_legado()') is not null then raise exception 'A função temporária ainda existe.'; end if;
 if has_function_privilege('anon','public.abrir_caixa_v2(numeric)','EXECUTE') or has_function_privilege('anon','public.fechar_caixa_v2(numeric,text)','EXECUTE') or has_function_privilege('anon','public.registrar_despesa_v2(text,numeric,text)','EXECUTE') or has_function_privilege('anon','public.registrar_ajuste_financeiro_v1(uuid,text)','EXECUTE') or has_function_privilege('anon','public.listar_movimentacoes_financeiras_v2(text)','EXECUTE') or has_function_privilege('anon','public.listar_movimentos_dinheiro_sem_caixa_v1(date,date)','EXECUTE') then raise exception 'anon recuperou EXECUTE em RPC financeira.'; end if;
end $a$;
commit;