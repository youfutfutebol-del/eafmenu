-- Fundação dos planos comerciais do EAF Menu.
-- Preços são dados editáveis. Não devem ser usados em regras de autorização.

create table public.planos (
  codigo text primary key,
  nome text not null unique,
  preco_mensal numeric(10,2) not null,
  medalha text not null,
  ordem smallint not null unique,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid null references public.admins_plataforma(id) on delete set null,
  constraint planos_codigo_formato_check
    check (codigo = lower(codigo) and codigo ~ '^[a-z][a-z0-9_]*$'),
  constraint planos_nome_check
    check (char_length(btrim(nome)) between 1 and 80),
  constraint planos_preco_mensal_check
    check (preco_mensal >= 0),
  constraint planos_medalha_check
    check (char_length(btrim(medalha)) between 1 and 16),
  constraint planos_ordem_check
    check (ordem > 0)
);

comment on table public.planos is
  'Catálogo editável de planos comerciais. Preço é dado, nunca regra de acesso.';
comment on column public.planos.codigo is
  'Identificador técnico estável, minúsculo e não editável pelas RPCs.';
comment on column public.planos.preco_mensal is
  'Valor mensal editável pelo Super Admin; não usar em autorização.';
comment on column public.planos.medalha is
  'Representação visual editável do plano.';
comment on column public.planos.atualizado_por is
  'Super Admin responsável pela última alteração, preservando o plano se o admin for excluído.';

alter table public.planos enable row level security;

revoke all on table public.planos from public, anon, authenticated;
grant all on table public.planos to service_role;

insert into public.planos (codigo, nome, preco_mensal, medalha, ordem)
values
  ('essencial', 'Essencial', 79.90, '🥉', 1),
  ('profissional', 'Profissional', 99.90, '🥈', 2),
  ('premium', 'Premium', 129.90, '🥇', 3);

alter table public.restaurantes
  add column plano_codigo text,
  add column plano_alterado_em timestamptz,
  add column plano_alterado_por uuid;

update public.restaurantes
set plano_codigo = 'premium',
    plano_alterado_em = now()
where plano_codigo is null;

alter table public.restaurantes
  alter column plano_codigo set default 'premium',
  alter column plano_codigo set not null,
  add constraint restaurantes_plano_codigo_fkey
    foreign key (plano_codigo) references public.planos(codigo) on delete restrict,
  add constraint restaurantes_plano_alterado_por_fkey
    foreign key (plano_alterado_por) references public.admins_plataforma(id) on delete set null;

comment on column public.restaurantes.plano_codigo is
  'Plano atual. Default premium é temporário para compatibilidade e deve ser revisto quando o seletor entrar no Super Admin.';
comment on column public.restaurantes.plano_alterado_em is
  'Momento da última mudança administrativa de plano.';
comment on column public.restaurantes.plano_alterado_por is
  'Super Admin responsável pela última mudança de plano.';

