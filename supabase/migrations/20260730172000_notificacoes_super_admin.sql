-- Notificações persistentes do Super Admin, com destinos normalizados e leitura individual.

create type public.tipo_notificacao_plataforma as enum ('informativa', 'atencao', 'urgente');

create table public.notificacoes_plataforma (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (char_length(btrim(titulo)) between 1 and 120),
  mensagem text not null check (char_length(btrim(mensagem)) between 1 and 4000),
  tipo public.tipo_notificacao_plataforma not null default 'informativa',
  criada_por uuid not null references public.admins_plataforma(id),
  criada_em timestamptz not null default now(),
  publicada_em timestamptz not null default now(),
  arquivada_em timestamptz
);

create table public.notificacoes_plataforma_destinos (
  notificacao_id uuid not null references public.notificacoes_plataforma(id) on delete cascade,
  restaurante_id uuid not null references public.restaurantes(id) on delete cascade,
  primary key (notificacao_id, restaurante_id)
);

create table public.notificacoes_plataforma_leituras (
  notificacao_id uuid not null references public.notificacoes_plataforma(id) on delete cascade,
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  lida_em timestamptz not null default now(),
  primary key (notificacao_id, usuario_id)
);

create index notificacoes_plataforma_publicadas_idx
  on public.notificacoes_plataforma (publicada_em desc)
  where arquivada_em is null;
create index notificacoes_destinos_restaurante_idx
  on public.notificacoes_plataforma_destinos (restaurante_id, notificacao_id);
create index notificacoes_leituras_usuario_idx
  on public.notificacoes_plataforma_leituras (usuario_id, lida_em desc);

alter table public.notificacoes_plataforma enable row level security;
alter table public.notificacoes_plataforma_destinos enable row level security;
alter table public.notificacoes_plataforma_leituras enable row level security;

revoke all on public.notificacoes_plataforma from public, anon, authenticated;
revoke all on public.notificacoes_plataforma_destinos from public, anon, authenticated;
revoke all on public.notificacoes_plataforma_leituras from public, anon, authenticated;

