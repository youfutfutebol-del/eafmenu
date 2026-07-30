BEGIN;

-- ===================== 1. produto_precos =====================
ALTER TABLE public.produto_precos
  ADD COLUMN preco_promocional numeric(10,2),
  ADD COLUMN promocao_ativa boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.produto_precos.preco_promocional IS
  'Preço promocional simples (MVP). Pode ficar salvo mesmo com promocao_ativa=false.';
COMMENT ON COLUMN public.produto_precos.promocao_ativa IS
  'Liga/desliga a promoção. Sem calendário, horário ou cupom (MVP).';

ALTER TABLE public.produto_precos
  ADD CONSTRAINT chk_promocao_valida CHECK (
    (preco_promocional IS NULL OR (preco_promocional > 0 AND preco_promocional < preco))
    AND (NOT promocao_ativa OR preco_promocional IS NOT NULL)
  );

CREATE INDEX idx_produto_precos_promocao_ativa
  ON public.produto_precos (produto_id)
  WHERE promocao_ativa = true;

-- ===================== 2. itens_pedido: colunas + constraint de sabores_esperados =====================
ALTER TABLE public.itens_pedido
  ADD COLUMN preco_original_unitario numeric(10,2),
  ADD COLUMN preco_efetivo_unitario numeric(10,2),
  ADD COLUMN desconto_promocional_unitario numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN desconto_promocional_total numeric(10,2) NOT NULL DEFAULT 0;

UPDATE public.itens_pedido
SET preco_original_unitario = preco_unitario,
    preco_efetivo_unitario = preco_unitario,
    desconto_promocional_unitario = 0,
    desconto_promocional_total = 0
WHERE preco_original_unitario IS NULL;

ALTER TABLE public.itens_pedido
  ALTER COLUMN preco_original_unitario SET NOT NULL,
  ALTER COLUMN preco_efetivo_unitario SET NOT NULL;

ALTER TABLE public.itens_pedido
  ADD CONSTRAINT chk_preco_efetivo_igual_cobrado
    CHECK (preco_unitario = preco_efetivo_unitario),
  ADD CONSTRAINT chk_preco_efetivo_nao_maior_original
    CHECK (preco_efetivo_unitario <= preco_original_unitario),
  ADD CONSTRAINT chk_desconto_promocional_consistente CHECK (
    desconto_promocional_unitario = round(preco_original_unitario - preco_efetivo_unitario, 2)
    AND desconto_promocional_total = round(desconto_promocional_unitario * quantidade, 2)
  );

ALTER TABLE public.itens_pedido
  ADD CONSTRAINT chk_sabores_esperados_positivo
  CHECK (
    sabores_esperados IS NULL
    OR sabores_esperados >= 1
  );

-- ===================== 3. itens_pedido_sabores: snapshot com backfill seguro + constraints =====================
ALTER TABLE public.itens_pedido_sabores
  ADD COLUMN preco_original_unitario numeric(10,2);

UPDATE public.itens_pedido_sabores
SET preco_original_unitario = preco_unitario
WHERE preco_original_unitario IS NULL;

ALTER TABLE public.itens_pedido_sabores
  ALTER COLUMN preco_original_unitario SET NOT NULL;

ALTER TABLE public.itens_pedido_sabores
  ADD CONSTRAINT chk_sabor_preco_original_positivo CHECK (preco_original_unitario > 0),
  ADD CONSTRAINT chk_sabor_preco_unitario_positivo CHECK (preco_unitario > 0),
  ADD CONSTRAINT chk_sabor_preco_efetivo_nao_maior CHECK (preco_unitario <= preco_original_unitario),
  ADD CONSTRAINT uq_item_pedido_sabor UNIQUE (item_pedido_id, produto_id);

-- ===================== 4. pedidos: colunas de totais promocionais =====================
ALTER TABLE public.pedidos
  ADD COLUMN subtotal_bruto numeric(10,2),
  ADD COLUMN desconto_promocional numeric(10,2);

UPDATE public.pedidos
SET subtotal_bruto = subtotal,
    desconto_promocional = 0
WHERE subtotal_bruto IS NULL;

ALTER TABLE public.pedidos
  ALTER COLUMN subtotal_bruto SET NOT NULL,
  ALTER COLUMN subtotal_bruto SET DEFAULT 0,
  ALTER COLUMN desconto_promocional SET NOT NULL,
  ALTER COLUMN desconto_promocional SET DEFAULT 0;

