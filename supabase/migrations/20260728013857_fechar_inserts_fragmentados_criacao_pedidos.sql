drop policy if exists cliente_cria_pedido on public.pedidos;
drop policy if exists staff_cria_pedido_manual on public.pedidos;
drop policy if exists cliente_insere_itens_proprio_pedido on public.itens_pedido;
drop policy if exists staff_insere_itens_pedido_manual on public.itens_pedido;
drop policy if exists cliente_cria_sabores_proprios_itens on public.itens_pedido_sabores;
drop policy if exists staff_insere_sabores_restaurante on public.itens_pedido_sabores;
drop policy if exists cliente_cria_proprios_enderecos on public.enderecos_cliente;
drop policy if exists staff_cria_enderecos_do_restaurante on public.enderecos_cliente;
drop policy if exists staff_insere_clientes_manual on public.clientes;

revoke insert on table public.clientes from anon, authenticated;
revoke insert on table public.enderecos_cliente from anon, authenticated;
revoke insert on table public.pedidos from anon, authenticated;
revoke insert on table public.itens_pedido from anon, authenticated;
revoke insert on table public.itens_pedido_sabores from anon, authenticated;

do $$
begin
  if has_table_privilege('authenticated','public.clientes','INSERT')
     or has_table_privilege('authenticated','public.enderecos_cliente','INSERT')
     or has_table_privilege('authenticated','public.pedidos','INSERT')
     or has_table_privilege('authenticated','public.itens_pedido','INSERT')
     or has_table_privilege('authenticated','public.itens_pedido_sabores','INSERT') then
    raise exception 'INSERT fragmentado ainda concedido.';
  end if;
end $$;