create or replace function public.super_admin_enviar_notificacao(
  p_titulo text,
  p_mensagem text,
  p_tipo public.tipo_notificacao_plataforma,
  p_restaurante_ids uuid[] default null,
  p_todos boolean default false
) returns table(notificacao_id uuid, total_destinos integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_notificacao_id uuid;
  v_total integer;
  v_ids uuid[];
begin
  if v_admin_id is null then
    raise exception using message = 'Faça login como administrador da plataforma.', errcode = '28000';
  end if;
  if not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem enviar notificações.', errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_titulo, '')), '') is null
     or nullif(btrim(coalesce(p_mensagem, '')), '') is null then
    raise exception using message = 'Título e mensagem são obrigatórios.', errcode = '22023';
  end if;

  if p_todos then
    select array_agg(r.id order by r.id) into v_ids from public.restaurantes r;
  else
    select array_agg(distinct x.id order by x.id) into v_ids
    from unnest(coalesce(p_restaurante_ids, '{}'::uuid[])) x(id)
    join public.restaurantes r on r.id = x.id;
  end if;

  if coalesce(cardinality(v_ids), 0) = 0 then
    raise exception using message = 'Selecione pelo menos um restaurante.', errcode = '22023';
  end if;

  insert into public.notificacoes_plataforma(titulo, mensagem, tipo, criada_por)
  values (btrim(p_titulo), btrim(p_mensagem), coalesce(p_tipo, 'informativa'), v_admin_id)
  returning id into v_notificacao_id;

  insert into public.notificacoes_plataforma_destinos(notificacao_id, restaurante_id)
  select v_notificacao_id, unnest(v_ids);
  get diagnostics v_total = row_count;

  return query select v_notificacao_id, v_total;
end;
$$;

create or replace function public.listar_notificacoes_restaurante()
returns table (
  id uuid,
  titulo text,
  mensagem text,
  tipo public.tipo_notificacao_plataforma,
  publicada_em timestamptz,
  lida boolean,
  lida_em timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_usuario public.usuarios%rowtype;
begin
  select * into v_usuario from public.usuarios u where u.id = auth.uid();
  if v_usuario.id is null or not v_usuario.ativo
     or v_usuario.role not in ('dono', 'gerente', 'atendente')
     or not public.restaurante_operacional(v_usuario.restaurante_id) then
    raise exception using message = 'Usuário sem acesso às notificações.', errcode = '42501';
  end if;

  return query
  select n.id, n.titulo, n.mensagem, n.tipo, n.publicada_em,
         l.lida_em is not null, l.lida_em
  from public.notificacoes_plataforma n
  join public.notificacoes_plataforma_destinos d on d.notificacao_id = n.id
  left join public.notificacoes_plataforma_leituras l
    on l.notificacao_id = n.id and l.usuario_id = v_usuario.id
  where d.restaurante_id = v_usuario.restaurante_id
    and n.arquivada_em is null
    and n.publicada_em <= pg_catalog.now()
  order by n.publicada_em desc, n.id desc;
end;
$$;

create or replace function public.marcar_notificacao_restaurante_lida(p_notificacao_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario public.usuarios%rowtype;
  v_lida_em timestamptz;
begin
  select * into v_usuario from public.usuarios u where u.id = auth.uid();
  if v_usuario.id is null or not v_usuario.ativo
     or v_usuario.role not in ('dono', 'gerente', 'atendente')
     or not public.restaurante_operacional(v_usuario.restaurante_id) then
    raise exception using message = 'Usuário sem acesso às notificações.', errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.notificacoes_plataforma_destinos d
    join public.notificacoes_plataforma n on n.id = d.notificacao_id
    where d.notificacao_id = p_notificacao_id
      and d.restaurante_id = v_usuario.restaurante_id
      and n.arquivada_em is null
  ) then
    raise exception using message = 'Notificação não encontrada.', errcode = 'P0002';
  end if;

  insert into public.notificacoes_plataforma_leituras(notificacao_id, usuario_id)
  values (p_notificacao_id, v_usuario.id)
  on conflict (notificacao_id, usuario_id)
  do update set lida_em = excluded.lida_em
  returning lida_em into v_lida_em;
  return v_lida_em;
end;
$$;

create or replace function public.super_admin_listar_notificacoes_enviadas()
returns table (
  id uuid,
  titulo text,
  mensagem text,
  tipo public.tipo_notificacao_plataforma,
  criada_em timestamptz,
  publicada_em timestamptz,
  administrador_id uuid,
  administrador_nome text,
  total_destinatarios bigint,
  total_leituras bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem consultar este histórico.', errcode = '42501';
  end if;

  return query
  select n.id, n.titulo, n.mensagem, n.tipo, n.criada_em, n.publicada_em,
         a.id, a.nome,
         count(distinct d.restaurante_id),
         count(distinct l.usuario_id)
  from public.notificacoes_plataforma n
  join public.admins_plataforma a on a.id = n.criada_por
  left join public.notificacoes_plataforma_destinos d on d.notificacao_id = n.id
  left join public.notificacoes_plataforma_leituras l on l.notificacao_id = n.id
  group by n.id, a.id, a.nome
  order by n.publicada_em desc, n.id desc;
end;
$$;

create or replace function public.super_admin_detalhar_notificacao_enviada(
  p_notificacao_id uuid
)
returns table (
  restaurante_id uuid,
  restaurante_nome text,
  leituras jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem consultar este detalhe.', errcode = '42501';
  end if;
  if not exists (
    select 1 from public.notificacoes_plataforma n where n.id = p_notificacao_id
  ) then
    raise exception using message = 'Notificação não encontrada.', errcode = 'P0002';
  end if;

  return query
  select r.id, r.nome,
         coalesce(
           jsonb_agg(
             jsonb_build_object(
               'usuario_id', u.id,
               'usuario_nome', u.nome,
               'papel', u.role,
               'lida_em', l.lida_em
             )
             order by l.lida_em, u.nome
           ) filter (where l.usuario_id is not null),
           '[]'::jsonb
         )
  from public.notificacoes_plataforma_destinos d
  join public.restaurantes r on r.id = d.restaurante_id
  left join public.notificacoes_plataforma_leituras l
    on l.notificacao_id = d.notificacao_id
  left join public.usuarios u
    on u.id = l.usuario_id and u.restaurante_id = d.restaurante_id
  where d.notificacao_id = p_notificacao_id
  group by r.id, r.nome
  order by r.nome, r.id;
end;
$$;

revoke all on function public.super_admin_enviar_notificacao(
  text,text,public.tipo_notificacao_plataforma,uuid[],boolean
) from public, anon, service_role;
grant execute on function public.super_admin_enviar_notificacao(
  text,text,public.tipo_notificacao_plataforma,uuid[],boolean
) to authenticated;

revoke all on function public.listar_notificacoes_restaurante() from public, anon;
grant execute on function public.listar_notificacoes_restaurante() to authenticated, service_role;
revoke all on function public.marcar_notificacao_restaurante_lida(uuid) from public, anon;
grant execute on function public.marcar_notificacao_restaurante_lida(uuid) to authenticated, service_role;

revoke all on function public.super_admin_listar_notificacoes_enviadas()
  from public, anon, service_role;
grant execute on function public.super_admin_listar_notificacoes_enviadas()
  to authenticated;

revoke all on function public.super_admin_detalhar_notificacao_enviada(uuid)
  from public, anon, service_role;
grant execute on function public.super_admin_detalhar_notificacao_enviada(uuid)
  to authenticated;
