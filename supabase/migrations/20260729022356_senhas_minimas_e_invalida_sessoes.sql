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
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_telefone text := public.normalizar_telefone_acesso(p_telefone);
begin
  if p_senha is null or char_length(p_senha) < 8 then
    raise exception using message = 'A senha precisa ter pelo menos 8 caracteres.', errcode = '22023';
  end if;

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
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_telefone text := public.normalizar_telefone_acesso(p_dono_telefone);
begin
  if p_dono_senha is null or char_length(p_dono_senha) < 8 then
    raise exception using message = 'A senha do dono precisa ter pelo menos 8 caracteres.', errcode = '22023';
  end if;

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

create or replace function public.redefinir_senha_usuario(
  p_usuario_id uuid,
  p_nova_senha text
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'auth'
as $$
declare
  v_chamador public.usuarios%rowtype;
  v_alvo public.usuarios%rowtype;
begin
  select * into v_chamador
  from public.usuarios
  where id = auth.uid()
    and ativo = true;

  if v_chamador.id is null or v_chamador.role not in ('dono', 'gerente') then
    raise exception using message = 'Você não tem permissão para redefinir esta senha.', errcode = '42501';
  end if;

  select * into v_alvo
  from public.usuarios
  where id = p_usuario_id;

  if v_alvo.id is null or v_alvo.restaurante_id <> v_chamador.restaurante_id then
    raise exception using message = 'Usuário não encontrado nesse restaurante.', errcode = 'P0002';
  end if;

  if v_alvo.id = v_chamador.id then
    raise exception using message = 'Use a opção de trocar sua própria senha.', errcode = '42501';
  end if;

  if v_chamador.role = 'gerente' and v_alvo.role not in ('atendente', 'motoboy') then
    raise exception using message = 'Gerentes só podem redefinir senhas de atendentes e motoboys.', errcode = '42501';
  end if;

  if v_chamador.role = 'dono' and v_alvo.role not in ('gerente', 'atendente', 'motoboy') then
    raise exception using message = 'O dono só pode redefinir senhas da equipe.', errcode = '42501';
  end if;

  if p_nova_senha is null or char_length(p_nova_senha) < 8 then
    raise exception using message = 'A senha precisa ter pelo menos 8 caracteres.', errcode = '22023';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_nova_senha, extensions.gen_salt('bf')),
      updated_at = pg_catalog.now()
  where id = p_usuario_id;

  if not found then
    raise exception using message = 'Conta de autenticação não encontrada.', errcode = 'P0002';
  end if;

  delete from auth.refresh_tokens
  where user_id = p_usuario_id::text;

  delete from auth.sessions
  where user_id = p_usuario_id;

  return true;
end;
$$;

create or replace function public.super_admin_redefinir_senha(
  p_usuario_id uuid,
  p_nova_senha text
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'auth'
as $$
declare
  v_alvo public.usuarios%rowtype;
begin
  if not public.eh_super_admin() then
    raise exception using message = 'Só administradores da plataforma podem usar essa função.', errcode = '42501';
  end if;

  select * into v_alvo
  from public.usuarios
  where id = p_usuario_id;

  if v_alvo.id is null or v_alvo.role <> 'dono' then
    raise exception using message = 'Dono do restaurante não encontrado.', errcode = 'P0002';
  end if;

  if p_nova_senha is null or char_length(p_nova_senha) < 8 then
    raise exception using message = 'A senha precisa ter pelo menos 8 caracteres.', errcode = '22023';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_nova_senha, extensions.gen_salt('bf')),
      updated_at = pg_catalog.now()
  where id = p_usuario_id;

  if not found then
    raise exception using message = 'Conta de autenticação não encontrada.', errcode = 'P0002';
  end if;

  delete from auth.refresh_tokens
  where user_id = p_usuario_id::text;

  delete from auth.sessions
  where user_id = p_usuario_id;

  return true;
end;
$$;

revoke all on function public.criar_usuario_equipe(text,text,text,text,text,text,text) from public, anon;
grant execute on function public.criar_usuario_equipe(text,text,text,text,text,text,text) to authenticated, service_role;

revoke all on function public.criar_restaurante_com_dono(text,text,text,text,text) from public, anon;
grant execute on function public.criar_restaurante_com_dono(text,text,text,text,text) to authenticated, service_role;

revoke all on function public.redefinir_senha_usuario(uuid,text) from public, anon;
grant execute on function public.redefinir_senha_usuario(uuid,text) to authenticated, service_role;

revoke all on function public.super_admin_redefinir_senha(uuid,text) from public, anon;
grant execute on function public.super_admin_redefinir_senha(uuid,text) to authenticated, service_role;