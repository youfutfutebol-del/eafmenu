create or replace function public.criar_restaurante_com_dono(
  p_nome_restaurante text,
  p_dono_nome text,
  p_dono_telefone text,
  p_dono_email text,
  p_dono_senha text
) returns table(restaurante_id uuid, dono_id uuid)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_restaurante_id uuid := gen_random_uuid();
  v_dono_id uuid := gen_random_uuid();
  v_email_final text;
  v_slug_base text;
  v_slug text;
  v_sufixo int := 0;
begin
  if not eh_super_admin() then
    raise exception 'Só administradores da plataforma podem criar restaurantes.';
  end if;

  if p_nome_restaurante is null or trim(p_nome_restaurante) = '' then
    raise exception 'Nome do restaurante é obrigatório.';
  end if;
  if p_dono_telefone is null or trim(p_dono_telefone) = '' then
    raise exception 'Telefone do dono é obrigatório.';
  end if;
  if p_dono_senha is null or length(trim(p_dono_senha)) < 4 then
    raise exception 'A senha do dono precisa ter pelo menos 4 caracteres.';
  end if;

  v_email_final := lower(coalesce(nullif(trim(p_dono_email), ''), trim(p_dono_telefone) || '@sememail.eafmenu.local'));

  -- Gera um slug único a partir do nome (ex: "Pizzaria do João" -> "pizzaria-do-joao")
  v_slug_base := lower(trim(p_nome_restaurante));
  v_slug_base := translate(v_slug_base,
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn');
  v_slug_base := regexp_replace(v_slug_base, '[^a-z0-9]+', '-', 'g');
  v_slug_base := trim(both '-' from v_slug_base);
  if v_slug_base = '' then v_slug_base := 'restaurante'; end if;

  v_slug := v_slug_base;
  while exists(select 1 from restaurantes where slug = v_slug) loop
    v_sufixo := v_sufixo + 1;
    v_slug := v_slug_base || '-' || v_sufixo;
  end loop;

  insert into restaurantes (id, nome, slug)
  values (v_restaurante_id, trim(p_nome_restaurante), v_slug);

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_current,
    email_change_token_new, phone_change_token, reauthentication_token, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_dono_id, 'authenticated', 'authenticated', v_email_final,
    crypt(trim(p_dono_senha), gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('nome', p_dono_nome),
    '', '', '', '', '', '', ''
  );

  insert into auth.identities (
    provider_id, user_id, provider, identity_data, created_at, updated_at, last_sign_in_at
  ) values (
    v_dono_id::text, v_dono_id, 'email',
    jsonb_build_object('sub', v_dono_id::text, 'email', v_email_final, 'email_verified', true, 'phone_verified', false),
    now(), now(), now()
  );

  insert into usuarios (id, restaurante_id, nome, email, telefone, role, primeiro_acesso)
  values (v_dono_id, v_restaurante_id, p_dono_nome, v_email_final, trim(p_dono_telefone), 'dono', false);

  return query select v_restaurante_id, v_dono_id;
end;
$$;
grant execute on function criar_restaurante_com_dono(text,text,text,text,text) to authenticated;
