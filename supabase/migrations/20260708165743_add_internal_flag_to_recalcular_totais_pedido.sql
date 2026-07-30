CREATE OR REPLACE FUNCTION public.recalcular_totais_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_pedido_id uuid;
  v_subtotal numeric;
  v_taxa numeric;
begin
  v_pedido_id := coalesce(new.pedido_id, old.pedido_id);

  select coalesce(sum(quantidade * preco_unitario), 0) into v_subtotal
  from itens_pedido
  where pedido_id = v_pedido_id;

  select taxa_entrega into v_taxa from pedidos where id = v_pedido_id;

  perform set_config('eafmenu.via_recalculo_interno', 'true', true);

  update pedidos
  set subtotal = v_subtotal,
      total = v_subtotal + coalesce(v_taxa, 0)
  where id = v_pedido_id;

  return coalesce(new, old);
end;
$function$;