
alter table public.grupos_tamanho
  add column if not exists categoria_id uuid null;

alter table public.grupos_tamanho
  add column if not exists permite_combinacao boolean not null default false;

alter table public.grupos_tamanho
  add column if not exists ativo boolean not null default true;

alter table public.grupos_tamanho
  add column if not exists ordem integer not null default 0;

alter table public.opcoes_tamanho
  add column if not exists ativo boolean not null default true;

alter table public.itens_pedido
  add column if not exists nome_grupo_snapshot text null;

alter table public.itens_pedido
  add column if not exists nome_tamanho_snapshot text null;

alter table public.itens_pedido
  add column if not exists sabores_esperados smallint null;

alter table public.itens_pedido
  add column if not exists precificacao_finalizada_em timestamptz null;

alter table public.itens_pedido
  add column if not exists chave_idempotencia text null;

alter table public.itens_pedido
  add column if not exists conteudo_idempotencia jsonb null;

alter table public.itens_pedido_sabores
  add column if not exists nome_produto_snapshot text null;

alter table public.itens_pedido_sabores
  add column if not exists ordem smallint null;

comment on column public.grupos_tamanho.max_sabores is
  'Campo legado. A futura fonte oficial do limite será opcoes_tamanho.max_sabores. Não utilizar em novas implementações.';
