-- Permite que a equipe do restaurante (dono/gerente/atendente) crie e edite
-- endereços de clientes ao lançar um pedido manual pelo painel — antes só o
-- próprio cliente (via cardápio) tinha essa permissão.
create policy staff_cria_enderecos_do_restaurante on enderecos_cliente
  for insert
  with check (
    cliente_id in (select id from clientes where restaurante_id = auth_restaurante_id())
    and auth_role() = ANY (ARRAY['dono'::user_role, 'gerente'::user_role, 'atendente'::user_role])
  );

create policy staff_edita_enderecos_do_restaurante on enderecos_cliente
  for update
  using (
    cliente_id in (select id from clientes where restaurante_id = auth_restaurante_id())
    and auth_role() = ANY (ARRAY['dono'::user_role, 'gerente'::user_role, 'atendente'::user_role])
  );