ALTER TABLE public.pedidos
  ADD CONSTRAINT chk_subtotal_bruto_consistente
    CHECK (round(subtotal_bruto - desconto_promocional, 2) = subtotal);

-- ===================== 5. validar_preco_item_pedido =====================
CREATE OR REPLACE FUNCTION public.validar_preco_item_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_pedido_restaurante_id uuid;
  v_produto record;
  v_grupo record;
  v_qtd_sabores integer;
  v_preco_normal numeric;
  v_promo_ativa boolean;
  v_preco_promo numeric;
  v_preco_efetivo numeric;
  v_preco_maximo_efetivo numeric;
  v_max_sabores_grupo integer;
  v_max_sabores_tamanho integer;
  v_max_sabores_efetivo integer;
  v_tamanho_grupo_id uuid;
  v_sabores_elegiveis integer;
begin
  select restaurante_id into v_pedido_restaurante_id from pedidos where id = new.pedido_id;

  if v_pedido_restaurante_id is null then
    raise exception 'Pedido não encontrado.';
  end if;

  select id, restaurante_id, grupo_tamanho_id, ativo
    into v_produto
  from produtos where id = new.produto_id;

  if v_produto.id is null then
    raise exception 'Produto não encontrado.';
  end if;

  if v_produto.restaurante_id <> v_pedido_restaurante_id then
    raise exception 'Produto pertence a um restaurante diferente do pedido.';
  end if;

  if not coalesce(v_produto.ativo, false) then
    raise exception 'Produto está inativo.';
  end if;

  v_qtd_sabores := coalesce(new.sabores_esperados, 1);

  if v_qtd_sabores <= 1 then
    select preco, promocao_ativa, preco_promocional
      into v_preco_normal, v_promo_ativa, v_preco_promo
    from produto_precos
    where produto_id = new.produto_id
      and ativo = true
      and opcao_tamanho_id is not distinct from new.opcao_tamanho_id;

    if v_preco_normal is null then
      raise exception 'Preço não encontrado para este produto/tamanho.';
    end if;

    v_preco_efetivo := case when v_promo_ativa and v_preco_promo is not null
                             then v_preco_promo else v_preco_normal end;

    if new.preco_unitario <> v_preco_efetivo then
      raise exception 'Preço do item não confere com o cadastrado.';
    end if;

    new.preco_original_unitario := v_preco_normal;
    new.preco_efetivo_unitario := v_preco_efetivo;
    new.desconto_promocional_unitario := round(v_preco_normal - v_preco_efetivo, 2);
    new.desconto_promocional_total := round((v_preco_normal - v_preco_efetivo) * new.quantidade, 2);
    new.precificacao_finalizada_em := now();

  else
    if new.sabores_esperados is null or new.sabores_esperados < 2 then
      raise exception 'sabores_esperados deve ser no mínimo 2 para item multissabor.';
    end if;

    if v_produto.grupo_tamanho_id is null then
      raise exception 'sabores_esperados > 1 exige produto vinculado a um grupo de tamanhos.';
    end if;

    select id, restaurante_id, max_sabores
      into v_grupo
    from grupos_tamanho where id = v_produto.grupo_tamanho_id;

    if v_grupo.id is null then
      raise exception 'Grupo de tamanhos não encontrado.';
    end if;

    if v_grupo.restaurante_id <> v_pedido_restaurante_id then
      raise exception 'Grupo de tamanhos pertence a um restaurante diferente do pedido.';
    end if;

    v_max_sabores_grupo := v_grupo.max_sabores;

    if new.opcao_tamanho_id is not null then
      select grupo_id, max_sabores into v_tamanho_grupo_id, v_max_sabores_tamanho
      from opcoes_tamanho where id = new.opcao_tamanho_id;

      if v_tamanho_grupo_id is null or v_tamanho_grupo_id <> v_grupo.id then
        raise exception 'Tamanho informado não pertence ao grupo deste produto.';
      end if;
    else
      v_max_sabores_tamanho := null;
    end if;

    v_max_sabores_efetivo := coalesce(v_max_sabores_tamanho, v_max_sabores_grupo);

    if coalesce(v_max_sabores_efetivo, 1) <= 1 then
      raise exception 'Este grupo/tamanho não permite mais de um sabor (max_sabores <= 1).';
    end if;

    select count(distinct p.id) into v_sabores_elegiveis
    from produtos p
    join produto_precos pp on pp.produto_id = p.id
    where p.grupo_tamanho_id = v_grupo.id
      and p.restaurante_id = v_pedido_restaurante_id
      and p.ativo = true
      and pp.ativo = true
      and pp.opcao_tamanho_id is not distinct from new.opcao_tamanho_id;

    if new.sabores_esperados > v_sabores_elegiveis then
      raise exception 'Quantidade de sabores escolhida excede os sabores disponíveis neste tamanho.';
    end if;

    select max(
      case when pp.promocao_ativa and pp.preco_promocional is not null
           then pp.preco_promocional else pp.preco end
    ) into v_preco_maximo_efetivo
    from produtos p
    join produto_precos pp on pp.produto_id = p.id
    where p.grupo_tamanho_id = v_grupo.id
      and p.restaurante_id = v_pedido_restaurante_id
      and p.ativo = true
      and pp.ativo = true
      and pp.opcao_tamanho_id is not distinct from new.opcao_tamanho_id;

    if v_preco_maximo_efetivo is null then
      raise exception 'Nenhum preço ativo encontrado para este grupo/tamanho no restaurante do pedido.';
    end if;

    if new.sabores_esperados > v_max_sabores_efetivo then
      raise exception 'sabores_esperados (%) excede o máximo permitido para este grupo/tamanho (%).',
        new.sabores_esperados, v_max_sabores_efetivo;
    end if;

    new.preco_unitario := v_preco_maximo_efetivo;
    new.preco_original_unitario := v_preco_maximo_efetivo;
    new.preco_efetivo_unitario := v_preco_maximo_efetivo;
    new.desconto_promocional_unitario := 0;
    new.desconto_promocional_total := 0;
    new.precificacao_finalizada_em := null;
  end if;

  return new;
