-- Travas operacionais de suspensão e contratação do módulo de motoboy.

create or replace function public.restaurante_operacional(p_restaurante_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select not r.pausado
    from public.restaurantes r
    where r.id = p_restaurante_id
  ), false);
$$;

create or replace function public.modulo_motoboy_operacional(p_restaurante_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select r.modulo_motoboy_ativo and not r.pausado
    from public.restaurantes r
    where r.id = p_restaurante_id
  ), false);
$$;

revoke all on function public.restaurante_operacional(uuid) from public, anon, authenticated;
revoke all on function public.modulo_motoboy_operacional(uuid) from public, anon;
grant execute on function public.restaurante_operacional(uuid) to service_role;
grant execute on function public.modulo_motoboy_operacional(uuid) to authenticated, service_role;

-- A maioria das policies multi-tenant existentes depende deste helper. Retornar NULL
-- durante a pausa faz sessões antigas perderem imediatamente o acesso por RLS.
create or replace function public.auth_restaurante_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.restaurante_id
  from public.usuarios u
  join public.restaurantes r on r.id = u.restaurante_id
  where u.id = auth.uid()
    and r.pausado = false;
$$;

revoke all on function public.auth_restaurante_id() from public, anon;
grant execute on function public.auth_restaurante_id() to authenticated, service_role;

