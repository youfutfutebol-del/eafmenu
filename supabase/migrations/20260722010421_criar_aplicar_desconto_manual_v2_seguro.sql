
create function public.aplicar_desconto_manual_v2(
  p_pedido_id uuid,
  p_tipo text,
  p_valor numeric,
  p_motivo text,
  p_autorizado_por uuid,
  p_senha_autorizador text
)
returns table(
  pedido_id uuid, subtotal numeric, desconto_tipo text,
  desconto_valor_informado numeric, desconto_manual numeric,
  taxa_entrega numeric, total numeric, desconto_motivo text,
  desconto_aplicado_por uuid, desconto_autorizado_por uuid
)
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_uid uuid;
  v_aplicador public.usuarios%rowtype;
  v_autorizador public.usuarios%rowtype;
  v_pedido public.pedidos%rowtype;
  v_itens_count int;
  v_motivo text;
  v_desconto_calculado numeric;
  v_total_final numeric;
  v_autorizacao_ok boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception 'Usuário não autenticado.'; end if;

  select * into v_aplicador from public.usuarios u where u.id = v_uid;
  if not found or v_aplicador.ativo is not true
     or v_aplicador.role not in ('dono','gerente','atendente') then
    raise exception 'Usuário não autorizado a aplicar desconto.';
  end if;

  select * into v_pedido from public.pedidos pe where pe.id = p_pedido_id for update;
  if not found then raise exception 'Pedido não encontrado.'; end if;
  if v_pedido.restaurante_id is distinct from v_aplicador.restaurante_id then
    raise exception 'Pedido não pertence ao restaurante do usuário aplicador.';
  end if;
  if v_pedido.status = 'cancelado' then raise exception 'Pedido cancelado não pode receber desconto.'; end if;
  if v_pedido.pago then raise exception 'Pedido já pago não pode receber desconto.'; end if;

  select count(*) into v_itens_count from public.itens_pedido ip where ip.pedido_id=p_pedido_id;
  if v_itens_count=0 then raise exception 'Pedido não possui itens.'; end if;
  if v_pedido.subtotal<=0 then raise exception 'Pedido sem subtotal calculado.'; end if;

  if p_tipo is null or p_tipo not in ('valor','percentual') then
    raise exception 'Tipo de desconto inválido. Use valor ou percentual.';
  end if;
  if p_valor is null or p_valor<=0 then raise exception 'Valor do desconto deve ser positivo.'; end if;

  v_motivo:=btrim(coalesce(p_motivo,''));
  if v_motivo='' then raise exception 'Motivo do desconto é obrigatório.'; end if;

  if p_autorizado_por is null or btrim(coalesce(p_senha_autorizador,''))='' then
    raise exception 'Autorização inválida.';
  end if;

  select * into v_autorizador from public.usuarios u where u.id=p_autorizado_por;

  if v_aplicador.role in ('dono','gerente') then
    v_autorizacao_ok :=
      v_autorizador.id is not null and v_autorizador.id=v_uid
      and v_autorizador.ativo is true
      and v_autorizador.restaurante_id=v_pedido.restaurante_id
      and v_autorizador.role=v_aplicador.role
      and exists (
        select 1 from auth.users au where au.id=v_autorizador.id
        and au.encrypted_password=extensions.crypt(p_senha_autorizador,au.encrypted_password)
      );
  else
    v_autorizacao_ok :=
      v_autorizador.id is not null and v_autorizador.id<>v_uid
      and v_autorizador.ativo is true
      and v_autorizador.restaurante_id=v_pedido.restaurante_id
      and v_autorizador.role in ('dono','gerente')
      and exists (
        select 1 from auth.users au where au.id=v_autorizador.id
        and au.encrypted_password=extensions.crypt(p_senha_autorizador,au.encrypted_password)
      );
  end if;

  if not coalesce(v_autorizacao_ok,false) then raise exception 'Autorização inválida.'; end if;

  if p_tipo='percentual' then
    if p_valor>100 then raise exception 'Percentual de desconto não pode ultrapassar 100%%.'; end if;
    v_desconto_calculado:=round(v_pedido.subtotal*p_valor/100,2);
  else
    if p_valor>v_pedido.subtotal then raise exception 'Valor de desconto não pode ultrapassar o subtotal.'; end if;
    v_desconto_calculado:=round(p_valor,2);
  end if;

  v_total_final:=round(v_pedido.subtotal-v_desconto_calculado+v_pedido.taxa_entrega,2);
  if v_total_final<0 then raise exception 'Total do pedido não pode ser negativo.'; end if;

  perform set_config('eafmenu.via_desconto_manual','true',true);
  update public.pedidos pe set
    desconto_tipo=p_tipo, desconto_valor_informado=round(p_valor,2),
    desconto_manual=v_desconto_calculado, desconto_motivo=v_motivo,
    desconto_aplicado_por=v_uid, desconto_autorizado_por=v_autorizador.id,
    total=v_total_final
  where pe.id=p_pedido_id;

  return query
  select pe.id,pe.subtotal,pe.desconto_tipo,pe.desconto_valor_informado,
         pe.desconto_manual,pe.taxa_entrega,pe.total,pe.desconto_motivo,
         pe.desconto_aplicado_por,pe.desconto_autorizado_por
  from public.pedidos pe where pe.id=p_pedido_id;
end
$function$;

revoke all on function public.aplicar_desconto_manual_v2(uuid,text,numeric,text,uuid,text) from public;
revoke all on function public.aplicar_desconto_manual_v2(uuid,text,numeric,text,uuid,text) from anon;
revoke all on function public.aplicar_desconto_manual_v2(uuid,text,numeric,text,uuid,text) from authenticated;
grant execute on function public.aplicar_desconto_manual_v2(uuid,text,numeric,text,uuid,text) to authenticated,service_role;
