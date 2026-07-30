-- =============================================================================
-- MIGRATION A — backend aditivo e retrocompatível.
-- Parte 1 de 3 (A: aditivo / B: frontend / C: endurecimento).
--
-- Objetivo: preparar a infraestrutura para que cada SESSÃO do app do cliente
-- veja somente os pedidos e endereços que ELA criou no dia comercial atual,
-- sem alterar ainda nenhuma policy, helper ou fluxo hoje em produção.
--
-- Regra de negócio: telefone continua reunindo o cliente canônico da loja
-- (histórico, CRM); a sessão (auth_user_id) é quem determina o que o APP
-- mostra. Corte do dia comercial: 07:00 America/Sao_Paulo.
--
-- Esta migration NÃO altera:
--   - auth_cliente_ids() / auth_cliente_id(uuid) / auth_cliente_restaurantes();
--   - nenhuma policy existente;
--   - o acesso direto atual a "clientes";
--   - o fluxo atual de pedidos (a v2 mantém a mesma assinatura de retorno).
-- É 100% retrocompatível com o frontend hoje publicado.
-- =============================================================================

set lock_timeout = '5s';
set statement_timeout = '90s';

create temp table _migracao_a_before as
select
  (select count(*) from public.clientes) as clientes,
  (select count(*) from public.cliente_sessoes) as cliente_sessoes,
  (select count(*) from public.pedidos) as pedidos,
  (select count(*) from public.enderecos_cliente) as enderecos,
  (select count(*) from pg_policies where schemaname = 'public') as policies,
  (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'auth_cliente_ids') as fp_auth_cliente_ids,
  (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'auth_cliente_id') as fp_auth_cliente_id,
  (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'auth_cliente_restaurantes') as fp_auth_cliente_restaurantes;

-- =============================================================================
-- 1) dia_comercial_atual() — vira o dia às 07:00 America/Sao_Paulo.
-- Único ponto desta migration liberado para "anon": o app consulta a data
-- comercial antes mesmo de haver sessão (no boot da PWA).
-- =============================================================================
create or replace function public.dia_comercial_atual()
returns date
language sql
stable
set search_path to pg_catalog, public
as $$
  select ((now() at time zone 'America/Sao_Paulo') - interval '7 hours')::date
$$;

revoke all on function public.dia_comercial_atual() from public;
grant execute on function public.dia_comercial_atual() to anon, authenticated, service_role;

-- =============================================================================
-- 2) Novas colunas — todas nullable, sem default retroativo.
-- Sessões, pedidos e endereços já existentes permanecem com estas colunas
-- em NULL: elas não passam a ser "válidas" automaticamente pelo simples fato
-- de a coluna existir (dia_comercial NULL nunca bate com dia_comercial_atual()).
-- =============================================================================
alter table public.cliente_sessoes
  add column if not exists dia_comercial date,
  add column if not exists nome_informado text,
  add column if not exists telefone_informado text;

alter table public.pedidos
  add column if not exists cliente_sessao_auth_user_id uuid,
  add column if not exists cliente_sessao_dia_comercial date;

alter table public.enderecos_cliente
  add column if not exists cliente_sessao_auth_user_id uuid,
  add column if not exists cliente_sessao_dia_comercial date;

-- =============================================================================
-- 3) Índices de apoio às policies que a Migration C vai introduzir.
-- =============================================================================
create index if not exists pedidos_cliente_sessao_dia_idx
  on public.pedidos (cliente_sessao_auth_user_id, cliente_sessao_dia_comercial);

create index if not exists enderecos_cliente_sessao_dia_idx
  on public.enderecos_cliente (cliente_sessao_auth_user_id, cliente_sessao_dia_comercial);

create index if not exists cliente_sessoes_dia_comercial_idx
  on public.cliente_sessoes (restaurante_id, dia_comercial);

-- =============================================================================
-- 4) criar_ou_atualizar_cliente_sessao_v3 — nova RPC.
-- Busca/cria o cliente canônico por (restaurante, telefone), mas NUNCA
-- sobrescreve um canônico já existente, e nunca expõe nome/telefone oficiais
-- da tabela "clientes" — devolve apenas o que a PRÓPRIA sessão digitou.
-- =============================================================================
create or replace function public.criar_ou_atualizar_cliente_sessao_v3(
  p_restaurante_id uuid,
  p_nome text,
  p_telefone text
)
returns table(cliente_id uuid, nome_informado text, telefone_informado text, dia_comercial date)
language plpgsql
security definer
set search_path to pg_catalog, public
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_telefone text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_dia_comercial date := public.dia_comercial_atual();
  v_cliente public.clientes%rowtype;