create or replace function public.estado_acesso_restaurante_atual()
returns table (
  restaurante_id uuid,
  pausado boolean,
  modulo_motoboy_ativo boolean,
  whatsapp_suporte text
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.pausado, r.modulo_motoboy_ativo,
         '5541984213488'::text
  from public.usuarios u
  join public.restaurantes r on r.id = u.restaurante_id
  where u.id = auth.uid();
$$;

revoke all on function public.estado_acesso_restaurante_atual() from public, anon;
grant execute on function public.estado_acesso_restaurante_atual() to authenticated, service_role;

create or replace function public.trg_bloquear_operacao_restaurante()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  if auth.uid() is null or public.eh_super_admin() then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  v_restaurante_id := coalesce(
    case when tg_op <> 'DELETE' then (to_jsonb(new)->>'restaurante_id')::uuid end,
    case when tg_op <> 'INSERT' then (to_jsonb(old)->>'restaurante_id')::uuid end,
    (select u.restaurante_id from public.usuarios u where u.id = auth.uid())
  );

  if v_restaurante_id is not null then
    perform 1
    from public.restaurantes r
    where r.id = v_restaurante_id
    for share;
  end if;

  if v_restaurante_id is not null
     and not public.restaurante_operacional(v_restaurante_id) then
    raise exception using
      message = 'O restaurante está temporariamente suspenso. Entre em contato com a EAF Flow.',
      errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

revoke all on function public.trg_bloquear_operacao_restaurante() from public, anon, authenticated;

do $$
declare
  v_tabela text;
begin
  foreach v_tabela in array array[
    'categorias','clientes','enderecos_cliente','fechamentos_caixa',
    'grupos_tamanho','itens_pedido','itens_pedido_sabores',
    'movimentacoes_financeiras','opcoes_tamanho','pedido_promocoes',
    'pedidos','produto_precos','produtos','promocao_escopo_itens',
    'promocao_escopos','promocoes'
  ] loop
    if to_regclass('public.' || v_tabela) is not null then
      execute format(
        'create trigger bloquear_operacao_restaurante_pausado before insert or update or delete on public.%I for each row execute function public.trg_bloquear_operacao_restaurante()',
        v_tabela
      );
    end if;
  end loop;
end;
$$;

create or replace function public.trg_bloquear_operacao_motoboy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_caller_role public.user_role;
begin
  if public.eh_super_admin() then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_table_name = 'usuarios' then
    if (tg_op = 'INSERT' and new.role = 'motoboy')
       or (tg_op = 'UPDATE' and (
         new.role = 'motoboy'
         or old.role = 'motoboy'
       )) then
      v_restaurante_id := new.restaurante_id;
    else
      return coalesce(new, old);
    end if;
  elsif tg_table_name = 'motoboys' then
    if tg_op = 'DELETE' then
      v_restaurante_id := old.restaurante_id;
    else
      v_restaurante_id := new.restaurante_id;
    end if;
  else
    v_restaurante_id := coalesce(new.restaurante_id, old.restaurante_id);
    select u.role into v_caller_role from public.usuarios u where u.id = auth.uid();
    if v_caller_role is distinct from 'motoboy'
       and new.motoboy_id is not distinct from old.motoboy_id then
      return new;
    end if;
  end if;

  if v_restaurante_id is not null then
    perform 1
    from public.restaurantes r
    where r.id = v_restaurante_id
    for share;
  end if;

  if not public.modulo_motoboy_operacional(v_restaurante_id) then
    raise exception using
      message = 'O módulo de motoboy não está disponível para este restaurante.',
      errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

revoke all on function public.trg_bloquear_operacao_motoboy() from public, anon, authenticated;

create trigger bloquear_usuario_motoboy_sem_modulo
before insert or update on public.usuarios
for each row execute function public.trg_bloquear_operacao_motoboy();

create trigger bloquear_registro_motoboy_sem_modulo
before insert or update or delete on public.motoboys
for each row execute function public.trg_bloquear_operacao_motoboy();

create trigger bloquear_atribuicao_ou_update_motoboy_sem_modulo
before update on public.pedidos
for each row execute function public.trg_bloquear_operacao_motoboy();

-- Wrapper do pedido público: preserva retry idempotente antes de bloquear novos pedidos.
alter function public.criar_pedido_cliente_v1(
  uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text
) rename to _criar_pedido_cliente_v1_impl_estado_operacional;

revoke all on function public._criar_pedido_cliente_v1_impl_estado_operacional(
  uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text
) from public, anon, authenticated;

create function public.criar_pedido_cliente_v1(
  p_restaurante_id uuid,
  p_tipo public.tipo_pedido,
  p_forma_pagamento text,
  p_troco_para numeric,
  p_endereco jsonb,
  p_itens jsonb,
  p_chave_idempotencia text
) returns table(pedido_id uuid, numero_diario integer, total numeric, reutilizado boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chave text := btrim(coalesce(p_chave_idempotencia, ''));
begin
  if exists (
    select 1 from public.pedidos p
    where p.restaurante_id = p_restaurante_id
      and p.origem_criacao = 'cliente'
      and p.chave_idempotencia = v_chave
  ) then
    return query
    select * from public._criar_pedido_cliente_v1_impl_estado_operacional(
      p_restaurante_id, p_tipo, p_forma_pagamento, p_troco_para,
      p_endereco, p_itens, p_chave_idempotencia
    );
    return;
  end if;

  if not public.restaurante_operacional(p_restaurante_id) then
    raise exception using
      message = 'Este restaurante está temporariamente indisponível e não pode receber novos pedidos.',
      errcode = '55000';
  end if;

  return query
  select * from public._criar_pedido_cliente_v1_impl_estado_operacional(
    p_restaurante_id, p_tipo, p_forma_pagamento, p_troco_para,
    p_endereco, p_itens, p_chave_idempotencia
  );
end;
$$;

revoke all on function public.criar_pedido_cliente_v1(
  uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text
) from public, anon;
grant execute on function public.criar_pedido_cliente_v1(
  uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text
) to authenticated, service_role;

-- Pedido manual recebe checagem explícita antes de entrar no wrapper atual.
alter function public.criar_pedido_manual_v1(
  uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text
) rename to _criar_pedido_manual_v1_impl_estado_operacional;

revoke all on function public._criar_pedido_manual_v1_impl_estado_operacional(
  uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text
) from public, anon, authenticated;

create function public.criar_pedido_manual_v1(
  p_restaurante_id uuid,
  p_nome_cliente text,
  p_telefone_cliente text,
  p_tipo public.tipo_pedido,
  p_forma_pagamento text,
  p_troco_para numeric,
  p_observacoes text,
  p_endereco jsonb,
  p_itens jsonb,
  p_desconto jsonb,
  p_senha_autorizador text,
  p_chave_idempotencia text
) returns table(pedido_id uuid, numero_diario integer, total numeric, reutilizado boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_usuario uuid;
begin
  select u.restaurante_id into v_restaurante_usuario
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  if v_restaurante_usuario is distinct from p_restaurante_id then
    raise exception using message = 'Usuário sem permissão para este restaurante.', errcode = '42501';
  end if;
  if not public.restaurante_operacional(p_restaurante_id) then
    raise exception using
      message = 'O restaurante está temporariamente suspenso e não pode criar pedidos manuais.',
      errcode = '55000';
  end if;

  return query
  select * from public._criar_pedido_manual_v1_impl_estado_operacional(
    p_restaurante_id, p_nome_cliente, p_telefone_cliente, p_tipo,
    p_forma_pagamento, p_troco_para, p_observacoes, p_endereco, p_itens,
    p_desconto, p_senha_autorizador, p_chave_idempotencia
  );
end;
$$;

revoke all on function public.criar_pedido_manual_v1(
  uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text
) from public, anon;
grant execute on function public.criar_pedido_manual_v1(
  uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text
) to authenticated, service_role;

-- Cadastro e liberação diária precisam de checagem explícita porque são SECURITY DEFINER.
alter function public.criar_usuario_equipe(text,text,text,text,text,text,text)
  rename to _criar_usuario_equipe_impl_modulo_motoboy;
revoke all on function public._criar_usuario_equipe_impl_modulo_motoboy(text,text,text,text,text,text,text)
  from public, anon, authenticated;

create function public.criar_usuario_equipe(
  p_nome text, p_telefone text, p_email text, p_role text,
  p_senha text default null, p_veiculo text default null, p_placa text default null
) returns table(novo_usuario_id uuid, senha_provisoria text, email_gerado text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u where u.id = auth.uid() and u.ativo;
  if v_restaurante_id is null or not public.restaurante_operacional(v_restaurante_id) then
    raise exception using message = 'Restaurante sem acesso operacional.', errcode = '55000';
  end if;
  if p_role = 'motoboy' and not public.modulo_motoboy_operacional(v_restaurante_id) then
    raise exception using message = 'O módulo de motoboy não está disponível para este restaurante.', errcode = '55000';
  end if;
  return query select * from public._criar_usuario_equipe_impl_modulo_motoboy(
    p_nome,p_telefone,p_email,p_role,p_senha,p_veiculo,p_placa
  );
end;
$$;
revoke all on function public.criar_usuario_equipe(text,text,text,text,text,text,text) from public, anon;
grant execute on function public.criar_usuario_equipe(text,text,text,text,text,text,text)
  to authenticated, service_role;

alter function public.definir_liberacao_diaria_motoboy(uuid,boolean)
  rename to _definir_liberacao_diaria_motoboy_impl_modulo;
revoke all on function public._definir_liberacao_diaria_motoboy_impl_modulo(uuid,boolean)
  from public, anon, authenticated;

create function public.definir_liberacao_diaria_motoboy(p_motoboy_id uuid, p_liberado boolean)
returns table(liberado_em timestamptz, liberado_por uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u where u.id = auth.uid() and u.ativo;
  if not public.modulo_motoboy_operacional(v_restaurante_id) then
    raise exception using message = 'O módulo de motoboy não está disponível para este restaurante.', errcode = '55000';
  end if;
  return query select * from public._definir_liberacao_diaria_motoboy_impl_modulo(
    p_motoboy_id, p_liberado
  );
end;
$$;
revoke all on function public.definir_liberacao_diaria_motoboy(uuid,boolean) from public, anon;
grant execute on function public.definir_liberacao_diaria_motoboy(uuid,boolean)
  to authenticated;

alter function public.motoboy_esta_liberado_hoje()
  rename to _motoboy_esta_liberado_hoje_impl_modulo;
revoke all on function public._motoboy_esta_liberado_hoje_impl_modulo()
  from public, anon, authenticated;

create function public.motoboy_esta_liberado_hoje()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo and u.role = 'motoboy';
  if not public.modulo_motoboy_operacional(v_restaurante_id) then
    return false;
  end if;
  return public._motoboy_esta_liberado_hoje_impl_modulo();
end;
$$;
revoke all on function public.motoboy_esta_liberado_hoje() from public, anon;
grant execute on function public.motoboy_esta_liberado_hoje() to authenticated;

alter function public.definir_roteirizacao_motoboy(boolean)
  rename to _definir_roteirizacao_motoboy_impl_modulo;
revoke all on function public._definir_roteirizacao_motoboy_impl_modulo(boolean)
  from public, anon, authenticated;

create function public.definir_roteirizacao_motoboy(p_ativa boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u where u.id = auth.uid() and u.ativo;
  if not public.modulo_motoboy_operacional(v_restaurante_id) then
    raise exception using message = 'O módulo de motoboy não está disponível para este restaurante.', errcode = '55000';
  end if;
  return public._definir_roteirizacao_motoboy_impl_modulo(p_ativa);
end;
$$;
revoke all on function public.definir_roteirizacao_motoboy(boolean) from public, anon;
grant execute on function public.definir_roteirizacao_motoboy(boolean) to authenticated;

-- Defesa em profundidade nas policies específicas do motoboy.
alter policy motoboy_ve_proprio_registro on public.motoboys
  using (
    id = (select auth.uid())
    and public.modulo_motoboy_operacional(restaurante_id)
  );

alter policy motoboy_ve_pedidos_atribuidos on public.pedidos
  using (
    motoboy_id = (select auth.uid())
    and public.modulo_motoboy_operacional(restaurante_id)
  );

alter policy motoboy_atualiza_status_proprio_pedido on public.pedidos
  using (
    motoboy_id = (select auth.uid())
    and public.modulo_motoboy_operacional(restaurante_id)
  )
  with check (
    motoboy_id = (select auth.uid())
    and public.modulo_motoboy_operacional(restaurante_id)
  );

create or replace function public.motoboy_ve_cliente(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.pedidos p
    join public.motoboys m on m.id = p.motoboy_id
    where p.motoboy_id = auth.uid()
      and p.cliente_id = p_cliente_id
      and public.modulo_motoboy_operacional(m.restaurante_id)
  );
$$;
revoke all on function public.motoboy_ve_cliente(uuid) from public, anon;
grant execute on function public.motoboy_ve_cliente(uuid) to authenticated, service_role;

-- A função pública de status não expõe motivo interno.
create or replace function public.status_publico_restaurante(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_pausado boolean;
  v_status record;
begin
  select r.id, r.pausado into v_restaurante_id, v_pausado
  from public.restaurantes r
  where r.slug = lower(btrim(coalesce(p_slug, '')))
  limit 1;
  if v_restaurante_id is null then return null; end if;

  if v_pausado then
    return jsonb_build_object(
      'restaurante_id', v_restaurante_id,
      'aberto', false,
      'configurado', true,
      'horario_valido', true,
      'motivo', 'temporariamente_indisponivel',
      'mensagem', 'Restaurante temporariamente indisponível.',
      'servidor_agora', pg_catalog.now()
    );
  end if;

  select * into v_status
  from public._status_funcionamento_restaurante_em(v_restaurante_id, pg_catalog.now());
  return jsonb_build_object(
    'restaurante_id', v_restaurante_id,
    'aberto', v_status.aberto,
    'configurado', v_status.configurado,
    'horario_valido', v_status.horario_valido,
    'motivo', v_status.motivo,
    'proxima_abertura', v_status.proxima_abertura,
    'proxima_mudanca', v_status.proxima_mudanca,
    'mensagem', v_status.mensagem,
    'servidor_agora', v_status.servidor_agora
  );
end;
$$;
revoke all on function public.status_publico_restaurante(text) from public;
grant execute on function public.status_publico_restaurante(text) to anon, authenticated, service_role;

-- RPCs SECURITY DEFINER de leitura usadas diretamente pelo painel precisam da
-- mesma trava da RLS. As implementações anteriores ficam privadas e são
-- chamadas somente depois da validação operacional.
create or replace function public.exigir_acesso_operacional_painel()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.usuarios u
    join public.restaurantes r on r.id = u.restaurante_id
    where u.id = auth.uid()
      and u.ativo
      and not r.pausado
  ) then
    raise exception using message = 'Restaurante temporariamente indisponível.', errcode = '55000';
  end if;
end;
$$;
revoke all on function public.exigir_acesso_operacional_painel()
  from public, anon, authenticated, service_role;

alter function public.relatorio_financeiro_v2(date, date)
  rename to _relatorio_financeiro_v2_impl_pausa;
revoke all on function public._relatorio_financeiro_v2_impl_pausa(date, date)
  from public, anon, authenticated, service_role;
create function public.relatorio_financeiro_v2(
  p_data_inicio date default null,
  p_data_fim date default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.exigir_acesso_operacional_painel();
  return public._relatorio_financeiro_v2_impl_pausa(p_data_inicio, p_data_fim);
end;
$$;
revoke all on function public.relatorio_financeiro_v2(date, date) from public, anon;
grant execute on function public.relatorio_financeiro_v2(date, date) to authenticated;

alter function public.relatorio_cancelamentos_v1(text, date, date)
  rename to _relatorio_cancelamentos_v1_impl_pausa;
revoke all on function public._relatorio_cancelamentos_v1_impl_pausa(text, date, date)
  from public, anon, authenticated, service_role;
create function public.relatorio_cancelamentos_v1(
  p_periodo text default 'hoje',
  p_data_inicio date default null,
  p_data_fim date default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.exigir_acesso_operacional_painel();
  return public._relatorio_cancelamentos_v1_impl_pausa(p_periodo, p_data_inicio, p_data_fim);
end;
$$;
revoke all on function public.relatorio_cancelamentos_v1(text, date, date) from public, anon;
grant execute on function public.relatorio_cancelamentos_v1(text, date, date) to authenticated;

alter function public.listar_movimentacoes_financeiras_v2(text)
  rename to _listar_movimentacoes_financeiras_v2_impl_pausa;
revoke all on function public._listar_movimentacoes_financeiras_v2_impl_pausa(text)
  from public, anon, authenticated, service_role;
create function public.listar_movimentacoes_financeiras_v2(p_periodo text default 'hoje')
returns table(
  id uuid,
  tipo text,
  descricao text,
  valor numeric,
  pedido_id uuid,
  criado_em timestamptz,
  forma_pagamento text,
  origem text,
  criado_por uuid,
  ajuste_de_id uuid,
  motivo_ajuste text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.exigir_acesso_operacional_painel();
  return query
  select *
  from public._listar_movimentacoes_financeiras_v2_impl_pausa(p_periodo);
end;
$$;
revoke all on function public.listar_movimentacoes_financeiras_v2(text) from public, anon;
grant execute on function public.listar_movimentacoes_financeiras_v2(text) to authenticated;
