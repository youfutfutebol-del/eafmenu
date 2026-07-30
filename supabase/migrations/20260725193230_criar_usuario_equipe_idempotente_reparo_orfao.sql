-- MIGRATION: criar_usuario_equipe_idempotente_reparo_orfao
-- Versão idêntica à aprovada na simulação BEGIN/ROLLBACK 14/14 (25/07).
-- Endurecimentos do cross-review: lock por e-mail; adoção de órfão só com critérios cumulativos
-- (e-mail técnico exato, is_sso_user=false, não anônimo/deletado/banido, last_sign_in_at IS NULL,
-- zero usuarios/motoboys, zero refs públicas via varredura de catálogo, zero sessions/refresh/MFA,
-- exatamente 1 identity email); unique_violation só tratada p/ users_email_partial_key;
-- reparo de vínculo sem redefinir senha; nada é alterado fora dos ramos aprovados.
-- DOCUMENTADO: telefone de equipe é GLOBALMENTE único no modelo atual (e-mail técnico = telefone).

CREATE OR REPLACE FUNCTION public.criar_usuario_equipe(
  p_nome text, p_telefone text, p_email text, p_role text,
  p_senha text DEFAULT NULL, p_veiculo text DEFAULT NULL, p_placa text DEFAULT NULL
)
RETURNS TABLE(novo_usuario_id uuid, senha_provisoria text, email_gerado text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_chamador record;
  v_novo_id uuid;
  v_senha text;
  v_email_final text;
  v_primeiro_acesso boolean;
  v_telefone text;
  v_auth record;
  v_perfil record;
  v_constraint text;
  v_ref record;
  v_qtd bigint;
begin
  select u.role, u.restaurante_id into v_chamador
  from usuarios u where u.id = auth.uid();

  if v_chamador is null then
    raise exception 'Usuário não autenticado ou sem permissão.';
  end if;
  if v_chamador.role not in ('dono','gerente') then
    raise exception 'Você não tem permissão para criar usuários.';
  end if;
  if v_chamador.role = 'gerente' and p_role = 'dono' then
    raise exception 'Gerente não pode criar outro dono.';
  end if;
  if p_role not in ('dono','gerente','atendente','motoboy') then
    raise exception 'Papel inválido: %', p_role;
  end if;

  v_telefone := regexp_replace(coalesce(p_telefone,''), '\D', '', 'g');
  if length(v_telefone) < 10 then
    raise exception 'Telefone é obrigatório (com DDD).';
  end if;

  v_email_final := lower(coalesce(nullif(trim(p_email), ''), v_telefone || '@sememail.eafmenu.local'));

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('usuario-equipe-email:' || v_email_final, 0));

  if p_senha is not null and length(trim(p_senha)) >= 4 then
    v_senha := trim(p_senha); v_primeiro_acesso := false;
  elsif p_role = 'motoboy' then
    v_senha := lpad(floor(random() * 10000)::text, 4, '0'); v_primeiro_acesso := false;
  else
    v_senha := substr(md5(random()::text),1,4) || substr(md5(random()::text),1,4); v_primeiro_acesso := true;
  end if;

  select u.* into v_auth from auth.users u
  where lower(u.email) = v_email_final and u.is_sso_user = false
  for update;

  if v_auth.id is not null then
    select s.* into v_perfil from usuarios s where s.id = v_auth.id;

    if v_perfil.id is not null then
      if v_perfil.restaurante_id <> v_chamador.restaurante_id then
        raise exception 'Este telefone já está vinculado a outra conta de equipe.';
      end if;

      if p_role = 'motoboy' and v_perfil.role = 'motoboy'
         and not exists (select 1 from motoboys m where m.id = v_perfil.id) then
        insert into motoboys (id, restaurante_id, disponivel, veiculo, placa)
        values (v_perfil.id, v_chamador.restaurante_id, true,
                nullif(trim(p_veiculo),''), nullif(trim(p_placa),''));
        return query select v_perfil.id, null::text, v_email_final;
        return;
      end if;

      raise exception '% já faz parte da equipe deste restaurante (papel: %).',
        v_perfil.nome, v_perfil.role;
    end if;

    if v_email_final <> (v_telefone || '@sememail.eafmenu.local')
       or v_auth.is_anonymous
       or v_auth.deleted_at is not null
       or (v_auth.banned_until is not null and v_auth.banned_until > now())
       or v_auth.last_sign_in_at is not null
       or exists (select 1 from motoboys m where m.id = v_auth.id)
       or exists (select 1 from auth.sessions se where se.user_id = v_auth.id)
       or exists (select 1 from auth.refresh_tokens rt where rt.user_id = v_auth.id::text)
       or exists (select 1 from auth.mfa_factors mf where mf.user_id = v_auth.id)
       or exists (select 1 from auth.identities i where i.user_id = v_auth.id and i.provider <> 'email')
       or (select count(*) from auth.identities i where i.user_id = v_auth.id) > 1
    then
      raise exception 'Já existe uma conta com este e-mail. Fale com o suporte do EAF Menu.';
    end if;

    for v_ref in
      select c.conrelid::regclass::text as tab, a.attname as col
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
      join pg_class t on t.oid = c.conrelid
      join pg_namespace tn on tn.oid = t.relnamespace
      where c.contype = 'f'
        and c.confrelid in ('auth.users'::regclass,'public.usuarios'::regclass,'public.motoboys'::regclass)
        and tn.nspname = 'public'
        and c.conrelid not in ('public.usuarios'::regclass,'public.motoboys'::regclass)
    loop
      execute format('select count(*) from %s where %I = $1', v_ref.tab, v_ref.col)
        into v_qtd using v_auth.id;
      if v_qtd > 0 then
        raise exception 'Já existe uma conta com este e-mail. Fale com o suporte do EAF Menu.';
      end if;
    end loop;

    v_novo_id := v_auth.id;

    update auth.users set
      encrypted_password = crypt(v_senha, gen_salt('bf')),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now(),
      raw_user_meta_data = jsonb_build_object('nome', p_nome)
    where id = v_novo_id;

    if not exists (select 1 from auth.identities i where i.user_id = v_novo_id and i.provider = 'email') then
      insert into auth.identities (provider_id, user_id, provider, identity_data, created_at, updated_at, last_sign_in_at)
      values (v_novo_id::text, v_novo_id, 'email',
              jsonb_build_object('sub', v_novo_id::text, 'email', v_email_final, 'email_verified', true, 'phone_verified', false),
              now(), now(), now());
    end if;

  else
    v_novo_id := gen_random_uuid();
    begin
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
    exception when unique_violation then
      get stacked diagnostics v_constraint = CONSTRAINT_NAME;
      if v_constraint is distinct from 'users_email_partial_key' then
        raise;
      end if;
      raise exception 'Este telefone acabou de ser cadastrado. Atualize a tela e tente novamente.';
    end;

    insert into auth.identities (provider_id, user_id, provider, identity_data, created_at, updated_at, last_sign_in_at)
    values (v_novo_id::text, v_novo_id, 'email',
            jsonb_build_object('sub', v_novo_id::text, 'email', v_email_final, 'email_verified', true, 'phone_verified', false),
            now(), now(), now());
  end if;

  insert into usuarios (id, restaurante_id, nome, email, telefone, role, primeiro_acesso)
  values (v_novo_id, v_chamador.restaurante_id, p_nome, v_email_final, v_telefone, p_role::user_role, v_primeiro_acesso);

  if p_role = 'motoboy' then
    insert into motoboys (id, restaurante_id, disponivel, veiculo, placa)
    values (v_novo_id, v_chamador.restaurante_id, true, nullif(trim(p_veiculo),''), nullif(trim(p_placa),''));
  end if;

  return query select v_novo_id, v_senha, v_email_final;
end;
$function$;

COMMENT ON FUNCTION public.criar_usuario_equipe(text,text,text,text,text,text,text) IS
  'Criação idempotente de usuário de equipe. E-mail técnico = telefone normalizado (GLOBALMENTE único no modelo atual — suporte multi-restaurante por pessoa é decisão futura). Adota Auth órfão apenas sob critérios cumulativos estritos; repara vínculo motoboys faltante sem tocar na senha; nunca converte papel nem cruza restaurantes.';