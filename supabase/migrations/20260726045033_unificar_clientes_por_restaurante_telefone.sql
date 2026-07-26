set lock_timeout = '5s';
set statement_timeout = '90s';

create temp table _clientes_migracao_before as
select
  (select count(*) from public.clientes) as clientes,
  (select count(*) from public.pedidos) as pedidos,
  (select count(*) from public.enderecos_cliente) as enderecos,
  (select count(*) from public.clientes where auth_user_id is not null) as sessoes_legadas,
  (select coalesce(sum(qtd - 1), 0) from (
     select count(*) as qtd
     from public.clientes
     where telefone is not null
     group by restaurante_id, regexp_replace(telefone, '[^0-9]', '', 'g')
     having count(*) > 1
   ) d) as clientes_duplicados;

lock table public.clientes in share row exclusive mode;
lock table public.pedidos in share row exclusive mode;
lock table public.enderecos_cliente in share row exclusive mode;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.clientes'::regclass
      and conname = 'clientes_id_restaurante_id_key'
  ) then
    alter table public.clientes
      add constraint clientes_id_restaurante_id_key unique (id, restaurante_id);
  end if;
end;
$$;

create table public.cliente_sessoes (
  auth_user_id uuid not null,
  restaurante_id uuid not null,
  cliente_id uuid not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint cliente_sessoes_pkey primary key (auth_user_id, restaurante_id),
  constraint cliente_sessoes_auth_user_id_fkey foreign key (auth_user_id)
    references auth.users(id) on delete cascade,
  constraint cliente_sessoes_cliente_restaurante_fkey foreign key (cliente_id, restaurante_id)
    references public.clientes(id, restaurante_id) on delete cascade
);

create index cliente_sessoes_cliente_id_idx
  on public.cliente_sessoes(cliente_id);

alter table public.cliente_sessoes enable row level security;
revoke all on table public.cliente_sessoes from public, anon, authenticated;
grant all on table public.cliente_sessoes to service_role;

insert into public.cliente_sessoes(
  auth_user_id,
  restaurante_id,
  cliente_id,
  criado_em,
  atualizado_em
)
select
  c.auth_user_id,
  c.restaurante_id,
  c.id,
  c.criado_em,
  now()
from public.clientes c
where c.auth_user_id is not null;

create temp table _cliente_merge as
with stats as (
  select
    c.id,
    c.restaurante_id,
    regexp_replace(c.telefone, '[^0-9]', '', 'g') as telefone_normalizado,
    c.criado_em,
    (select count(*) from public.pedidos p where p.cliente_id = c.id) as pedidos,
    (select count(*) from public.enderecos_cliente e where e.cliente_id = c.id) as enderecos
  from public.clientes c
  where c.telefone is not null
), ranked as (
  select
    s.*,
    row_number() over (
      partition by s.restaurante_id, s.telefone_normalizado
      order by s.pedidos desc, s.enderecos desc, s.criado_em asc, s.id
    ) as rn
  from stats s
), canonicos as (
  select
    restaurante_id,
    telefone_normalizado,
    id as canonical_id
  from ranked
  where rn = 1
)
select
  r.id as duplicate_id,
  c.canonical_id,
  r.restaurante_id,
  r.telefone_normalizado
from ranked r
join canonicos c using (restaurante_id, telefone_normalizado)
where r.rn > 1;

update public.cliente_sessoes cs
set cliente_id = m.canonical_id,
    atualizado_em = now()
from _cliente_merge m
where cs.cliente_id = m.duplicate_id;

update public.pedidos p
set cliente_id = m.canonical_id
from _cliente_merge m
where p.cliente_id = m.duplicate_id;

update public.enderecos_cliente e
set cliente_id = m.canonical_id
from _cliente_merge m
where e.cliente_id = m.duplicate_id;

delete from public.clientes c
using _cliente_merge m
where c.id = m.duplicate_id;

update public.clientes
set telefone = nullif(regexp_replace(coalesce(telefone, ''), '[^0-9]', '', 'g'), '')
where telefone is distinct from nullif(regexp_replace(coalesce(telefone, ''), '[^0-9]', '', 'g'), '');

create or replace function public.normalizar_telefone_cliente_trigger()
returns trigger
language plpgsql
set search_path to pg_catalog, public
as $$
begin
  new.telefone := nullif(regexp_replace(coalesce(new.telefone, ''), '[^0-9]', '', 'g'), '');

  if new.telefone is not null and length(new.telefone) < 10 then
    raise exception using message = 'Telefone inválido.', errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_normalizar_telefone_cliente on public.clientes;
