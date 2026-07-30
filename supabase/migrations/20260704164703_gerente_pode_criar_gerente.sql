create or replace function public.criar_usuario_equipe(
  p_nome text,
  p_telefone text,
  p_email text,
  p_role text,
  p_senha text default null,
  p_veiculo text default null,
  p_placa text default null
) returns table(novo_usuario_id uuid, senha_provisoria text, email_gerado text)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_chamador record;
  v_novo_id uuid := gen_random_uuid();
  v_senha text;
  v_email_final text;
  v_primeiro_acesso boolean;
begin
  select u.role, u.restaurante_id into v_chamador
  from usuarios u where u.id = auth.uid();

  if v_chamador is null then
    raise exception 'Usuário não autenticado ou sem permissão.';
  end if;

  if v_chamador.role not in ('dono','gerente') then
    raise exception 'Você não tem permissão para criar usuários.';
  end if;

  -- Gerente pode criar gerente e atendente (e motoboy), mas nunca dono.
  if v_chamador.role = 'gerente' and p_role = 'dono' then
    raise exception 'Gerente não pode criar outro dono.';
  end if;

  if p_role not in ('dono','gerente','atendente','motoboy') then
    raise exception 'Papel inválido: %', p_role;
  end if;

  if p_telefone is null or trim(p_telefone) = '' then
    raise exception 'Telefone é obrigatório.';
  end if;

  v_email_final := lower(coalesce(nullif(trim(p_email), ''), trim(p_telefone) || '@sememail.eafmenu.local'));

  if p_senha is not null and length(trim(p_senha)) >= 4 then
    v_senha := trim(p_senha);
    v_primeiro_acesso := false;
  elsif p_role = 'motoboy' then
    v_senha := lpad(floor(random() * 10000)::text, 4, '0');
    v_primeiro_acesso := false;
  else
    v_senha := substr(md5(random()::text), 1, 4) || substr(md5(random()::text), 1, 4);
    v_primeiro_acesso := true;
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_current,
    email_change_token_new, phone_change_token, reauthentication_token, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_novo_id, 'authenticated', 'authenticated', v_email_final,
    crypt(v_senha, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('nome', p_nome),
    '', '', '', '', '', '', ''
  );

  insert into auth.identities (
    provider_id, user_id, provider, identity_data, created_at, updated_at, last_sign_in_at
  ) values (
    v_novo_id::text, v_novo_id, 'email',
    jsonb_build_object('sub', v_novo_id::text, 'email', v_email_final, 'email_verified', true, 'phone_verified', false),
    now(), now(), now()
  );

  insert into usuarios (id, restaurante_id, nome, email, telefone, role, primeiro_acesso)
  values (v_novo_id, v_chamador.restaurante_id, p_nome, v_email_final, trim(p_telefone), p_role::user_role, v_primeiro_acesso);

  if p_role = 'motoboy' then
    insert into motoboys (id, restaurante_id, disponivel, veiculo, placa)
    values (v_novo_id, v_chamador.restaurante_id, true, nullif(trim(p_veiculo),''), nullif(trim(p_placa),''));
  end if;

  return query select v_novo_id, v_senha, v_email_final;
end;
$$;
grant execute on function criar_usuario_equipe(text,text,text,text,text,text,text) to authenticated;
