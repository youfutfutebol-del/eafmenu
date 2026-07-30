-- 1) Força taxa_entrega e zera subtotal/total na criação do pedido
create or replace function public.forcar_taxa_entrega_pedido()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_taxa numeric;
begin
  if new.tipo = 'entrega' then
    select taxa_entrega_padrao into v_taxa from restaurantes where id = new.restaurante_id;
    new.taxa_entrega := coalesce(v_taxa, 0);
  else
    new.taxa_entrega := 0;
  end if;

  new.subtotal := 0;
  new.total := new.taxa_entrega;

  return new;
end;
$$;

drop trigger if exists trg_forcar_taxa_entrega_pedido on public.pedidos;
create trigger trg_forcar_taxa_entrega_pedido
before insert on public.pedidos
for each row execute function public.forcar_taxa_entrega_pedido();

-- 2) Valida preço do item: exato se produto sem grupo, mínimo do grupo se tiver
create or replace function public.validar_preco_item_pedido()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_grupo_id uuid;
  v_preco_exato numeric;
  v_preco_minimo_grupo numeric;
begin
  select grupo_tamanho_id into v_grupo_id from produtos where id = new.produto_id;

  if v_grupo_id is null then
    select preco into v_preco_exato
    from produto_precos
    where produto_id = new.produto_id
      and ativo = true
      and opcao_tamanho_id is not distinct from new.opcao_tamanho_id;

    if v_preco_exato is null then
      raise exception 'Preço não encontrado para este produto/tamanho.';
    end if;

    if new.preco_unitario <> v_preco_exato then
      raise exception 'Preço do item não confere com o cadastrado.';
    end if;
  else
    select min(pp.preco) into v_preco_minimo_grupo
    from produtos p
    join produto_precos pp on pp.produto_id = p.id
    where p.grupo_tamanho_id = v_grupo_id
      and pp.ativo = true
      and pp.opcao_tamanho_id is not distinct from new.opcao_tamanho_id;

    if v_preco_minimo_grupo is null then
      raise exception 'Preço não encontrado para este grupo/tamanho.';
    end if;

    if new.preco_unitario < v_preco_minimo_grupo then
      raise exception 'Preço do item abaixo do mínimo permitido para este grupo de sabores.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validar_preco_item_pedido on public.itens_pedido;
create trigger trg_validar_preco_item_pedido
before insert on public.itens_pedido
for each row execute function public.validar_preco_item_pedido();

-- 3) Recalcula subtotal/total do pedido a partir dos itens já validados
create or replace function public.recalcular_totais_pedido()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
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

  update pedidos
  set subtotal = v_subtotal,
      total = v_subtotal + coalesce(v_taxa, 0)
  where id = v_pedido_id;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_recalcular_totais_pedido on public.itens_pedido;
create trigger trg_recalcular_totais_pedido
after insert or update or delete on public.itens_pedido
for each row execute function public.recalcular_totais_pedido();