-- Usado pelo PWA do cliente ao se identificar: se o telefone já existe pra esse
-- restaurante (de uma sessão anônima anterior, outro aparelho, cache limpo etc.),
-- reconecta esse cliente à sessão atual em vez de tentar criar um duplicado
-- (que violaria a constraint única de restaurante+telefone).
create or replace function public.vincular_cliente_por_telefone(
  p_restaurante_id uuid,
  p_telefone text,
  p_nome text
) returns clientes
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_cliente clientes;
begin
  if auth.uid() is null then
    raise exception 'Sessão inválida.';
  end if;

  select * into v_cliente from clientes
  where restaurante_id = p_restaurante_id and telefone = p_telefone;

  if v_cliente.id is not null then
    update clientes
    set auth_user_id = auth.uid(), nome = p_nome
    where id = v_cliente.id
    returning * into v_cliente;
  else
    insert into clientes (nome, telefone, restaurante_id, auth_user_id)
    values (p_nome, p_telefone, p_restaurante_id, auth.uid())
    returning * into v_cliente;
  end if;

  return v_cliente;
end;
$$;
grant execute on function vincular_cliente_por_telefone(uuid, text, text) to anon, authenticated;
