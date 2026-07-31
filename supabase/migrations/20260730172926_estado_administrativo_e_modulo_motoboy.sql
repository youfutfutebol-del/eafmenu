-- Estado administrativo do restaurante e contratação independente do módulo de motoboy.

create or replace function public.eh_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admins_plataforma a
    where a.id = auth.uid()
  );
$$;

alter table public.restaurantes
  add column pausado boolean not null default false,
  add column pausado_em timestamptz,
  add column pausado_por uuid references public.admins_plataforma(id) on delete restrict,
  add column motivo_pausa text,
  add column modulo_motoboy_ativo boolean,
  add column modulo_motoboy_alterado_em timestamptz,
  add column modulo_motoboy_alterado_por uuid references public.admins_plataforma(id) on delete restrict;

-- Compatibilidade: todas as lojas que já existiam tinham acesso ao fluxo de
-- motoboy antes desta flag. Novas lojas passam a começar sem o módulo.
update public.restaurantes
set modulo_motoboy_ativo = true
where modulo_motoboy_ativo is null;

alter table public.restaurantes
  alter column modulo_motoboy_ativo set default false,
  alter column modulo_motoboy_ativo set not null;

alter table public.restaurantes
  add constraint restaurantes_pausa_consistente check (
    (pausado = false and pausado_em is null and pausado_por is null and motivo_pausa is null)
    or
    (pausado = true and pausado_em is not null and pausado_por is not null
      and nullif(btrim(motivo_pausa), '') is not null)
  ),
  add constraint restaurantes_modulo_motoboy_auditoria_consistente check (
    (modulo_motoboy_alterado_em is null and modulo_motoboy_alterado_por is null)
    or
    (modulo_motoboy_alterado_em is not null and modulo_motoboy_alterado_por is not null)
  );

comment on column public.restaurantes.pausado is
  'Suspensão administrativa reversível definida exclusivamente pelo Super Admin. Não representa assinatura, horário ou exclusão.';
comment on column public.restaurantes.motivo_pausa is
  'Motivo interno da suspensão. Nunca deve ser retornado ao restaurante ou ao cardápio público.';
comment on column public.restaurantes.modulo_motoboy_ativo is
  'Contratação do módulo de motoboy próprio. Independente de roteirizacao_motoboy_ativa.';

create index restaurantes_pausado_idx
  on public.restaurantes (pausado)
  where pausado;

create index motoboys_liberado_por_idx
  on public.motoboys (liberado_por)
  where liberado_por is not null;

drop function public.listar_restaurantes_plataforma();
create function public.listar_restaurantes_plataforma()
returns table(
  id uuid,
  nome text,
  slug text,
  criado_em timestamptz,
  total_usuarios bigint,
  dono_id uuid,
  dono_nome text,
  dono_telefone text,
  pausado boolean,
  modulo_motoboy_ativo boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem ver esta lista.', errcode = '42501';
  end if;
  return query
  select r.id, r.nome, r.slug, r.criado_em, count(u.id),
    (select u2.id from public.usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em limit 1),
    (select u2.nome from public.usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em limit 1),
    (select u2.telefone from public.usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em limit 1),
    r.pausado, r.modulo_motoboy_ativo
  from public.restaurantes r
  left join public.usuarios u on u.restaurante_id = r.id
  group by r.id
  order by r.criado_em desc;
end;
$$;

create or replace function public.super_admin_definir_pausa_restaurante(
  p_restaurante_id uuid,
  p_pausado boolean,
  p_motivo text default null
) returns table (
  restaurante_id uuid,
  pausado boolean,
  pausado_em timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_em_andamento bigint;
begin
  if v_admin_id is null then
    raise exception using message = 'Faça login como administrador da plataforma.', errcode = '28000';
  end if;
  if not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem alterar este estado.', errcode = '42501';
  end if;
  if p_restaurante_id is null or p_pausado is null then
    raise exception using message = 'Restaurante e estado são obrigatórios.', errcode = '22023';
  end if;
  perform 1
  from public.restaurantes r
  where r.id = p_restaurante_id
  for update;
  if not found then
    raise exception using message = 'Restaurante não encontrado.', errcode = 'P0002';
  end if;

  if p_pausado then
    if nullif(btrim(coalesce(p_motivo, '')), '') is null then
      raise exception using message = 'Informe o motivo interno da suspensão.', errcode = '22023';
    end if;

    select count(*) into v_em_andamento
    from public.pedidos p
    where p.restaurante_id = p_restaurante_id
      and p.status not in ('entregue', 'retirado', 'cancelado');

    if v_em_andamento > 0 then
      raise exception using
        message = format(
          'Não é possível pausar: existem %s pedido(s) em andamento. Finalize ou cancele esses pedidos primeiro.',
          v_em_andamento
        ),
        errcode = '55000';
    end if;

    update public.restaurantes r
       set pausado = true,
           pausado_em = pg_catalog.now(),
           pausado_por = v_admin_id,
           motivo_pausa = btrim(p_motivo)
     where r.id = p_restaurante_id;
  else
    update public.restaurantes r
       set pausado = false,
           pausado_em = null,
           pausado_por = null,
           motivo_pausa = null
     where r.id = p_restaurante_id;
  end if;

  return query
  select r.id, r.pausado, r.pausado_em
  from public.restaurantes r
  where r.id = p_restaurante_id;
end;
$$;

create or replace function public.super_admin_definir_modulo_motoboy(
  p_restaurante_id uuid,
  p_ativo boolean
) returns table (
  restaurante_id uuid,
  modulo_motoboy_ativo boolean,
  alterado_em timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
begin
  if v_admin_id is null then
    raise exception using message = 'Faça login como administrador da plataforma.', errcode = '28000';
  end if;
  if not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem alterar este módulo.', errcode = '42501';
  end if;
  if p_restaurante_id is null or p_ativo is null then
    raise exception using message = 'Restaurante e estado do módulo são obrigatórios.', errcode = '22023';
  end if;

  update public.restaurantes r
     set modulo_motoboy_ativo = p_ativo,
         modulo_motoboy_alterado_em = pg_catalog.now(),
         modulo_motoboy_alterado_por = v_admin_id
   where r.id = p_restaurante_id;

  if not found then
    raise exception using message = 'Restaurante não encontrado.', errcode = 'P0002';
  end if;

  return query
  select r.id, r.modulo_motoboy_ativo, r.modulo_motoboy_alterado_em
  from public.restaurantes r
  where r.id = p_restaurante_id;
end;
$$;

revoke all on function public.super_admin_definir_pausa_restaurante(uuid, boolean, text)
  from public, anon, service_role;
grant execute on function public.super_admin_definir_pausa_restaurante(uuid, boolean, text)
  to authenticated;

revoke all on function public.super_admin_definir_modulo_motoboy(uuid, boolean)
  from public, anon, service_role;
grant execute on function public.super_admin_definir_modulo_motoboy(uuid, boolean)
  to authenticated;

-- As RPCs administrativas existentes mantêm checagem interna, mas não precisam ser
-- pontos de entrada para anon.
revoke execute on function public.eh_super_admin() from public, anon;
revoke execute on function public.listar_restaurantes_plataforma() from public, anon;
grant execute on function public.eh_super_admin() to authenticated, service_role;
grant execute on function public.listar_restaurantes_plataforma() to authenticated, service_role;
