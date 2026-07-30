
create index idx_produtos_grupo_tamanho_id
  on public.produtos using btree (grupo_tamanho_id);
