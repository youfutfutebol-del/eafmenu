
-- =========================================================
-- 1. COLUNAS EM public.pedidos
-- =========================================================
ALTER TABLE public.pedidos
  ADD COLUMN desconto_tipo text NULL,
  ADD COLUMN desconto_valor_informado numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN desconto_manual numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN desconto_motivo text NULL,
  ADD COLUMN desconto_aplicado_por uuid NULL,
  ADD COLUMN desconto_autorizado_por uuid NULL;

-- =========================================================
-- 2. FOREIGN KEYS (sem ON DELETE CASCADE, preserva histórico)
-- =========================================================
ALTER TABLE public.pedidos
  ADD CONSTRAINT pedidos_desconto_aplicado_por_fkey
    FOREIGN KEY (desconto_aplicado_por) REFERENCES public.usuarios(id),
  ADD CONSTRAINT pedidos_desconto_autorizado_por_fkey
    FOREIGN KEY (desconto_autorizado_por) REFERENCES public.usuarios(id);

-- =========================================================
-- 3. CONSTRAINTS
-- =========================================================
ALTER TABLE public.pedidos
  ADD CONSTRAINT chk_desconto_tipo_valido
    CHECK (desconto_tipo IS NULL OR desconto_tipo IN ('valor','percentual')),

  ADD CONSTRAINT chk_desconto_nao_negativo
    CHECK (desconto_valor_informado >= 0 AND desconto_manual >= 0),

  ADD CONSTRAINT chk_desconto_manual_nao_excede_subtotal
    CHECK (desconto_manual <= subtotal),

  ADD CONSTRAINT chk_desconto_percentual_valido
    CHECK (desconto_tipo IS DISTINCT FROM 'percentual'
           OR (desconto_valor_informado > 0 AND desconto_valor_informado <= 100)),

  ADD CONSTRAINT chk_desconto_valor_fixo_valido
    CHECK (desconto_tipo IS DISTINCT FROM 'valor'
           OR desconto_valor_informado > 0),

  ADD CONSTRAINT chk_desconto_estado_consistente
    CHECK (
      (
        desconto_manual = 0
        AND desconto_tipo IS NULL
        AND desconto_valor_informado = 0
        AND desconto_motivo IS NULL
        AND desconto_aplicado_por IS NULL
        AND desconto_autorizado_por IS NULL
      )
      OR
      (
        desconto_manual > 0
        AND desconto_tipo IS NOT NULL
        AND desconto_valor_informado > 0
        AND desconto_motivo IS NOT NULL
        AND btrim(desconto_motivo) <> ''
        AND desconto_aplicado_por IS NOT NULL
        AND desconto_autorizado_por IS NOT NULL
      )
    );

-- =========================================================
-- 4. ATUALIZAR O RECÁLCULO FINANCEIRO (inclui desconto_manual)
-- =========================================================
CREATE OR REPLACE FUNCTION public.recalcular_totais_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_pedido_id uuid;
  v_subtotal numeric;
  v_taxa numeric;
  v_desconto numeric;
begin
  v_pedido_id := coalesce(new.pedido_id, old.pedido_id);

  select coalesce(sum(quantidade * preco_unitario), 0) into v_subtotal
  from itens_pedido
  where pedido_id = v_pedido_id;

  select taxa_entrega, desconto_manual into v_taxa, v_desconto
  from pedidos where id = v_pedido_id;

  perform set_config('eafmenu.via_recalculo_interno', 'true', true);

  update pedidos
  set subtotal = round(v_subtotal, 2),
      total = round(v_subtotal - coalesce(v_desconto, 0) + coalesce(v_taxa, 0), 2)
  where id = v_pedido_id;

  return coalesce(new, old);
end;
$function$;

-- =========================================================
-- 5. ATUALIZAR O BLOQUEIO DE EDIÇÃO FINANCEIRA DIRETA
--    (agora também protege os campos de desconto)
-- =========================================================
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

-- Trigger precisa disparar também quando só os campos de desconto mudarem
DROP TRIGGER IF EXISTS trg_bloquear_edicao_financeira_direta ON public.pedidos;
CREATE TRIGGER trg_bloquear_edicao_financeira_direta
  BEFORE UPDATE OF total, subtotal, taxa_entrega,
    desconto_tipo, desconto_valor_informado, desconto_manual,
    desconto_motivo, desconto_aplicado_por, desconto_autorizado_por
  ON public.pedidos
  FOR EACH ROW EXECUTE FUNCTION public.bloquear_edicao_financeira_direta();