end;
$function$;

-- ===================== 6. validar_sabor_item_pedido =====================
CREATE OR REPLACE FUNCTION public.validar_sabor_item_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item record;
  v_pedido_restaurante_id uuid;
  v_produto record;
  v_preco record;
  v_grupo_id_item uuid;
  v_qtd_atual integer;
  v_max_sabores_grupo integer;
  v_max_sabores_tamanho integer;
  v_max_sabores_efetivo integer;
begin
  select ip.id, ip.pedido_id, ip.opcao_tamanho_id, ip.sabores_esperados,
         ip.precificacao_finalizada_em, ip.produto_id
    into v_item
  from itens_pedido ip
  where ip.id = new.item_pedido_id
  for update;

  if v_item.id is null then
    raise exception 'Item de pedido pai não encontrado.';
  end if;

  if v_item.precificacao_finalizada_em is not null then
    raise exception 'Este item já teve a precificação finalizada; não é possível inserir novos sabores.';
  end if;

  if coalesce(v_item.sabores_esperados, 1) <= 1 then
    raise exception 'Este item não é multissabor (sabores_esperados <= 1).';
  end if;

  select grupo_tamanho_id into v_grupo_id_item from produtos where id = v_item.produto_id;

  select p.restaurante_id, p.grupo_tamanho_id, p.ativo
    into v_produto
  from produtos p
  where p.id = new.produto_id;

  if v_produto.restaurante_id is null then
    raise exception 'Produto do sabor não encontrado.';
  end if;

  if not v_produto.ativo then
    raise exception 'Produto do sabor está inativo.';
  end if;

  select restaurante_id into v_pedido_restaurante_id from pedidos where id = v_item.pedido_id;

  if v_produto.restaurante_id <> v_pedido_restaurante_id then
    raise exception 'Sabor pertence a um produto de outro restaurante.';
  end if;

  if v_produto.grupo_tamanho_id is null or v_produto.grupo_tamanho_id <> v_grupo_id_item then
    raise exception 'Sabor não pertence ao mesmo grupo de tamanhos do item.';
  end if;

  select pp.preco, pp.promocao_ativa, pp.preco_promocional, pp.ativo
    into v_preco
  from produto_precos pp
  where pp.produto_id = new.produto_id
    and pp.opcao_tamanho_id is not distinct from v_item.opcao_tamanho_id;

  if v_preco.preco is null or not v_preco.ativo then
    raise exception 'Sabor não possui preço ativo para este tamanho.';
  end if;

  if exists (
    select 1 from itens_pedido_sabores s
    where s.item_pedido_id = new.item_pedido_id and s.produto_id = new.produto_id
  ) then
    raise exception 'Este sabor já foi adicionado a este item.';
  end if;

  select count(*) into v_qtd_atual
  from itens_pedido_sabores
  where item_pedido_id = new.item_pedido_id;

  if v_qtd_atual + 1 > v_item.sabores_esperados then
    raise exception 'Quantidade de sabores inserida excede o esperado para este item.';
  end if;

  select ot.max_sabores, gt.max_sabores
    into v_max_sabores_tamanho, v_max_sabores_grupo
  from grupos_tamanho gt
  left join opcoes_tamanho ot on ot.id = v_item.opcao_tamanho_id
  where gt.id = v_grupo_id_item;

  v_max_sabores_efetivo := coalesce(v_max_sabores_tamanho, v_max_sabores_grupo);

  if v_max_sabores_efetivo is not null and (v_qtd_atual + 1) > v_max_sabores_efetivo then
    raise exception 'Quantidade de sabores excede o máximo permitido para este grupo (%).', v_max_sabores_efetivo;
  end if;

  new.preco_original_unitario := v_preco.preco;
  new.preco_unitario := case when v_preco.promocao_ativa and v_preco.preco_promocional is not null
                              then v_preco.preco_promocional else v_preco.preco end;
  select nome into new.nome_produto_snapshot from produtos where id = new.produto_id;

  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_validar_sabor_item_pedido ON public.itens_pedido_sabores;