create trigger trg_normalizar_telefone_cliente
before insert or update of telefone on public.clientes
for each row
execute function public.normalizar_telefone_cliente_trigger();

create unique index clientes_restaurante_telefone_uidx
  on public.clientes(restaurante_id, telefone)
  where telefone is not null;

create or replace function public.auth_cliente_ids()
returns setof uuid
language sql
stable
security definer
set search_path to pg_catalog, public
as $$
  select cs.cliente_id
  from public.cliente_sessoes cs
  where cs.auth_user_id = auth.uid()
$$;

create or replace function public.auth_cliente_id(p_restaurante_id uuid)
returns uuid
language sql
stable
security definer
set search_path to pg_catalog, public
as $$
  select cs.cliente_id
  from public.cliente_sessoes cs
  where cs.auth_user_id = auth.uid()
    and cs.restaurante_id = p_restaurante_id
  limit 1
$$;

create or replace function public.auth_cliente_restaurantes()
returns setof uuid
language sql
stable
security definer
set search_path to pg_catalog, public
as $$
  select cs.restaurante_id
  from public.cliente_sessoes cs
  where cs.auth_user_id = auth.uid()
$$;

revoke all on function public.auth_cliente_ids() from public, anon;
revoke all on function public.auth_cliente_id(uuid) from public, anon;
revoke all on function public.auth_cliente_restaurantes() from public, anon;
grant execute on function public.auth_cliente_ids() to authenticated, service_role;
grant execute on function public.auth_cliente_id(uuid) to authenticated, service_role;
grant execute on function public.auth_cliente_restaurantes() to authenticated, service_role;

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

  if v_cliente.id is not null then
    update public.clientes c
    set nome = v_nome
    where c.id = v_cliente.id
    returning c.* into v_cliente;
  else
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

      update public.clientes c
      set nome = v_nome
      where c.id = v_cliente.id
      returning c.* into v_cliente;
    end;
  end if;

  insert into public.cliente_sessoes(
    auth_user_id,
    restaurante_id,
    cliente_id,
    criado_em,
    atualizado_em
  )
  values (
    v_auth_user_id,
    p_restaurante_id,
    v_cliente.id,
    now(),
    now()
  )
  on conflict (auth_user_id, restaurante_id)
  do update
  set cliente_id = excluded.cliente_id,
      atualizado_em = now();

  return query
  select v_cliente.id, v_cliente.nome, v_cliente.telefone;
end;
$$;

revoke all on function public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
  from public, anon;
grant execute on function public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
  to authenticated, service_role;

-- Clientes: sessão vinculada vê e atualiza o cadastro canônico.
drop policy if exists cliente_atualiza_proprio_cadastro on public.clientes;
drop policy if exists cliente_cria_proprio_cadastro on public.clientes;
drop policy if exists cliente_edita_proprio_cadastro on public.clientes;
drop policy if exists cliente_ve_proprio_cadastro on public.clientes;

create policy cliente_ve_proprio_cadastro
on public.clientes
for select
using (id in (select public.auth_cliente_ids()));

create policy cliente_edita_proprio_cadastro
on public.clientes
for update
using (id in (select public.auth_cliente_ids()))
with check (id in (select public.auth_cliente_ids()));

-- Endereços.
drop policy if exists cliente_apaga_proprios_enderecos on public.enderecos_cliente;
drop policy if exists cliente_cria_proprios_enderecos on public.enderecos_cliente;
drop policy if exists cliente_edita_proprios_enderecos on public.enderecos_cliente;
drop policy if exists cliente_gerencia_proprios_enderecos on public.enderecos_cliente;
drop policy if exists cliente_ve_proprios_enderecos on public.enderecos_cliente;

create policy cliente_ve_proprios_enderecos
on public.enderecos_cliente
for select
using (cliente_id in (select public.auth_cliente_ids()));

create policy cliente_cria_proprios_enderecos
on public.enderecos_cliente
for insert
with check (cliente_id in (select public.auth_cliente_ids()));

create policy cliente_edita_proprios_enderecos
on public.enderecos_cliente
for update
using (cliente_id in (select public.auth_cliente_ids()))
with check (cliente_id in (select public.auth_cliente_ids()));

create policy cliente_apaga_proprios_enderecos
on public.enderecos_cliente
for delete
using (cliente_id in (select public.auth_cliente_ids()));

-- Pedidos.
drop policy if exists cliente_cria_pedido on public.pedidos;
drop policy if exists cliente_ve_proprios_pedidos on public.pedidos;