begin
  if v_auth_user_id is null then
    raise exception using message = 'Sessão inválida.', errcode = '28000';
  end if;

  if p_restaurante_id is null or v_nome = '' or length(v_telefone) < 10 then
    raise exception using message = 'Não foi possível concluir a identificação com os dados informados.', errcode = 'P0001';
  end if;

  perform 1
  from public.restaurantes r
  where r.id = p_restaurante_id;

  if not found then
    raise exception using message = 'Não foi possível concluir a identificação com os dados informados.', errcode = 'P0001';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'cliente-telefone:' || p_restaurante_id::text || ':' || v_telefone,
      0
    )
  );

  select c.*
  into v_cliente
  from public.clientes c
  where c.restaurante_id = p_restaurante_id
    and c.telefone = v_telefone
  for update;

  if v_cliente.id is null then
    begin
      insert into public.clientes(
        nome,
        telefone,
        restaurante_id,
        auth_user_id
      )
      values (
        v_nome,
        v_telefone,
        p_restaurante_id,
        null
      )
      returning * into v_cliente;
    exception when unique_violation then
      select c.*
      into v_cliente
      from public.clientes c
      where c.restaurante_id = p_restaurante_id
        and c.telefone = v_telefone
      for update;

      if v_cliente.id is null then
        raise;
      end if;
    end;
  end if;
  -- Cliente canônico encontrado ou recém-criado: nunca sobrescrito a partir daqui.

  insert into public.cliente_sessoes(
    auth_user_id,
    restaurante_id,
    cliente_id,
    dia_comercial,
    nome_informado,
    telefone_informado,
    criado_em,
    atualizado_em
  )
  values (
    v_auth_user_id,
    p_restaurante_id,
    v_cliente.id,
    v_dia_comercial,
    v_nome,
    v_telefone,
    now(),
    now()
  )
  on conflict (auth_user_id, restaurante_id)
  do update
  set cliente_id = excluded.cliente_id,
      dia_comercial = excluded.dia_comercial,
      nome_informado = excluded.nome_informado,
      telefone_informado = excluded.telefone_informado,
      atualizado_em = now();

  return query
  select v_cliente.id, v_nome, v_telefone, v_dia_comercial;
end;
$$;

revoke all on function public.criar_ou_atualizar_cliente_sessao_v3(uuid, text, text)
  from public, anon;
grant execute on function public.criar_ou_atualizar_cliente_sessao_v3(uuid, text, text)
  to authenticated, service_role;

-- =============================================================================
-- 5) cliente_sessao_atual — leitura pura, sem JOIN em "clientes".
-- Só retorna linha quando a sessão já foi confirmada NESTE dia comercial.
-- =============================================================================
create or replace function public.cliente_sessao_atual(p_restaurante_id uuid)
returns table(cliente_id uuid, nome_informado text, telefone_informado text, dia_comercial date)
language sql
stable
security definer
set search_path to pg_catalog, public
as $$
  select cs.cliente_id, cs.nome_informado, cs.telefone_informado, cs.dia_comercial
  from public.cliente_sessoes cs
  where cs.auth_user_id = auth.uid()
    and cs.restaurante_id = p_restaurante_id
    and cs.dia_comercial = public.dia_comercial_atual()
$$;

revoke all on function public.cliente_sessao_atual(uuid) from public, anon;
grant execute on function public.cliente_sessao_atual(uuid) to authenticated, service_role;

-- =============================================================================
-- 6) v2 — mantida com a MESMA assinatura de retorno (retrocompatibilidade).
-- CREATE OR REPLACE é seguro aqui porque TABLE(id uuid, nome text, telefone text)
-- não muda. Internamente passa a: não sobrescrever o canônico existente,
-- preencher dia_comercial/nome_informado/telefone_informado na sessão, e
-- retornar o id canônico + os dados DIGITADOS nesta sessão (não os oficiais).
-- =============================================================================
create or replace function public.criar_ou_atualizar_cliente_sessao_v2(
  p_restaurante_id uuid,
  p_nome text,
  p_telefone text
)
returns table(id uuid, nome text, telefone text)
language plpgsql
security definer
set search_path to pg_catalog, public
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_telefone text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_dia_comercial date := public.dia_comercial_atual();
  v_cliente public.clientes%rowtype;
