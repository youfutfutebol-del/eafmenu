
CREATE OR REPLACE FUNCTION public.vincular_cliente_por_telefone(p_restaurante_id uuid, p_telefone text, p_nome text)
RETURNS clientes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_cliente clientes;
  v_cliente_atual_sessao clientes;
  v_telefone_norm text;
begin
  if auth.uid() is null then
    raise exception 'Sessão inválida.';
  end if;

  v_telefone_norm := regexp_replace(p_telefone, '\D', '', 'g');

  -- Busca cliente existente pelo restaurante + telefone normalizado (ignora formatação: espaços, traços, parênteses)
  select * into v_cliente
  from clientes
  where restaurante_id = p_restaurante_id
    and regexp_replace(telefone, '\D', '', 'g') = v_telefone_norm;

  -- Caso 3: telefone não existe nesse restaurante -> cria normalmente
  if v_cliente.id is null then
    -- Impede violar UNIQUE(auth_user_id, restaurante_id): a sessão atual não pode já ter outro cliente aqui
    select * into v_cliente_atual_sessao
    from clientes
    where restaurante_id = p_restaurante_id
      and auth_user_id = auth.uid();

    if v_cliente_atual_sessao.id is not null then
      raise exception 'Esta sessão já está vinculada a outro cadastro neste restaurante.';
    end if;

    insert into clientes (nome, telefone, restaurante_id, auth_user_id)
    values (p_nome, p_telefone, p_restaurante_id, auth.uid())
    returning * into v_cliente;
    return v_cliente;
  end if;

  -- Caso 1: telefone já pertence à sessão atual -> retorna sem duplicar, sem sobrescrever nome
  if v_cliente.auth_user_id = auth.uid() then
    return v_cliente;
  end if;

  -- Caso 2: telefone pertence a outra sessão (nula ou anônima antiga) -> recupera o cadastro,
  -- transferindo o vínculo para a sessão atual, preservando id, nome e todos os registros relacionados.
  -- Antes de transferir, impede violar UNIQUE(auth_user_id, restaurante_id): a sessão atual não pode
  -- já ter outro cliente distinto neste restaurante.
  select * into v_cliente_atual_sessao
  from clientes
  where restaurante_id = p_restaurante_id
    and auth_user_id = auth.uid();

  if v_cliente_atual_sessao.id is not null and v_cliente_atual_sessao.id <> v_cliente.id then
    raise exception 'Esta sessão já está vinculada a outro cadastro neste restaurante.';
  end if;

  update clientes
     set auth_user_id = auth.uid()
   where id = v_cliente.id
  returning * into v_cliente;

  return v_cliente;
end;
$function$;
