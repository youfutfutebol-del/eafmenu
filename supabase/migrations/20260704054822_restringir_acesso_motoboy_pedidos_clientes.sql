-- Hoje "staff_ve_pedidos_restaurante" e "staff_ve_clientes" liberam SELECT pra
-- qualquer papel da equipe (sem excluir motoboy), então um motoboy conseguia ver
-- TODOS os pedidos e TODOS os clientes do restaurante via API, não só os que são
-- dele. Já existe uma policy própria (motoboy_ve_pedidos_atribuidos) cobrindo o
-- caso legítimo do motoboy (pedidos atribuídos a ele) — então essas duas policies
-- amplas passam a excluir explicitamente o papel motoboy.

drop policy if exists staff_ve_pedidos_restaurante on pedidos;
create policy staff_ve_pedidos_restaurante on pedidos
  for select
  using (
    restaurante_id = auth_restaurante_id()
    and auth_role() = ANY (ARRAY['dono'::user_role, 'gerente'::user_role, 'atendente'::user_role])
  );

drop policy if exists staff_ve_clientes on clientes;
create policy staff_ve_clientes on clientes
  for select
  using (
    restaurante_id = auth_restaurante_id()
    and auth_role() = ANY (ARRAY['dono'::user_role, 'gerente'::user_role, 'atendente'::user_role])
  );
