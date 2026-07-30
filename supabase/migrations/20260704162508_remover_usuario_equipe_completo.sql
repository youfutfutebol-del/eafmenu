-- Remove um usuário da equipe (qualquer papel, incluindo motoboy) por completo:
-- apaga o registro de negócio (usuarios/motoboys) E a conta de login (auth.users),
-- em vez de deixar uma conta órfã sem acesso ao app mas ainda existindo no Auth.
create or replace function public.remover_usuario_equipe(p_usuario_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_chamador record;
  v_alvo record;
begin
  select role, restaurante_id into v_chamador from usuarios where id = auth.uid();
  if v_chamador is null or v_chamador.role <> 'dono' then
    raise exception 'Só o dono pode remover usuários.';
  end if;

  if p_usuario_id = auth.uid() then
    raise exception 'Você não pode remover a própria conta.';
  end if;

  select restaurante_id into v_alvo from usuarios where id = p_usuario_id;
  if v_alvo is null or v_alvo.restaurante_id <> v_chamador.restaurante_id then
    raise exception 'Usuário não encontrado nesse restaurante.';
  end if;

  delete from motoboys where id = p_usuario_id;
  delete from usuarios where id = p_usuario_id;
  delete from auth.identities where user_id = p_usuario_id;
  delete from auth.users where id = p_usuario_id;

  return true;
end;
$$;
grant execute on function remover_usuario_equipe(uuid) to authenticated;