CREATE TRIGGER trg_validar_sabor_item_pedido
BEFORE INSERT ON public.itens_pedido_sabores
FOR EACH ROW EXECUTE FUNCTION public.validar_sabor_item_pedido();

-- ===================== 7. finalizar_precificacao_grupo_sabores (com arredondamento corrigido) =====================
CREATE OR REPLACE FUNCTION public.finalizar_precificacao_grupo_sabores()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item record;
  v_qtd_atual integer;
  v_media_normal numeric;
  v_media_efetiva numeric;
  v_preco_original_final numeric;
  v_preco_efetivo_final numeric;
  v_desconto_unitario_final numeric;
  v_desconto_total_final numeric;
begin
  select ip.id, ip.quantidade, ip.sabores_esperados, ip.precificacao_finalizada_em
    into v_item
  from itens_pedido ip
  where ip.id = new.item_pedido_id
  for update;

  if v_item.precificacao_finalizada_em is not null then
    return new;
  end if;

  select count(*), avg(preco_original_unitario), avg(preco_unitario)
    into v_qtd_atual, v_media_normal, v_media_efetiva
  from itens_pedido_sabores
  where item_pedido_id = v_item.id;

  if v_qtd_atual < v_item.sabores_esperados then
    return new;
  end if;

  if v_qtd_atual > v_item.sabores_esperados then
    raise exception 'Quantidade de sabores (%) excede sabores_esperados (%) para este item.',
      v_qtd_atual, v_item.sabores_esperados;
  end if;

  v_preco_original_final := round(v_media_normal, 2);
  v_preco_efetivo_final := round(v_media_efetiva, 2);

  v_desconto_unitario_final := round(v_preco_original_final - v_preco_efetivo_final, 2);
  v_desconto_total_final := round(v_desconto_unitario_final * v_item.quantidade, 2);

  perform set_config('eafmenu.via_recalculo_interno', 'true', true);

  update itens_pedido
  set preco_original_unitario = v_preco_original_final,
      preco_efetivo_unitario = v_preco_efetivo_final,
      preco_unitario = v_preco_efetivo_final,
      desconto_promocional_unitario = v_desconto_unitario_final,
      desconto_promocional_total = v_desconto_total_final,
      precificacao_finalizada_em = now()
  where id = v_item.id;

  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_finalizar_precificacao_grupo_sabores ON public.itens_pedido_sabores;
CREATE TRIGGER trg_finalizar_precificacao_grupo_sabores
AFTER INSERT ON public.itens_pedido_sabores
FOR EACH ROW EXECUTE FUNCTION public.finalizar_precificacao_grupo_sabores();

