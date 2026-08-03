-- Fundação do catálogo de recursos, pacotes por plano e exceções por restaurante.
-- Esta migration apenas prepara autorização futura; não altera os fluxos operacionais atuais.

alter table public.planos
  add column descricao_curta text null,
  add constraint planos_descricao_curta_check
    check (
      descricao_curta is null
      or char_length(btrim(descricao_curta)) between 1 and 180
    );

create table public.recursos (
  codigo text primary key,
  nome text not null,
  descricao text not null default '',
  ordem smallint not null unique,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid null references public.admins_plataforma(id) on delete set null,
  constraint recursos_codigo_formato_check
    check (codigo = lower(codigo) and codigo ~ '^[a-z][a-z0-9_]*$'),
  constraint recursos_nome_check
    check (char_length(btrim(nome)) between 1 and 80),
  constraint recursos_descricao_check
    check (char_length(descricao) <= 240),
  constraint recursos_ordem_check
    check (ordem > 0)
);

create index recursos_atualizado_por_idx
  on public.recursos (atualizado_por)
  where atualizado_por is not null;

create table public.plano_recursos (
  plano_codigo text not null,
  recurso_codigo text not null,
  incluido boolean not null default false,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid null,
  primary key (plano_codigo, recurso_codigo),
  constraint plano_recursos_plano_codigo_fkey
    foreign key (plano_codigo) references public.planos(codigo) on delete restrict,
  constraint plano_recursos_recurso_codigo_fkey
    foreign key (recurso_codigo) references public.recursos(codigo) on delete restrict,
  constraint plano_recursos_atualizado_por_fkey
    foreign key (atualizado_por) references public.admins_plataforma(id) on delete set null
);

create index plano_recursos_recurso_incluido_idx
  on public.plano_recursos (recurso_codigo, incluido, plano_codigo);

create index plano_recursos_atualizado_por_idx
  on public.plano_recursos (atualizado_por)
  where atualizado_por is not null;

create table public.restaurante_recursos (
  restaurante_id uuid not null,
  recurso_codigo text not null,
  decisao text not null,
  motivo text null,
  alterado_em timestamptz not null default now(),
  alterado_por uuid not null,
  primary key (restaurante_id, recurso_codigo),
  constraint restaurante_recursos_restaurante_id_fkey
    foreign key (restaurante_id) references public.restaurantes(id) on delete cascade,
  constraint restaurante_recursos_recurso_codigo_fkey
    foreign key (recurso_codigo) references public.recursos(codigo) on delete restrict,
  constraint restaurante_recursos_alterado_por_fkey
    foreign key (alterado_por) references public.admins_plataforma(id) on delete restrict,
  constraint restaurante_recursos_decisao_check
    check (decisao in ('liberar', 'bloquear')),
  constraint restaurante_recursos_motivo_check
    check (
      motivo is null
      or char_length(btrim(motivo)) between 1 and 500
    )
);

create index restaurante_recursos_recurso_codigo_idx
  on public.restaurante_recursos (recurso_codigo, restaurante_id);

create index restaurante_recursos_alterado_por_idx
  on public.restaurante_recursos (alterado_por);

alter table public.recursos enable row level security;
alter table public.plano_recursos enable row level security;
alter table public.restaurante_recursos enable row level security;

revoke all on table public.recursos from public, anon, authenticated;
revoke all on table public.plano_recursos from public, anon, authenticated;
revoke all on table public.restaurante_recursos from public, anon, authenticated;

grant all on table public.recursos to service_role;
grant all on table public.plano_recursos to service_role;
grant all on table public.restaurante_recursos to service_role;

insert into public.recursos (codigo, nome, descricao, ordem, ativo)
values
  ('pedido_manual', 'Pedido Manual', 'Criação de pedidos pela equipe do restaurante', 1, true),
  ('app_motoboy', 'App do Motoboy', 'Acesso ao aplicativo e às operações dos entregadores', 2, true);