begin
  if v_auth_user_id is null then
    raise exception using message = 'Sessão inválida.', errcode = '28000';
  end if;

  if p_restaurante_id is null or v_nome = '' or length(v_telefone) < 10 then
    raise exception using message = 'Não foi possível concluir o cadastro com os dados informados.', errcode = 'P0001';
  end if;

  perform 1
  from public.restaurantes r
  where r.id = p_restaurante_id;

  if not found then
    raise exception using message = 'Não foi possível concluir o cadastro com os dados informados.', errcode = 'P0001';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'cliente-telefone:' || p_restaurante_id::text || ':' || v_telefone,
      0
    )
  );

  select c.*
  into v_cliente
  from public.clientes c
  where c.restaurante_id = p_restaurante_id
    and c.telefone = v_telefone
  for update;

  if v_cliente.id is null then
    begin
      insert into public.clientes(
        nome,
        telefone,
        restaurante_id,
        auth_user_id
      )
      values (
        v_nome,
        v_telefone,
        p_restaurante_id,
        null
      )
      returning * into v_cliente;
    exception when unique_violation then
      select c.*
      into v_cliente
      from public.clientes c
      where c.restaurante_id = p_restaurante_id
        and c.telefone = v_telefone
      for update;

      if v_cliente.id is null then
        raise;
      end if;
    end;
  end if;
  -- Compatibilidade com o comportamento novo: não sobrescreve mais o canônico.

  insert into public.cliente_sessoes(
    auth_user_id,
    restaurante_id,
    cliente_id,
    dia_comercial,
    nome_informado,
    telefone_informado,
    criado_em,
    atualizado_em
  )
  values (
    v_auth_user_id,
    p_restaurante_id,
    v_cliente.id,
    v_dia_comercial,
    v_nome,
    v_telefone,
    now(),
    now()
  )
  on conflict (auth_user_id, restaurante_id)
  do update
  set cliente_id = excluded.cliente_id,
      dia_comercial = excluded.dia_comercial,
      nome_informado = excluded.nome_informado,
      telefone_informado = excluded.telefone_informado,
      atualizado_em = now();

  return query
  select v_cliente.id, v_nome, v_telefone;
end;
$$;

-- Grants inalterados (a assinatura é a mesma; reaplicados por clareza/segurança).
revoke all on function public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
  from public, anon;
grant execute on function public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
  to authenticated, service_role;

-- =============================================================================
-- Asserções: qualquer divergência aborta a migration inteira.
-- Confirma que esta etapa foi puramente aditiva.
-- =============================================================================
do $$
declare
  v_before record;
begin
  select * into v_before from _migracao_a_before;

  if (select count(*) from public.clientes) <> v_before.clientes then
    raise exception 'Validação falhou: quantidade de clientes mudou (migration deveria ser aditiva).';
  end if;

  if (select count(*) from public.cliente_sessoes) <> v_before.cliente_sessoes then
    raise exception 'Validação falhou: quantidade de cliente_sessoes mudou.';
  end if;

  if (select count(*) from public.pedidos) <> v_before.pedidos then
    raise exception 'Validação falhou: quantidade de pedidos mudou.';
  end if;

  if (select count(*) from public.enderecos_cliente) <> v_before.enderecos then
    raise exception 'Validação falhou: quantidade de endereços mudou.';
  end if;

  if (select count(*) from pg_policies where schemaname = 'public') <> v_before.policies then
    raise exception 'Validação falhou: número de policies mudou — Migration A não pode tocar policies.';
  end if;

  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'auth_cliente_ids') <> v_before.fp_auth_cliente_ids then
    raise exception 'Validação falhou: auth_cliente_ids() foi alterada.';
  end if;

  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'auth_cliente_id') <> v_before.fp_auth_cliente_id then
    raise exception 'Validação falhou: auth_cliente_id(uuid) foi alterada.';
  end if;

  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'auth_cliente_restaurantes') <> v_before.fp_auth_cliente_restaurantes then
    raise exception 'Validação falhou: auth_cliente_restaurantes() foi alterada.';
  end if;
end;
$$;
