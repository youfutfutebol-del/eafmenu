
-- Pedidos lançados manualmente pela equipe (telefone/balcão) não exigem
-- que o cliente tenha conta — guardamos nome/telefone direto no pedido.
alter table public.orders
  add column if not exists cliente_nome text,
  add column if not exists cliente_telefone text;

-- Equipe (dono/gerente/atendente) pode criar pedidos pro próprio tenant,
-- desde que não esteja se passando por um customer_id de outra pessoa.
create policy "staff_create_tenant_orders"
on public.orders for insert
to public
with check (
  tenant_id = current_tenant_id()
  and current_user_role() in ('dono', 'gerente', 'atendente')
  and customer_id is null
);
