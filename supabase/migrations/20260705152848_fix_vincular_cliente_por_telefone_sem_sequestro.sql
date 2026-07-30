create or replace function public.vincular_cliente_por_telefone(
  p_restaurante_id uuid,
  p_telefone text,
  p_nome text
)
returns clientes
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

  select * into v_cliente
  from clientes
  where restaurante_id = p_restaurante_id and telefone = p_telefone;

  -- Caso 1: telefone não existe nesse restaurante -> cria normalmente
  if v_cliente.id is null then
    insert into clientes (nome, telefone, restaurante_id, auth_user_id)
    values (p_nome, p_telefone, p_restaurante_id, auth.uid())
    returning * into v_cliente;
    return v_cliente;
  end if;

  -- Caso 2: existe mas ainda sem ninguém vinculado -> vincula agora
  if v_cliente.auth_user_id is null then
    update clientes
    set auth_user_id = auth.uid(), nome = p_nome
    where id = v_cliente.id
    returning * into v_cliente;
    return v_cliente;
  end if;

  -- Caso 3: já é a mesma pessoa -> atualiza nome normalmente
  if v_cliente.auth_user_id = auth.uid() then
    update clientes
    set nome = p_nome
    where id = v_cliente.id
    returning * into v_cliente;
    return v_cliente;
  end if;

  -- Caso 4: telefone pertence a outra pessoa -> bloqueia, não sobrescreve
  raise exception 'Esse telefone já está vinculado a outra conta neste restaurante. Se for você, entre pelo mesmo celular/app que usou da última vez.';
end;
$$;