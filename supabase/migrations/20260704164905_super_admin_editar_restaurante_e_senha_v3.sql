create or replace function public.super_admin_editar_restaurante(
  p_restaurante_id uuid,
  p_novo_nome text,
  p_novo_slug text default null
) returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
begin
  if not eh_super_admin() then
    raise exception 'Só administradores da plataforma podem editar restaurantes.';
  end if;

  if p_novo_nome is null or trim(p_novo_nome) = '' then
    raise exception 'Nome do restaurante é obrigatório.';
  end if;

  update restaurantes
  set nome = trim(p_novo_nome),
      slug = coalesce(nullif(trim(p_novo_slug), ''), slug)
  where id = p_restaurante_id;

  if not found then
    raise exception 'Restaurante não encontrado.';
  end if;

  return true;
end;
$$;
grant execute on function super_admin_editar_restaurante(uuid, text, text) to authenticated;

create or replace function public.super_admin_redefinir_senha(p_usuario_id uuid, p_nova_senha text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
begin
  if not eh_super_admin() then
    raise exception 'Só administradores da plataforma podem usar essa função.';
  end if;

  if p_nova_senha is null or length(trim(p_nova_senha)) < 4 then
    raise exception 'A senha precisa ter pelo menos 4 caracteres.';
  end if;

  update auth.users set encrypted_password = crypt(trim(p_nova_senha), gen_salt('bf')), updated_at = now()
  where id = p_usuario_id;

  if not found then
    raise exception 'Usuário não encontrado.';
  end if;

  return true;
end;
$$;
grant execute on function super_admin_redefinir_senha(uuid, text) to authenticated;
