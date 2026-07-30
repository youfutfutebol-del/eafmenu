alter table pedido_status_historico drop constraint pedido_status_historico_alterado_por_fkey;
alter table pedido_status_historico
  add constraint pedido_status_historico_alterado_por_fkey
  foreign key (alterado_por) references auth.users(id) on delete set null;