insert into public.plano_recursos (plano_codigo, recurso_codigo, incluido)
values
  ('essencial', 'pedido_manual', false),
  ('essencial', 'app_motoboy', false),
  ('profissional', 'pedido_manual', true),
  ('profissional', 'app_motoboy', false),
  ('premium', 'pedido_manual', true),
  ('premium', 'app_motoboy', true);

create function public._resolver_recurso_restaurante(
  p_restaurante_id uuid,
  p_recurso_codigo text
)
returns table (
  restaurante_id uuid,
  restaurante_pausado boolean,
  plano_codigo text,
  plano_nome text,
  plano_medalha text,
  plano_preco_mensal numeric(10,2),
  recurso_codigo text,
  recurso_nome text,
  recurso_descricao text,
  recurso_ordem smallint,
  disponivel boolean,
  origem text,
  decisao_individual text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    r.id,
    r.pausado,
    p.codigo,
    p.nome,
    p.medalha,
    p.preco_mensal,
    rc.codigo,
    rc.nome,
    rc.descricao,
    rc.ordem,
    case
      when r.pausado then false
      when not p.ativo then false
      when not rc.ativo then false
      when rr.decisao = 'bloquear' then false
      when rr.decisao = 'liberar' then true
      when coalesce(pr.incluido, false) then true
      else false
    end,
    case
      when r.pausado then 'restaurante_pausado'
      when not p.ativo then 'plano_inativo'
      when not rc.ativo then 'recurso_inativo'
      when rr.decisao = 'bloquear' then 'excecao_bloqueada'
      when rr.decisao = 'liberar' then 'excecao_liberada'
      when coalesce(pr.incluido, false) then 'plano'
      else 'nao_incluido'
    end,
    coalesce(rr.decisao, 'herdar')
  from public.restaurantes r
  join public.planos p on p.codigo = r.plano_codigo
  join public.recursos rc on rc.codigo = p_recurso_codigo
  left join public.plano_recursos pr
    on pr.plano_codigo = p.codigo
   and pr.recurso_codigo = rc.codigo
  left join public.restaurante_recursos rr
    on rr.restaurante_id = r.id
   and rr.recurso_codigo = rc.codigo
  where r.id = p_restaurante_id;
$function$;

create function public.recurso_disponivel_restaurante(
  p_restaurante_id uuid,
  p_recurso_codigo text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce((
    select resolvedor.disponivel
    from public._resolver_recurso_restaurante(p_restaurante_id, p_recurso_codigo) resolvedor
  ), false);
$function$;

create function public.recursos_restaurante_atual()
returns table (
  restaurante_id uuid,
  restaurante_pausado boolean,
  plano_codigo text,
  plano_nome text,
  plano_preco_mensal numeric(10,2),
  plano_medalha text,
  recurso_codigo text,
  recurso_nome text,
  recurso_descricao text,
  recurso_ordem smallint,
  disponivel boolean,
  origem text,
  decisao_individual text,
  planos_elegiveis text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id
    into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid()
    and u.ativo;

  if v_restaurante_id is null then
    select m.restaurante_id
      into v_restaurante_id
    from public.motoboys m
    where m.id = auth.uid();
  end if;

  if v_restaurante_id is null then
    raise exception using
      message = 'Usuário sem restaurante ativo vinculado.',
      errcode = '42501';
  end if;

  return query
  select
    resolvedor.restaurante_id,
    resolvedor.restaurante_pausado,
    resolvedor.plano_codigo,
    resolvedor.plano_nome,
    resolvedor.plano_preco_mensal,
    resolvedor.plano_medalha,
    resolvedor.recurso_codigo,
    resolvedor.recurso_nome,
    resolvedor.recurso_descricao,
    resolvedor.recurso_ordem,
    resolvedor.disponivel,
    resolvedor.origem,
    resolvedor.decisao_individual,
    coalesce((
      select array_agg(p.nome order by p.ordem)
      from public.planos p
      join public.plano_recursos pr
        on pr.plano_codigo = p.codigo
       and pr.recurso_codigo = resolvedor.recurso_codigo
       and pr.incluido
      where p.ativo
    ), array[]::text[])
  from public.recursos rc
  cross join lateral public._resolver_recurso_restaurante(v_restaurante_id, rc.codigo) resolvedor
  where rc.ativo
  order by resolvedor.recurso_ordem;
end;
$function$;

create function public.super_admin_listar_planos_recursos()
returns table (
  plano_codigo text,
  plano_nome text,
  plano_descricao_curta text,
  plano_preco_mensal numeric(10,2),
  plano_medalha text,
  plano_ordem smallint,
  plano_ativo boolean,
  recurso_codigo text,
  recurso_nome text,
  recurso_descricao text,
  recurso_ordem smallint,
  recurso_ativo boolean,
  incluido boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem listar a matriz de recursos.', errcode = '42501';
  end if;

  return query
  select
    p.codigo, p.nome, p.descricao_curta, p.preco_mensal, p.medalha, p.ordem, p.ativo,
    r.codigo, r.nome, r.descricao, r.ordem, r.ativo,
    coalesce(pr.incluido, false)
  from public.planos p
  cross join public.recursos r
  left join public.plano_recursos pr
    on pr.plano_codigo = p.codigo
   and pr.recurso_codigo = r.codigo
  order by p.ordem, r.ordem;
end;
$function$;

create function public.super_admin_atualizar_plano_v2(
  p_codigo text,
  p_nome text,
  p_descricao_curta text,
  p_preco_mensal numeric,
  p_medalha text,
  p_ordem integer,
  p_ativo boolean
)
returns table (
  codigo text,
  nome text,
  descricao_curta text,
  preco_mensal numeric(10,2),
  medalha text,
  ordem smallint,
  ativo boolean,
  atualizado_em timestamptz,
  atualizado_por uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_plano public.planos%rowtype;
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem alterar planos.', errcode = '42501';
  end if;
  if p_codigo is null or p_codigo <> lower(p_codigo) then
    raise exception using message = 'Código de plano inválido.', errcode = '22023';
  end if;
  if p_nome is null or char_length(btrim(p_nome)) not between 1 and 80 then
    raise exception using message = 'Nome de plano inválido.', errcode = '22023';
  end if;
  if p_descricao_curta is not null
     and char_length(btrim(p_descricao_curta)) not between 1 and 180 then
    raise exception using message = 'Descrição curta inválida.', errcode = '22023';
  end if;
  if p_preco_mensal is null or p_preco_mensal < 0 or p_preco_mensal > 99999999.99 then
    raise exception using message = 'Preço mensal inválido.', errcode = '22023';
  end if;
  if p_medalha is null or char_length(btrim(p_medalha)) not between 1 and 16 then
    raise exception using message = 'Medalha inválida.', errcode = '22023';
  end if;
  if p_ordem is null or p_ordem <= 0 or p_ordem > 32767 then
    raise exception using message = 'Ordem inválida.', errcode = '22023';
  end if;
  if p_ativo is null then
    raise exception using message = 'Estado ativo é obrigatório.', errcode = '22023';
  end if;

  select p.* into v_plano
  from public.planos p
  where p.codigo = p_codigo
  for update;

  if not found then
    raise exception using message = 'Plano não encontrado.', errcode = 'P0002';
  end if;
  if not p_ativo and exists (
    select 1 from public.restaurantes r where r.plano_codigo = p_codigo
  ) then
    raise exception using message = 'Não é possível desativar um plano vinculado a restaurantes.', errcode = '23503';
  end if;

  update public.planos p
  set nome = btrim(p_nome),
      descricao_curta = case when p_descricao_curta is null then null else btrim(p_descricao_curta) end,
      preco_mensal = p_preco_mensal,
      medalha = btrim(p_medalha),
      ordem = p_ordem::smallint,
      ativo = p_ativo,
      atualizado_em = now(),
      atualizado_por = auth.uid()
  where p.codigo = p_codigo
  returning p.* into v_plano;

  return query
  select v_plano.codigo, v_plano.nome, v_plano.descricao_curta,
         v_plano.preco_mensal, v_plano.medalha, v_plano.ordem,
         v_plano.ativo, v_plano.atualizado_em, v_plano.atualizado_por;
end;
$function$;

create function public.super_admin_definir_recursos_plano(
  p_plano_codigo text,
  p_recursos_incluidos text[]
)
returns table (
  recurso_codigo text,
  incluido boolean,
  atualizado_em timestamptz,
  atualizado_por uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := auth.uid();
begin
  if v_admin_id is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem alterar recursos de planos.', errcode = '42501';
  end if;
  if not exists (select 1 from public.planos p where p.codigo = p_plano_codigo) then
    raise exception using message = 'Plano não encontrado.', errcode = 'P0002';
  end if;
  if p_recursos_incluidos is null then
    raise exception using message = 'A lista de recursos é obrigatória.', errcode = '22023';
  end if;
  if cardinality(p_recursos_incluidos) <> (
    select count(distinct entrada.codigo_recurso)
    from unnest(p_recursos_incluidos) as entrada(codigo_recurso)
  ) then
    raise exception using message = 'A lista contém códigos de recursos repetidos.', errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_recursos_incluidos) as entrada(codigo_recurso)
    left join public.recursos r on r.codigo = entrada.codigo_recurso
    where r.codigo is null
  ) then
    raise exception using message = 'A lista contém recurso inexistente.', errcode = 'P0002';
  end if;
  if exists (
    select 1
    from unnest(p_recursos_incluidos) as entrada(codigo_recurso)
    join public.recursos r on r.codigo = entrada.codigo_recurso
    where not r.ativo
  ) then
    raise exception using message = 'A lista contém recurso inativo.', errcode = '22023';
  end if;

  insert into public.plano_recursos (plano_codigo, recurso_codigo, incluido, atualizado_em, atualizado_por)
  select p_plano_codigo, r.codigo, false, now(), v_admin_id
  from public.recursos r
  on conflict on constraint plano_recursos_pkey do nothing;

  update public.plano_recursos pr
  set incluido = pr.recurso_codigo = any(p_recursos_incluidos),
      atualizado_em = now(),
      atualizado_por = v_admin_id
  where pr.plano_codigo = p_plano_codigo;

  return query
  select pr.recurso_codigo, pr.incluido, pr.atualizado_em, pr.atualizado_por
  from public.plano_recursos pr
  join public.recursos r on r.codigo = pr.recurso_codigo
  where pr.plano_codigo = p_plano_codigo
  order by r.ordem;
end;
$function$;

create function public.super_admin_listar_recursos_restaurante(
  p_restaurante_id uuid
)
returns table (
  restaurante_id uuid,
  restaurante_pausado boolean,
  plano_codigo text,
  plano_nome text,
  plano_preco_mensal numeric(10,2),
  plano_medalha text,
  recurso_codigo text,
  recurso_nome text,
  recurso_descricao text,
  recurso_ordem smallint,
  incluido_plano boolean,
  decisao_individual text,
  disponivel boolean,
  origem text,
  planos_elegiveis text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem listar recursos do restaurante.', errcode = '42501';
  end if;
  if not exists (select 1 from public.restaurantes r where r.id = p_restaurante_id) then
    raise exception using message = 'Restaurante não encontrado.', errcode = 'P0002';
  end if;

  return query
  select
    resolvedor.restaurante_id,
    resolvedor.restaurante_pausado,
    resolvedor.plano_codigo,
    resolvedor.plano_nome,
    resolvedor.plano_preco_mensal,
    resolvedor.plano_medalha,
    resolvedor.recurso_codigo,
    resolvedor.recurso_nome,
    resolvedor.recurso_descricao,
    resolvedor.recurso_ordem,
    coalesce(pr_atual.incluido, false),
    resolvedor.decisao_individual,
    resolvedor.disponivel,
    resolvedor.origem,
    coalesce((
      select array_agg(p.nome order by p.ordem)
      from public.planos p
      join public.plano_recursos pr
        on pr.plano_codigo = p.codigo
       and pr.recurso_codigo = resolvedor.recurso_codigo
       and pr.incluido
      where p.ativo
    ), array[]::text[])
  from public.recursos rc
  cross join lateral public._resolver_recurso_restaurante(p_restaurante_id, rc.codigo) resolvedor
  left join public.plano_recursos pr_atual
    on pr_atual.plano_codigo = resolvedor.plano_codigo
   and pr_atual.recurso_codigo = resolvedor.recurso_codigo
  where rc.ativo
  order by resolvedor.recurso_ordem;
end;
$function$;

create function public.super_admin_definir_recurso_restaurante(
  p_restaurante_id uuid,
  p_recurso_codigo text,
  p_decisao text,
  p_motivo text
)
returns table (
  restaurante_id uuid,
  restaurante_pausado boolean,
  plano_codigo text,
  plano_nome text,
  plano_medalha text,
  plano_preco_mensal numeric(10,2),
  recurso_codigo text,
  recurso_nome text,
  recurso_descricao text,
  recurso_ordem smallint,
  disponivel boolean,
  origem text,
  decisao_individual text
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem alterar recursos do restaurante.', errcode = '42501';
  end if;
  if not exists (select 1 from public.restaurantes r where r.id = p_restaurante_id) then
    raise exception using message = 'Restaurante não encontrado.', errcode = 'P0002';
  end if;
  if not exists (select 1 from public.recursos r where r.codigo = p_recurso_codigo) then
    raise exception using message = 'Recurso não encontrado.', errcode = 'P0002';
  end if;
  if p_decisao is null or p_decisao not in ('herdar', 'liberar', 'bloquear') then
    raise exception using message = 'Decisão inválida.', errcode = '22023';
  end if;
  if p_motivo is not null and char_length(btrim(p_motivo)) > 500 then
    raise exception using message = 'Motivo inválido.', errcode = '22023';
  end if;

  if p_decisao = 'herdar' then
    delete from public.restaurante_recursos rr
    where rr.restaurante_id = p_restaurante_id
      and rr.recurso_codigo = p_recurso_codigo;
  else
    insert into public.restaurante_recursos (
      restaurante_id, recurso_codigo, decisao, motivo, alterado_em, alterado_por
    ) values (
      p_restaurante_id,
      p_recurso_codigo,
      p_decisao,
      nullif(btrim(coalesce(p_motivo, '')), ''),
      now(),
      auth.uid()
    )
    on conflict on constraint restaurante_recursos_pkey do update
      set decisao = excluded.decisao,
          motivo = excluded.motivo,
          alterado_em = excluded.alterado_em,
          alterado_por = excluded.alterado_por;
  end if;

  return query
  select *
  from public._resolver_recurso_restaurante(p_restaurante_id, p_recurso_codigo);
end;
$function$;

revoke all on function public._resolver_recurso_restaurante(uuid,text) from public, anon, authenticated;
revoke all on function public.recurso_disponivel_restaurante(uuid,text) from public, anon, authenticated;
revoke all on function public.recursos_restaurante_atual() from public, anon;
revoke all on function public.super_admin_listar_planos_recursos() from public, anon;
revoke all on function public.super_admin_atualizar_plano_v2(text,text,text,numeric,text,integer,boolean) from public, anon;
revoke all on function public.super_admin_definir_recursos_plano(text,text[]) from public, anon;
revoke all on function public.super_admin_listar_recursos_restaurante(uuid) from public, anon;
revoke all on function public.super_admin_definir_recurso_restaurante(uuid,text,text,text) from public, anon;

grant execute on function public.recurso_disponivel_restaurante(uuid,text) to service_role;
grant execute on function public.recursos_restaurante_atual() to authenticated, service_role;
grant execute on function public.super_admin_listar_planos_recursos() to authenticated, service_role;
grant execute on function public.super_admin_atualizar_plano_v2(text,text,text,numeric,text,integer,boolean) to authenticated, service_role;
grant execute on function public.super_admin_definir_recursos_plano(text,text[]) to authenticated, service_role;
grant execute on function public.super_admin_listar_recursos_restaurante(uuid) to authenticated, service_role;
grant execute on function public.super_admin_definir_recurso_restaurante(uuid,text,text,text) to authenticated, service_role;
