create or replace function public.normalizar_telefone_acesso(p_telefone text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select nullif(regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g'), '');
$$;

update public.usuarios
set telefone = public.normalizar_telefone_acesso(telefone)
where telefone is distinct from public.normalizar_telefone_acesso(telefone);

alter table public.usuarios
  add column if not exists telefone_normalizado text
  generated always as (public.normalizar_telefone_acesso(telefone)) stored;

create unique index if not exists usuarios_telefone_normalizado_unique
  on public.usuarios (telefone_normalizado)
  where telefone_normalizado is not null;

create or replace function public.trg_normalizar_validar_telefone_usuario()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_telefone text;
begin
  v_telefone := public.normalizar_telefone_acesso(new.telefone);

  if v_telefone is not null and length(v_telefone) < 10 then
    raise exception 'Telefone inválido. Informe o número com DDD.';
  end if;

  if v_telefone is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('usuario-telefone:' || v_telefone, 0)
    );

    if exists (
      select 1
      from public.usuarios u
      where u.id is distinct from new.id
        and u.telefone_normalizado = v_telefone
    ) then
      raise exception 'Este telefone já está vinculado a outra conta de acesso.';
    end if;
  end if;

  new.telefone := v_telefone;
  return new;
end;
$$;

drop trigger if exists trg_normalizar_validar_telefone_usuario on public.usuarios;
create trigger trg_normalizar_validar_telefone_usuario
before insert or update of telefone on public.usuarios
for each row execute function public.trg_normalizar_validar_telefone_usuario();

alter function public.criar_usuario_equipe(text, text, text, text, text, text, text)
  rename to _criar_usuario_equipe_impl_telefone_unico;

revoke all on function public._criar_usuario_equipe_impl_telefone_unico(text, text, text, text, text, text, text)
  from public, anon, authenticated, service_role;

create or replace function public.criar_usuario_equipe(
  p_nome text,
  p_telefone text,
  p_email text,
  p_role text,
  p_senha text default null,
  p_veiculo text default null,
  p_placa text default null
)
returns table(novo_usuario_id uuid, senha_provisoria text, email_gerado text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_telefone text := public.normalizar_telefone_acesso(p_telefone);
begin
  if v_telefone is null or length(v_telefone) < 10 then
    raise exception 'Telefone é obrigatório (com DDD).';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('usuario-telefone:' || v_telefone, 0)
  );

  if exists (
    select 1 from public.usuarios u
    where u.telefone_normalizado = v_telefone
  ) then
    raise exception 'Este telefone já está vinculado a outra conta de acesso.';
  end if;

  return query
  select *
  from public._criar_usuario_equipe_impl_telefone_unico(
    p_nome,
    v_telefone,
    p_email,
    p_role,
    p_senha,
    p_veiculo,
    p_placa
  );
end;
$$;

revoke all on function public.criar_usuario_equipe(text, text, text, text, text, text, text)
  from public, anon;
grant execute on function public.criar_usuario_equipe(text, text, text, text, text, text, text)
  to authenticated, service_role;

alter function public.criar_restaurante_com_dono(text, text, text, text, text)
  rename to _criar_restaurante_com_dono_impl_telefone_unico;

revoke all on function public._criar_restaurante_com_dono_impl_telefone_unico(text, text, text, text, text)
  from public, anon, authenticated, service_role;

create or replace function public.criar_restaurante_com_dono(
  p_nome_restaurante text,
  p_dono_nome text,
  p_dono_telefone text,
  p_dono_email text,
  p_dono_senha text
)
returns table(restaurante_id uuid, dono_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_telefone text := public.normalizar_telefone_acesso(p_dono_telefone);
begin
  if v_telefone is not null and length(v_telefone) < 10 then
    raise exception 'Telefone inválido. Informe o número com DDD.';
  end if;

  if v_telefone is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('usuario-telefone:' || v_telefone, 0)
    );

    if exists (
      select 1 from public.usuarios u
      where u.telefone_normalizado = v_telefone
    ) then
      raise exception 'Este telefone já está vinculado a outra conta de acesso.';
    end if;
  end if;

  return query
  select *
  from public._criar_restaurante_com_dono_impl_telefone_unico(
    p_nome_restaurante,
    p_dono_nome,
    v_telefone,
    p_dono_email,
    p_dono_senha
  );
end;
$$;

revoke all on function public.criar_restaurante_com_dono(text, text, text, text, text)
  from public, anon;
grant execute on function public.criar_restaurante_com_dono(text, text, text, text, text)
  to authenticated, service_role;

create or replace function public.resolver_email_login(p_identificador text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_telefone text;
  v_email text;
  v_quantidade integer;
begin
  if p_identificador ilike '%@%' then
    return lower(btrim(p_identificador));
  end if;

  v_telefone := public.normalizar_telefone_acesso(p_identificador);
  if v_telefone is null or length(v_telefone) < 10 then
    return null;
  end if;

  select count(*), min(u.email)
    into v_quantidade, v_email
  from public.usuarios u
  where u.telefone_normalizado = v_telefone
    and u.ativo = true;

  if v_quantidade > 1 then
    raise exception 'Existe um conflito de contas para este telefone. Fale com o suporte do EAF Menu.';
  end if;

  if v_quantidade = 0 then
    return null;
  end if;

  return v_email;
end;
$$;

revoke all on function public.resolver_email_login(text) from public;
grant execute on function public.resolver_email_login(text) to anon, authenticated, service_role;

comment on column public.usuarios.telefone_normalizado is
  'Telefone de acesso contendo apenas dígitos. Único globalmente em toda a plataforma.';
comment on function public.resolver_email_login(text) is
  'Resolve login por e-mail ou telefone normalizado sem escolher contas arbitrariamente.';