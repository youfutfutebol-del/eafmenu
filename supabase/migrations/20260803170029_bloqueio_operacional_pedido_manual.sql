create or replace function public.criar_pedido_manual_v1(
  p_restaurante_id uuid,
  p_nome_cliente text,
  p_telefone_cliente text,
  p_tipo public.tipo_pedido,
  p_forma_pagamento text,
  p_troco_para numeric,
  p_observacoes text,
  p_endereco jsonb,
  p_itens jsonb,
  p_desconto jsonb,
  p_senha_autorizador text,
  p_chave_idempotencia text
) returns table(pedido_id uuid, numero_diario integer, total numeric, reutilizado boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_usuario uuid;
begin
  select u.restaurante_id into v_restaurante_usuario
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  if v_restaurante_usuario is distinct from p_restaurante_id then
    raise exception using message = 'Usuário sem permissão para este restaurante.', errcode = '42501';
  end if;
  if not public.restaurante_operacional(p_restaurante_id) then
    raise exception using
      message = 'O restaurante está temporariamente suspenso e não pode criar pedidos manuais.',
      errcode = '55000';
  end if;
  if not public.recurso_disponivel_restaurante(
    p_restaurante_id,
    'pedido_manual'
  ) then
    raise exception using
      message = 'Recurso indisponível para este restaurante.',
      detail = 'pedido_manual',
      hint = 'Consulte o plano e as exceções individuais do restaurante.',
      errcode = '42501';
  end if;

  return query
  select * from public._criar_pedido_manual_v1_impl_estado_operacional(
    p_restaurante_id, p_nome_cliente, p_telefone_cliente, p_tipo,
    p_forma_pagamento, p_troco_para, p_observacoes, p_endereco, p_itens,
    p_desconto, p_senha_autorizador, p_chave_idempotencia
  );
end;
$$;

revoke all on function public.criar_pedido_manual_v1(
  uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text
) from public, anon;
grant execute on function public.criar_pedido_manual_v1(
  uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text
) to authenticated, service_role;
