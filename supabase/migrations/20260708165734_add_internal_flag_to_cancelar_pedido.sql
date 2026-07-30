CREATE OR REPLACE FUNCTION public.cancelar_pedido(p_pedido_id uuid, p_motivo text, p_senha_confirmacao text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_chamador record;
  v_pedido record;
  v_confirmador_id uuid;
  v_senha_ok boolean := false;
  v_candidato record;
begin
  select id, role, restaurante_id into v_chamador
  from usuarios where id = auth.uid();

  if v_chamador is null or v_chamador.role not in ('dono','gerente','atendente') then
    raise exception 'Você não tem permissão para cancelar pedidos.';
  end if;

  select id, restaurante_id, status into v_pedido
  from pedidos where id = p_pedido_id;

  if v_pedido is null or v_pedido.restaurante_id <> v_chamador.restaurante_id then
    raise exception 'Pedido não encontrado nesse restaurante.';
  end if;

  -- Única trava de status agora: pedido já cancelado não pode ser cancelado de novo.
  -- Antes bloqueava entregue/retirado também; isso mudou por decisão de produto.
  if v_pedido.status = 'cancelado' then
    raise exception 'Este pedido já está cancelado.';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Informe o motivo do cancelamento.';
  end if;

  if p_senha_confirmacao is null or length(trim(p_senha_confirmacao)) = 0 then
    raise exception 'Informe a senha de confirmação.';
  end if;

  if v_chamador.role in ('dono','gerente') then
    select exists (
      select 1 from auth.users
      where id = v_chamador.id
        and encrypted_password = crypt(p_senha_confirmacao, encrypted_password)
    ) into v_senha_ok;

    if v_senha_ok then
      v_confirmador_id := v_chamador.id;
    end if;

  else
    for v_candidato in
      select u.id, au.encrypted_password
      from usuarios u
      join auth.users au on au.id = u.id
      where u.restaurante_id = v_chamador.restaurante_id
        and u.role in ('dono','gerente')
        and u.ativo = true
    loop
      if v_candidato.encrypted_password = crypt(p_senha_confirmacao, v_candidato.encrypted_password) then
        v_confirmador_id := v_candidato.id;
        exit;
      end if;
    end loop;

    v_senha_ok := v_confirmador_id is not null;
  end if;

  if not v_senha_ok then
    raise exception 'Senha de confirmação incorreta.';
  end if;

  perform set_config('eafmenu.via_cancelar_pedido', 'true', true);

  update pedidos
  set status = 'cancelado',
      status_anterior = v_pedido.status,
      cancelado_em = now(),
      motivo_cancelamento = trim(p_motivo),
      cancelado_por = v_chamador.id,
      cancelado_confirmado_por = v_confirmador_id
  where id = p_pedido_id;

  return true;
end;
$function$;