create policy cliente_cria_pedido
on public.pedidos
for insert
with check (
  cliente_id in (select public.auth_cliente_ids())
  and restaurante_id in (select public.auth_cliente_restaurantes())
);

create policy cliente_ve_proprios_pedidos
on public.pedidos
for select
using (cliente_id in (select public.auth_cliente_ids()));

-- Itens.
drop policy if exists cliente_cria_itens_proprios_pedidos on public.itens_pedido;
drop policy if exists cliente_insere_itens_proprio_pedido on public.itens_pedido;
drop policy if exists cliente_ve_itens_proprio_pedido on public.itens_pedido;
drop policy if exists cliente_ve_itens_proprios_pedidos on public.itens_pedido;

create policy cliente_insere_itens_proprio_pedido
on public.itens_pedido
for insert
with check (
  pedido_id in (
    select p.id
    from public.pedidos p
    where p.cliente_id in (select public.auth_cliente_ids())
  )
);

create policy cliente_ve_itens_proprio_pedido
on public.itens_pedido
for select
using (
  pedido_id in (
    select p.id
    from public.pedidos p
    where p.cliente_id in (select public.auth_cliente_ids())
  )
);

-- Sabores.
drop policy if exists cliente_cria_sabores_proprios_itens on public.itens_pedido_sabores;
drop policy if exists cliente_ve_sabores_proprios_itens on public.itens_pedido_sabores;

create policy cliente_cria_sabores_proprios_itens
on public.itens_pedido_sabores
for insert
with check (
  item_pedido_id in (
    select ip.id
    from public.itens_pedido ip
    join public.pedidos p on p.id = ip.pedido_id
    where p.cliente_id in (select public.auth_cliente_ids())
  )
);

create policy cliente_ve_sabores_proprios_itens
on public.itens_pedido_sabores
for select
using (
  item_pedido_id in (
    select ip.id
    from public.itens_pedido ip
    join public.pedidos p on p.id = ip.pedido_id
    where p.cliente_id in (select public.auth_cliente_ids())
  )
);

-- Promoções vinculadas ao pedido.
drop policy if exists sel_pedido_promocoes_cliente on public.pedido_promocoes;

create policy sel_pedido_promocoes_cliente
on public.pedido_promocoes
for select
using (
  pedido_id in (
    select p.id
    from public.pedidos p
    where p.cliente_id in (select public.auth_cliente_ids())
  )
);

-- Histórico de status.
drop policy if exists cliente_ve_historico_proprio_pedido on public.pedido_status_historico;

create policy cliente_ve_historico_proprio_pedido
on public.pedido_status_historico
for select
using (
  pedido_id in (
    select p.id
    from public.pedidos p
    where p.cliente_id in (select public.auth_cliente_ids())
  )
);

-- Asserções: qualquer divergência aborta a migration inteira.
do $$
declare
  v_before record;
  v_duplicidades bigint;
  v_politicas_legadas bigint;
begin
  select * into v_before from _clientes_migracao_before;

  if (select count(*) from public.pedidos) <> v_before.pedidos then
    raise exception 'Validação falhou: quantidade de pedidos mudou.';
  end if;

  if (select count(*) from public.enderecos_cliente) <> v_before.enderecos then
    raise exception 'Validação falhou: quantidade de endereços mudou.';
  end if;

  if (select count(*) from public.clientes) <> v_before.clientes - v_before.clientes_duplicados then
    raise exception 'Validação falhou: quantidade de clientes consolidada divergiu.';
  end if;

  if (select count(*) from public.cliente_sessoes) <> v_before.sessoes_legadas then
    raise exception 'Validação falhou: vínculos de sessão não foram preservados.';
  end if;

  select count(*) into v_duplicidades
  from (
    select 1
    from public.clientes
    where telefone is not null
    group by restaurante_id, telefone
    having count(*) > 1
  ) d;

  if v_duplicidades <> 0 then
    raise exception 'Validação falhou: ainda existem clientes duplicados.';
  end if;

  select count(*) into v_politicas_legadas
  from pg_policies
  where schemaname = 'public'
    and (
      coalesce(qual, '') ilike '%clientes.auth_user_id%'
      or coalesce(with_check, '') ilike '%clientes.auth_user_id%'
      or coalesce(qual, '') ilike '%auth_user_id = auth.uid()%'
      or coalesce(with_check, '') ilike '%auth_user_id = auth.uid()%'
    );

  if v_politicas_legadas <> 0 then
    raise exception 'Validação falhou: políticas antigas ainda dependem de clientes.auth_user_id.';
  end if;
end;
$$;