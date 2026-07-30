-- Tabela de administradores da PLATAFORMA EAF Menu (não confundir com "dono" de um restaurante).
-- Um super admin não pertence a nenhum restaurante específico — ele cadastra novos restaurantes.
create table if not exists admins_plataforma (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  criado_em timestamptz not null default now()
);
alter table admins_plataforma enable row level security;
-- Nenhuma policy pra tabela pública: só é lida via funções SECURITY DEFINER abaixo.

-- Coloca a conta do Eduardo (que já existe e está sendo usada pra construir o sistema) como o primeiro super admin.
insert into admins_plataforma (id, nome)
values ('e372c7e1-02ca-42c9-99df-ae22fa7ff90d', 'Eduardo Freitas')
on conflict (id) do nothing;

-- Verifica se quem está chamando é super admin
create or replace function public.eh_super_admin()
returns boolean
language sql
security definer
set search_path to 'public'
stable
as $$
  select exists(select 1 from admins_plataforma where id = auth.uid());
$$;
grant execute on function eh_super_admin() to authenticated;

-- Lista os restaurantes (só super admin vê essa lista completa)
create or replace function public.listar_restaurantes_plataforma()
returns table(id uuid, nome text, slug text, criado_em timestamptz, total_usuarios bigint)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not eh_super_admin() then
    raise exception 'Só administradores da plataforma podem ver essa lista.';
  end if;

  return query
  select r.id, r.nome, r.slug, r.criado_em, count(u.id)
  from restaurantes r
  left join usuarios u on u.restaurante_id = r.id
  group by r.id, r.nome, r.slug, r.criado_em
  order by r.criado_em desc;
end;
$$;
grant execute on function listar_restaurantes_plataforma() to authenticated;

-- Cria um novo restaurante + o primeiro usuário "dono" dele, tudo numa função só.
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

  insert into restaurantes (id, nome)
  values (v_restaurante_id, trim(p_nome_restaurante));

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