create or replace function public.super_admin_listar_planos()
returns table (
  codigo text,
  nome text,
  preco_mensal numeric(10,2),
  medalha text,
  ordem smallint,
  ativo boolean,
  quantidade_restaurantes bigint,
  atualizado_em timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem listar planos.', errcode = '42501';
  end if;

  return query
  select p.codigo, p.nome, p.preco_mensal, p.medalha, p.ordem, p.ativo,
         count(r.id), p.atualizado_em
  from public.planos p
  left join public.restaurantes r on r.plano_codigo = p.codigo
  group by p.codigo
  order by p.ordem;
end;
$function$;

create or replace function public.super_admin_atualizar_plano(
  p_codigo text,
  p_nome text,
  p_preco_mensal numeric,
  p_medalha text,
  p_ordem integer,
  p_ativo boolean
)
returns table (
  codigo text,
  nome text,
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
      preco_mensal = p_preco_mensal,
      medalha = btrim(p_medalha),
      ordem = p_ordem::smallint,
      ativo = p_ativo,
      atualizado_em = now(),
      atualizado_por = auth.uid()
  where p.codigo = p_codigo
  returning p.* into v_plano;

  return query
  select v_plano.codigo, v_plano.nome, v_plano.preco_mensal,
         v_plano.medalha, v_plano.ordem, v_plano.ativo,
         v_plano.atualizado_em, v_plano.atualizado_por;
end;
$function$;

create or replace function public.super_admin_definir_plano_restaurante(
  p_restaurante_id uuid,
  p_plano_codigo text
)
returns table (
  restaurante_id uuid,
  restaurante_nome text,
  plano_codigo text,
  plano_nome text,
  plano_medalha text,
  plano_preco_mensal numeric(10,2)
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_restaurante public.restaurantes%rowtype;
  v_plano public.planos%rowtype;
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem alterar o plano do restaurante.', errcode = '42501';
  end if;

  select r.* into v_restaurante
  from public.restaurantes r
  where r.id = p_restaurante_id
  for update;
  if not found then
    raise exception using message = 'Restaurante não encontrado.', errcode = 'P0002';
  end if;

  select p.* into v_plano
  from public.planos p
  where p.codigo = p_plano_codigo
  for share;
  if not found then
    raise exception using message = 'Plano não encontrado.', errcode = 'P0002';
  end if;
  if not v_plano.ativo then
    raise exception using message = 'Plano inativo não pode ser atribuído.', errcode = '22023';
  end if;

  update public.restaurantes r
  set plano_codigo = v_plano.codigo,
      plano_alterado_em = now(),
      plano_alterado_por = auth.uid()
  where r.id = v_restaurante.id;

  return query
  select v_restaurante.id, v_restaurante.nome, v_plano.codigo,
         v_plano.nome, v_plano.medalha, v_plano.preco_mensal;
end;
$function$;

drop function public.listar_restaurantes_plataforma();
create function public.listar_restaurantes_plataforma()
returns table (
  id uuid,
  nome text,
  slug text,
  criado_em timestamptz,
  total_usuarios bigint,
  dono_id uuid,
  dono_nome text,
  dono_telefone text,
  pausado boolean,
  modulo_motoboy_ativo boolean,
  plano_codigo text,
  plano_nome text,
  plano_preco_mensal numeric(10,2),
  plano_medalha text
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem ver esta lista.', errcode = '42501';
  end if;
  return query
  select r.id, r.nome, r.slug, r.criado_em, count(u.id),
    (select u2.id from public.usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em limit 1),
    (select u2.nome from public.usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em limit 1),
    (select u2.telefone from public.usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em limit 1),
    r.pausado, r.modulo_motoboy_ativo,
    p.codigo, p.nome, p.preco_mensal, p.medalha
  from public.restaurantes r
  join public.planos p on p.codigo = r.plano_codigo
  left join public.usuarios u on u.restaurante_id = r.id
  group by r.id, p.codigo
  order by r.criado_em desc;
end;
$function$;

drop function public.estado_acesso_restaurante_atual();
create function public.estado_acesso_restaurante_atual()
returns table (
  restaurante_id uuid,
  pausado boolean,
  modulo_motoboy_ativo boolean,
  whatsapp_suporte text,
  plano_codigo text,
  plano_nome text,
  plano_preco_mensal numeric(10,2),
  plano_medalha text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select r.id, r.pausado, r.modulo_motoboy_ativo,
         '5541984213488'::text,
         p.codigo, p.nome, p.preco_mensal, p.medalha
  from public.usuarios u
  join public.restaurantes r on r.id = u.restaurante_id
  join public.planos p on p.codigo = r.plano_codigo
  where u.id = auth.uid();
$function$;

revoke all on function public.super_admin_listar_planos() from public, anon;
revoke all on function public.super_admin_atualizar_plano(text,text,numeric,text,integer,boolean) from public, anon;
revoke all on function public.super_admin_definir_plano_restaurante(uuid,text) from public, anon;
revoke all on function public.listar_restaurantes_plataforma() from public, anon;
revoke all on function public.estado_acesso_restaurante_atual() from public, anon;

grant execute on function public.super_admin_listar_planos() to authenticated, service_role;
grant execute on function public.super_admin_atualizar_plano(text,text,numeric,text,integer,boolean) to authenticated, service_role;
grant execute on function public.super_admin_definir_plano_restaurante(uuid,text) to authenticated, service_role;
grant execute on function public.listar_restaurantes_plataforma() to authenticated, service_role;
grant execute on function public.estado_acesso_restaurante_atual() to authenticated, service_role;