-- =========================================================
-- 6. RPC aplicar_desconto_manual
-- =========================================================
CREATE OR REPLACE FUNCTION public.aplicar_desconto_manual(
  p_pedido_id uuid,
  p_tipo text,
  p_valor numeric,
  p_motivo text,
  p_autorizado_por uuid
)
RETURNS TABLE (
  pedido_id uuid,
  subtotal numeric,
  desconto_tipo text,
  desconto_valor_informado numeric,
  desconto_manual numeric,
  taxa_entrega numeric,
  total numeric,
  desconto_motivo text,
  desconto_aplicado_por uuid,
  desconto_autorizado_por uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid;
  v_aplicador public.usuarios%rowtype;
  v_autorizador public.usuarios%rowtype;
  v_pedido public.pedidos%rowtype;
  v_itens_count int;
  v_motivo text;
  v_desconto_calculado numeric;
  v_total_final numeric;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select * into v_aplicador from public.usuarios where id = v_uid;
  if not found then
    raise exception 'Usuário aplicador não encontrado em usuarios.';
  end if;
  if v_aplicador.ativo is not true then
    raise exception 'Usuário aplicador não está ativo.';
  end if;
  if v_aplicador.role = 'motoboy' then
    raise exception 'Motoboy não pode aplicar desconto.';
  end if;

  select * into v_pedido from public.pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'Pedido não encontrado.';
  end if;

  if v_pedido.restaurante_id is distinct from v_aplicador.restaurante_id then
    raise exception 'Pedido não pertence ao restaurante do usuário aplicador.';
  end if;

  if v_pedido.status = 'cancelado' then
    raise exception 'Pedido cancelado não pode receber desconto.';
  end if;

  if v_pedido.pago then
    raise exception 'Pedido já pago não pode receber desconto.';
  end if;

  select count(*) into v_itens_count from public.itens_pedido where pedido_id = p_pedido_id;
  if v_itens_count = 0 then
    raise exception 'Pedido não possui itens.';
  end if;

  if v_pedido.subtotal <= 0 then
    raise exception 'Pedido sem subtotal calculado.';
  end if;

  if p_tipo is null or p_tipo not in ('valor','percentual') then
    raise exception 'Tipo de desconto inválido. Use valor ou percentual.';
  end if;

  if p_valor is null or p_valor <= 0 then
    raise exception 'Valor do desconto deve ser positivo.';
  end if;

  v_motivo := btrim(coalesce(p_motivo, ''));
  if v_motivo = '' then
    raise exception 'Motivo do desconto é obrigatório.';
  end if;

  if p_autorizado_por is null then
    raise exception 'Autorizador é obrigatório.';
  end if;

  select * into v_autorizador from public.usuarios where id = p_autorizado_por;
  if not found then
    raise exception 'Autorizador não encontrado.';
  end if;
  if v_autorizador.ativo is not true then
    raise exception 'Autorizador não está ativo.';
  end if;
  if v_autorizador.restaurante_id is distinct from v_pedido.restaurante_id then
    raise exception 'Autorizador não pertence ao restaurante do pedido.';
  end if;
  if v_autorizador.role = 'motoboy' then
    raise exception 'Motoboy não pode autorizar desconto.';
  end if;

  if p_tipo = 'percentual' then
    if p_valor > 100 then
      raise exception 'Percentual de desconto não pode ultrapassar 100%%.';
    end if;
    v_desconto_calculado := round(v_pedido.subtotal * p_valor / 100, 2);
  else
    if p_valor > v_pedido.subtotal then
      raise exception 'Valor de desconto não pode ultrapassar o subtotal.';
    end if;
    v_desconto_calculado := round(p_valor, 2);
  end if;

  v_total_final := round(v_pedido.subtotal - v_desconto_calculado + v_pedido.taxa_entrega, 2);

  perform set_config('eafmenu.via_desconto_manual', 'true', true);

  update public.pedidos
  set desconto_tipo = p_tipo,
      desconto_valor_informado = round(p_valor, 2),
      desconto_manual = v_desconto_calculado,
      desconto_motivo = v_motivo,
      desconto_aplicado_por = v_uid,
      desconto_autorizado_por = p_autorizado_por,
      total = v_total_final
  where id = p_pedido_id;

  return query
  select p.id, p.subtotal, p.desconto_tipo, p.desconto_valor_informado, p.desconto_manual,
         p.taxa_entrega, p.total, p.desconto_motivo, p.desconto_aplicado_por, p.desconto_autorizado_por
  from public.pedidos p where p.id = p_pedido_id;
end;
$function$;

-- =========================================================
-- 7. GRANTS DA RPC
-- =========================================================
REVOKE ALL ON FUNCTION public.aplicar_desconto_manual(uuid, text, numeric, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aplicar_desconto_manual(uuid, text, numeric, text, uuid) TO authenticated;