-- ===================== 8. bloquear_avanco_pedido_precificacao_pendente =====================
CREATE OR REPLACE FUNCTION public.bloquear_avanco_pedido_precificacao_pendente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (new.pago = true and coalesce(old.pago, false) = false)
     or (new.status in ('em_preparo','saiu_para_entrega','entregue','retirado')
         and new.status is distinct from old.status)
  then
    if exists (
      select 1 from itens_pedido
      where pedido_id = new.id
        and coalesce(sabores_esperados, 1) > 1
        and precificacao_finalizada_em is null
    ) then
      raise exception 'Pedido % possui item com precificação de sabores pendente. Não pode ser pago nem avançar de status.', new.id;
    end if;
  end if;
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_bloquear_avanco_pedido_precificacao_pendente ON public.pedidos;
CREATE TRIGGER trg_bloquear_avanco_pedido_precificacao_pendente
BEFORE UPDATE OF status, pago ON public.pedidos
FOR EACH ROW EXECUTE FUNCTION public.bloquear_avanco_pedido_precificacao_pendente();

-- ===================== 9. recalcular_totais_pedido =====================
CREATE OR REPLACE FUNCTION public.recalcular_totais_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_pedido_id uuid;
  v_subtotal_bruto numeric;
  v_subtotal numeric;
  v_desconto_promocional numeric;
  v_taxa numeric;
  v_desconto_manual numeric;
begin
  v_pedido_id := coalesce(new.pedido_id, old.pedido_id);

  select
    coalesce(sum(quantidade * preco_original_unitario), 0),
    coalesce(sum(quantidade * preco_efetivo_unitario), 0),
    coalesce(sum(desconto_promocional_total), 0)
    into v_subtotal_bruto, v_subtotal, v_desconto_promocional
  from itens_pedido
  where pedido_id = v_pedido_id;

  select taxa_entrega, desconto_manual into v_taxa, v_desconto_manual
  from pedidos where id = v_pedido_id;

  perform set_config('eafmenu.via_recalculo_interno', 'true', true);

  update pedidos
  set subtotal_bruto = round(v_subtotal_bruto, 2),
      desconto_promocional = round(v_desconto_promocional, 2),
      subtotal = round(v_subtotal, 2),
      total = round(v_subtotal - coalesce(v_desconto_manual, 0) + coalesce(v_taxa, 0), 2)
  where id = v_pedido_id;

  return coalesce(new, old);
end;
$function$;

-- ===================== 10. bloquear_edicao_financeira_direta =====================
DROP TRIGGER IF EXISTS trg_bloquear_edicao_financeira_direta ON public.pedidos;

CREATE OR REPLACE FUNCTION public.bloquear_edicao_financeira_direta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(current_setting('eafmenu.via_recalculo_interno', true), 'false') = 'true'
     or coalesce(current_setting('eafmenu.via_desconto_manual', true), 'false') = 'true' then
    return new;
  end if;

  if new.total is distinct from old.total
     or new.subtotal is distinct from old.subtotal
     or new.subtotal_bruto is distinct from old.subtotal_bruto
     or new.desconto_promocional is distinct from old.desconto_promocional
     or new.taxa_entrega is distinct from old.taxa_entrega
     or new.desconto_tipo is distinct from old.desconto_tipo
     or new.desconto_valor_informado is distinct from old.desconto_valor_informado
     or new.desconto_manual is distinct from old.desconto_manual
     or new.desconto_motivo is distinct from old.desconto_motivo
     or new.desconto_aplicado_por is distinct from old.desconto_aplicado_por
     or new.desconto_autorizado_por is distinct from old.desconto_autorizado_por
  then
    raise exception 'Total, subtotal, taxa de entrega e campos de desconto são calculados pelo sistema e não podem ser editados diretamente.';
  end if;

  return new;
end;
$function$;

CREATE TRIGGER trg_bloquear_edicao_financeira_direta
BEFORE UPDATE OF total, subtotal, subtotal_bruto, desconto_promocional, taxa_entrega,
  desconto_tipo, desconto_valor_informado, desconto_manual, desconto_motivo,
  desconto_aplicado_por, desconto_autorizado_por
ON public.pedidos
FOR EACH ROW EXECUTE FUNCTION public.bloquear_edicao_financeira_direta();

-- ===================== 11. forcar_taxa_entrega_pedido =====================
CREATE OR REPLACE FUNCTION public.forcar_taxa_entrega_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_taxa numeric;
begin
  if new.tipo = 'entrega' then
    select taxa_entrega_padrao into v_taxa from restaurantes where id = new.restaurante_id;
    new.taxa_entrega := coalesce(v_taxa, 0);
  else
    new.taxa_entrega := 0;
  end if;

  new.subtotal_bruto := 0;
  new.desconto_promocional := 0;
  new.subtotal := 0;
  new.total := new.taxa_entrega;

  return new;
end;
$function$;

COMMIT;
