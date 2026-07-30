BEGIN;

CREATE POLICY staff_ve_sabores_restaurante
ON public.itens_pedido_sabores
FOR SELECT
TO public
USING (
  auth_role() = ANY (ARRAY['dono','gerente','atendente']::user_role[])
  AND item_pedido_id IN (
    SELECT ip.id
    FROM itens_pedido ip
    JOIN pedidos p ON p.id = ip.pedido_id
    WHERE p.restaurante_id = auth_restaurante_id()
  )
);

CREATE POLICY staff_insere_sabores_restaurante
ON public.itens_pedido_sabores
FOR INSERT
TO public
WITH CHECK (
  auth_role() = ANY (ARRAY['dono','gerente','atendente']::user_role[])
  AND item_pedido_id IN (
    SELECT ip.id
    FROM itens_pedido ip
    JOIN pedidos p ON p.id = ip.pedido_id
    WHERE p.restaurante_id = auth_restaurante_id()
  )
  AND produto_id IN (
    SELECT id
    FROM produtos
    WHERE restaurante_id = auth_restaurante_id()
  )
);

COMMIT;
