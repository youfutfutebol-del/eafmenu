create or replace function public.remover_restaurante(p_restaurante_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
begin
  if not eh_super_admin() then
    raise exception 'Só administradores da plataforma podem remover restaurantes.';
  end if;

  if not exists(select 1 from restaurantes where id = p_restaurante_id) then
    raise exception 'Restaurante não encontrado.';
  end if;

  -- Apaga as contas de login (auth) de toda a equipe desse restaurante.
  -- As tabelas de negócio (usuarios, pedidos, produtos, etc.) já têm CASCADE
  -- configurado a partir de restaurantes, então basta apagar o restaurante no final.
  delete from auth.identities where user_id in (select id from usuarios where restaurante_id = p_restaurante_id);
  delete from auth.users where id in (select id from usuarios where restaurante_id = p_restaurante_id);

  delete from restaurantes where id = p_restaurante_id;

  return true;
end;
$$;
grant execute on function remover_restaurante(uuid) to authenticated;
