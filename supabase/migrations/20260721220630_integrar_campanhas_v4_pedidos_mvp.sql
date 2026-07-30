
-- =========================================================
-- 1. SCHEMA
-- =========================================================
ALTER TABLE promocoes
  ADD COLUMN periodo_inicio  timestamptz NULL,
  ADD COLUMN periodo_fim     timestamptz NULL,
  ADD COLUMN dias_semana     smallint[]  NULL,
  ADD COLUMN horario_inicio  time        NULL,
  ADD COLUMN horario_fim     time        NULL;

ALTER TABLE promocoes ADD CONSTRAINT chk_promo_periodo
  CHECK (periodo_fim IS NULL OR periodo_inicio IS NULL OR periodo_fim > periodo_inicio);
ALTER TABLE promocoes ADD CONSTRAINT chk_promo_dias_semana
  CHECK (dias_semana IS NULL OR dias_semana <@ ARRAY[0,1,2,3,4,5,6]::smallint[]);
ALTER TABLE promocoes ADD CONSTRAINT chk_promo_horario_par
  CHECK ((horario_inicio IS NULL) = (horario_fim IS NULL));

ALTER TABLE itens_pedido
  ADD COLUMN desconto_campanha_unitario numeric NOT NULL DEFAULT 0,
  ADD COLUMN desconto_campanha_total    numeric NOT NULL DEFAULT 0,
  ADD COLUMN quantidade_beneficiada_campanha smallint NOT NULL DEFAULT 0,
  ADD COLUMN promocao_id_aplicada       uuid    NULL REFERENCES promocoes(id);

ALTER TABLE itens_pedido ADD CONSTRAINT chk_qtd_beneficiada_campanha
  CHECK (quantidade_beneficiada_campanha >= 0);

ALTER TABLE pedidos ADD COLUMN desconto_campanha numeric NOT NULL DEFAULT 0;

ALTER TABLE pedidos DROP CONSTRAINT chk_subtotal_bruto_consistente;
ALTER TABLE pedidos ADD CONSTRAINT chk_subtotal_bruto_consistente
  CHECK (round(subtotal_bruto - desconto_promocional - desconto_campanha, 2) = subtotal);

CREATE TABLE pedido_promocoes (
  pedido_id                     uuid PRIMARY KEY REFERENCES pedidos(id) ON DELETE CASCADE,
  restaurante_id                uuid NOT NULL REFERENCES restaurantes(id),
  promocao_id                   uuid NOT NULL REFERENCES promocoes(id),
  nome_snapshot                 text NOT NULL,
  condicao_quantidade_snapshot  integer NOT NULL,
  beneficio_quantidade_snapshot integer NOT NULL,
  beneficio_percentual_snapshot numeric NOT NULL,
  beneficio_modo_snapshot       text NOT NULL,
  desconto_total                numeric NOT NULL,
  calculado_em                  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE pedido_promocoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY sel_pedido_promocoes_staff ON pedido_promocoes FOR SELECT
  USING (restaurante_id = auth_restaurante_id() AND auth_role() <> 'motoboy');
CREATE POLICY sel_pedido_promocoes_cliente ON pedido_promocoes FOR SELECT
  USING (pedido_id IN (SELECT p.id FROM pedidos p JOIN clientes c ON c.id = p.cliente_id WHERE c.auth_user_id = auth.uid()));
REVOKE INSERT, UPDATE, DELETE ON pedido_promocoes FROM anon, authenticated;
GRANT SELECT ON pedido_promocoes TO anon, authenticated;

-- =========================================================
-- 2. FUNÇÕES
-- =========================================================
CREATE OR REPLACE FUNCTION public._calcular_melhor_campanha_pedido(p_pedido_id uuid)
RETURNS TABLE (
  promocao_id uuid, nome text, condicao_quantidade integer, beneficio_quantidade integer,
  beneficio_percentual numeric, beneficio_modo text, desconto_total numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_restaurante_id uuid;
  v_agora_sp timestamp;
  v_hora_sp time;
  v_dia_hoje smallint;
  v_dia_ontem smallint;
  v_promo record;
  v_melhor_desconto numeric := 0;
  v_melhor record;
  v_melhor_encontrada boolean := false;
BEGIN
  SELECT p.restaurante_id INTO v_restaurante_id FROM pedidos p WHERE p.id = p_pedido_id;
  IF v_restaurante_id IS NULL THEN RETURN; END IF;

  v_agora_sp := (now() AT TIME ZONE 'America/Sao_Paulo');
  v_hora_sp  := v_agora_sp::time;
  v_dia_hoje := extract(dow from v_agora_sp)::smallint;
  v_dia_ontem := (v_dia_hoje + 6) % 7;

  FOR v_promo IN
    SELECT pr.* FROM promocoes pr
    WHERE pr.restaurante_id = v_restaurante_id
      AND pr.ativo = true
      AND pr.arquivado_em IS NULL
      AND pr.beneficio_modo <> 'escolha_cliente'
      AND (pr.periodo_inicio IS NULL OR now() >= pr.periodo_inicio)
      AND (pr.periodo_fim    IS NULL OR now() <= pr.periodo_fim)
      AND (
        ((pr.dias_semana IS NULL OR v_dia_hoje = ANY(pr.dias_semana)) AND (
          pr.horario_inicio IS NULL OR
          CASE WHEN pr.horario_fim <= pr.horario_inicio
               THEN v_hora_sp >= pr.horario_inicio
               ELSE v_hora_sp >= pr.horario_inicio AND v_hora_sp < pr.horario_fim
          END
        ))
        OR
        (pr.horario_fim IS NOT NULL AND pr.horario_fim <= pr.horario_inicio
         AND (pr.dias_semana IS NULL OR v_dia_ontem = ANY(pr.dias_semana))
         AND v_hora_sp < pr.horario_fim)
      )
    ORDER BY pr.criado_em ASC, pr.id ASC
  LOOP
    DECLARE
      v_escopo_cond  promocao_escopos%rowtype;
      v_escopo_benef promocao_escopos%rowtype;
      v_qtd_condicao numeric;
      v_restante     int;
      v_desconto     numeric := 0;
      v_item         record;
      v_qtd_aplicada numeric;
    BEGIN
      SELECT es.* INTO v_escopo_cond  FROM promocao_escopos es WHERE es.promocao_id = v_promo.id AND es.papel = 'condicao';
      SELECT es.* INTO v_escopo_benef FROM promocao_escopos es WHERE es.promocao_id = v_promo.id AND es.papel = 'beneficio';
      IF v_escopo_cond.id IS NULL OR v_escopo_benef.id IS NULL THEN CONTINUE; END IF;

      SELECT COALESCE(SUM(ip.quantidade), 0) INTO v_qtd_condicao
      FROM itens_pedido ip JOIN produtos pd ON pd.id = ip.produto_id
      WHERE ip.pedido_id = p_pedido_id AND ip.precificacao_finalizada_em IS NOT NULL
        AND EXISTS (SELECT 1 FROM promocao_escopo_itens pei
                    WHERE pei.promocao_escopo_id = v_escopo_cond.id
                      AND ((pei.produto_id = ip.produto_id AND (pei.opcao_tamanho_id IS NULL OR pei.opcao_tamanho_id = ip.opcao_tamanho_id))
                           OR (pei.categoria_id = pd.categoria_id)));

      IF v_qtd_condicao < v_promo.condicao_quantidade THEN CONTINUE; END IF;

      v_restante := v_promo.beneficio_quantidade;
      FOR v_item IN
        SELECT ip.id, ip.quantidade, ip.preco_efetivo_unitario
        FROM itens_pedido ip JOIN produtos pd ON pd.id = ip.produto_id
        WHERE ip.pedido_id = p_pedido_id AND ip.precificacao_finalizada_em IS NOT NULL
          AND EXISTS (SELECT 1 FROM promocao_escopo_itens pei
                      WHERE pei.promocao_escopo_id = v_escopo_benef.id
                        AND ((pei.produto_id = ip.produto_id AND (pei.opcao_tamanho_id IS NULL OR pei.opcao_tamanho_id = ip.opcao_tamanho_id))
                             OR (pei.categoria_id = pd.categoria_id)))
        ORDER BY CASE WHEN v_promo.beneficio_modo = 'produto_fixo' THEN 0 ELSE ip.preco_efetivo_unitario END ASC, ip.id ASC
      LOOP
        EXIT WHEN v_restante <= 0;
        v_qtd_aplicada := LEAST(v_item.quantidade, v_restante);
        v_desconto := v_desconto + round(v_item.preco_efetivo_unitario * v_promo.beneficio_percentual / 100, 2) * v_qtd_aplicada;
        v_restante := v_restante - v_qtd_aplicada;
      END LOOP;

      IF v_desconto > 0 AND v_desconto > v_melhor_desconto THEN
        v_melhor_desconto := v_desconto;
        v_melhor := v_promo;
        v_melhor_encontrada := true;
      END IF;
    END;
  END LOOP;

  IF NOT v_melhor_encontrada THEN RETURN; END IF;

  RETURN QUERY SELECT v_melhor.id, v_melhor.nome, v_melhor.condicao_quantidade, v_melhor.beneficio_quantidade,
                      v_melhor.beneficio_percentual, v_melhor.beneficio_modo, v_melhor_desconto;
END;
$$;
REVOKE ALL ON FUNCTION public._calcular_melhor_campanha_pedido(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._aplicar_melhor_campanha_pedido(p_pedido_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_restaurante_id uuid;
  v_melhor record;
  v_encontrou boolean := false;
  v_restante int;
  v_item record;
  v_qtd_aplicada numeric;
  v_desc_unit numeric;
  v_desc_tot numeric;
BEGIN
  SELECT restaurante_id INTO v_restaurante_id FROM pedidos WHERE id = p_pedido_id;
  IF v_restaurante_id IS NULL THEN RETURN; END IF;

  UPDATE itens_pedido
     SET desconto_campanha_unitario = 0, desconto_campanha_total = 0,
         quantidade_beneficiada_campanha = 0, promocao_id_aplicada = NULL
   WHERE pedido_id = p_pedido_id
     AND (desconto_campanha_unitario <> 0 OR desconto_campanha_total <> 0
          OR quantidade_beneficiada_campanha <> 0 OR promocao_id_aplicada IS NOT NULL);

  SELECT * INTO v_melhor FROM _calcular_melhor_campanha_pedido(p_pedido_id);
  v_encontrou := (v_melhor IS NOT NULL) AND (v_melhor.promocao_id IS NOT NULL);

  IF NOT v_encontrou THEN
    DELETE FROM pedido_promocoes WHERE pedido_id = p_pedido_id;
    RETURN;
  END IF;

  v_restante := v_melhor.beneficio_quantidade;
  FOR v_item IN
    SELECT ip.id, ip.quantidade, ip.preco_efetivo_unitario
    FROM itens_pedido ip
    JOIN produtos pd ON pd.id = ip.produto_id
    JOIN promocao_escopos pe ON pe.promocao_id = v_melhor.promocao_id AND pe.papel = 'beneficio'
    WHERE ip.pedido_id = p_pedido_id AND ip.precificacao_finalizada_em IS NOT NULL
      AND EXISTS (SELECT 1 FROM promocao_escopo_itens pei
                  WHERE pei.promocao_escopo_id = pe.id
                    AND ((pei.produto_id = ip.produto_id AND (pei.opcao_tamanho_id IS NULL OR pei.opcao_tamanho_id = ip.opcao_tamanho_id))
                         OR (pei.categoria_id = pd.categoria_id)))
    ORDER BY CASE WHEN v_melhor.beneficio_modo = 'produto_fixo' THEN 0 ELSE ip.preco_efetivo_unitario END ASC, ip.id ASC
  LOOP
    EXIT WHEN v_restante <= 0;
    v_qtd_aplicada := LEAST(v_item.quantidade, v_restante);
    v_desc_unit := round(v_item.preco_efetivo_unitario * v_melhor.beneficio_percentual / 100, 2);
    v_desc_tot  := round(v_desc_unit * v_qtd_aplicada, 2);
    UPDATE itens_pedido
       SET desconto_campanha_unitario = v_desc_unit,
           desconto_campanha_total = v_desc_tot,
           quantidade_beneficiada_campanha = v_qtd_aplicada,
           promocao_id_aplicada = v_melhor.promocao_id
     WHERE id = v_item.id;
    v_restante := v_restante - v_qtd_aplicada;
  END LOOP;

  INSERT INTO pedido_promocoes (pedido_id, restaurante_id, promocao_id, nome_snapshot,
         condicao_quantidade_snapshot, beneficio_quantidade_snapshot, beneficio_percentual_snapshot,
         beneficio_modo_snapshot, desconto_total)
  VALUES (p_pedido_id, v_restaurante_id, v_melhor.promocao_id, v_melhor.nome,
          v_melhor.condicao_quantidade, v_melhor.beneficio_quantidade, v_melhor.beneficio_percentual,
          v_melhor.beneficio_modo, v_melhor.desconto_total)
  ON CONFLICT (pedido_id) DO UPDATE SET
    promocao_id = excluded.promocao_id, nome_snapshot = excluded.nome_snapshot,
    condicao_quantidade_snapshot = excluded.condicao_quantidade_snapshot,
    beneficio_quantidade_snapshot = excluded.beneficio_quantidade_snapshot,
    beneficio_percentual_snapshot = excluded.beneficio_percentual_snapshot,
    beneficio_modo_snapshot = excluded.beneficio_modo_snapshot,
    desconto_total = excluded.desconto_total,
    calculado_em = now();
END;
$$;
REVOKE ALL ON FUNCTION public._aplicar_melhor_campanha_pedido(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_recalcular_campanha_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM _aplicar_melhor_campanha_pedido(COALESCE(new.pedido_id, old.pedido_id));
  RETURN COALESCE(new, old);
END;
$$;

DROP TRIGGER IF EXISTS trg_recalcular_campanha_pedido ON public.itens_pedido;
CREATE TRIGGER trg_recalcular_campanha_pedido
AFTER INSERT OR DELETE OR UPDATE OF
  quantidade, produto_id, opcao_tamanho_id, preco_unitario, preco_efetivo_unitario, precificacao_finalizada_em
ON public.itens_pedido
FOR EACH ROW EXECUTE FUNCTION trg_recalcular_campanha_pedido();

CREATE OR REPLACE FUNCTION public.recalcular_totais_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_pedido_id uuid;
  v_subtotal_bruto numeric;
  v_subtotal numeric;
  v_desconto_promocional numeric;
  v_desconto_campanha numeric;
  v_taxa numeric;
  v_desconto_manual numeric;
BEGIN
  v_pedido_id := coalesce(new.pedido_id, old.pedido_id);

  SELECT
    coalesce(sum(quantidade * preco_original_unitario), 0),
    coalesce(sum(quantidade * preco_efetivo_unitario), 0),
    coalesce(sum(desconto_promocional_total), 0),
    coalesce(sum(desconto_campanha_total), 0)
    INTO v_subtotal_bruto, v_subtotal, v_desconto_promocional, v_desconto_campanha
  FROM itens_pedido WHERE pedido_id = v_pedido_id;

  v_subtotal := v_subtotal - v_desconto_campanha;

  SELECT taxa_entrega, desconto_manual INTO v_taxa, v_desconto_manual
  FROM pedidos WHERE id = v_pedido_id;

  PERFORM set_config('eafmenu.via_recalculo_interno', 'true', true);

  UPDATE pedidos
     SET subtotal_bruto = round(v_subtotal_bruto, 2),
         desconto_promocional = round(v_desconto_promocional, 2),
         desconto_campanha = round(v_desconto_campanha, 2),
         subtotal = round(v_subtotal, 2),
         total = round(GREATEST(v_subtotal - coalesce(v_desconto_manual, 0) + coalesce(v_taxa, 0), 0), 2)
   WHERE id = v_pedido_id;

  RETURN coalesce(new, old);
END;
$$;

DROP TRIGGER IF EXISTS trg_bloquear_edicao_financeira_direta ON public.pedidos;
CREATE TRIGGER trg_bloquear_edicao_financeira_direta
BEFORE UPDATE OF
  total, subtotal, subtotal_bruto, desconto_promocional, desconto_campanha, taxa_entrega,
  desconto_tipo, desconto_valor_informado, desconto_manual, desconto_motivo,
  desconto_aplicado_por, desconto_autorizado_por
ON public.pedidos
FOR EACH ROW EXECUTE FUNCTION public.bloquear_edicao_financeira_direta();

CREATE OR REPLACE FUNCTION public.bloquear_avanco_pedido_precificacao_pendente()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_calc record;
  v_tem_calc boolean;
  v_snapshot record;
  v_tem_snapshot boolean;
  v_soma_itens numeric;
  v_qtd_outra_promo int;
  v_qtd_com_promo int;
  v_qtd_inconsistente_item int;
  v_consistente boolean := true;
BEGIN
  IF (new.pago = true AND coalesce(old.pago, false) = false)
     OR (new.status IN ('em_preparo','saiu_para_entrega','entregue','retirado')
         AND new.status IS DISTINCT FROM old.status)
  THEN
    IF EXISTS (
      SELECT 1 FROM itens_pedido
      WHERE pedido_id = new.id
        AND coalesce(sabores_esperados, 1) > 1
        AND precificacao_finalizada_em IS NULL
    ) THEN
      RAISE EXCEPTION 'Pedido % possui item com precificação de sabores pendente. Não pode ser pago nem avançar de status.', new.id;
    END IF;

    SELECT * INTO v_calc FROM _calcular_melhor_campanha_pedido(new.id);
    v_tem_calc := (v_calc IS NOT NULL) AND (v_calc.promocao_id IS NOT NULL);

    SELECT * INTO v_snapshot FROM pedido_promocoes WHERE pedido_id = new.id;
    v_tem_snapshot := (v_snapshot IS NOT NULL) AND (v_snapshot.pedido_id IS NOT NULL);

    SELECT coalesce(sum(desconto_campanha_total), 0) INTO v_soma_itens
    FROM itens_pedido WHERE pedido_id = new.id;

    SELECT
      count(*) FILTER (WHERE promocao_id_aplicada IS NOT NULL AND (NOT v_tem_calc OR promocao_id_aplicada IS DISTINCT FROM v_calc.promocao_id)),
      count(*) FILTER (WHERE promocao_id_aplicada IS NOT NULL)
      INTO v_qtd_outra_promo, v_qtd_com_promo
    FROM itens_pedido WHERE pedido_id = new.id;

    SELECT count(*) INTO v_qtd_inconsistente_item
    FROM itens_pedido
    WHERE pedido_id = new.id
      AND (
        (promocao_id_aplicada IS NOT NULL AND quantidade_beneficiada_campanha <= 0)
        OR (quantidade_beneficiada_campanha > 0 AND promocao_id_aplicada IS NULL)
        OR (quantidade_beneficiada_campanha > quantidade)
        OR (promocao_id_aplicada IS NOT NULL
            AND round(desconto_campanha_unitario * quantidade_beneficiada_campanha, 2) IS DISTINCT FROM round(desconto_campanha_total, 2))
      );

    IF v_qtd_inconsistente_item > 0 THEN
      v_consistente := false;
    ELSIF NOT v_tem_calc THEN
      IF new.desconto_campanha IS DISTINCT FROM 0
         OR v_tem_snapshot
         OR round(v_soma_itens, 2) IS DISTINCT FROM 0
         OR v_qtd_com_promo > 0
      THEN
        v_consistente := false;
      END IF;
    ELSE
      IF round(new.desconto_campanha, 2) IS DISTINCT FROM round(v_calc.desconto_total, 2)
         OR NOT v_tem_snapshot
         OR (v_tem_snapshot AND v_snapshot.promocao_id IS DISTINCT FROM v_calc.promocao_id)
         OR (v_tem_snapshot AND round(v_snapshot.desconto_total, 2) IS DISTINCT FROM round(v_calc.desconto_total, 2))
         OR round(v_soma_itens, 2) IS DISTINCT FROM round(v_calc.desconto_total, 2)
         OR v_qtd_outra_promo > 0
         OR v_qtd_com_promo = 0
      THEN
        v_consistente := false;
      END IF;
    END IF;

    IF NOT v_consistente THEN
      RAISE EXCEPTION 'Pedido % está com o cálculo de campanhas desatualizado ou inconsistente. Ajuste os itens do pedido para forçar o recálculo antes de pagar/avançar.', new.id;
    END IF;
  END IF;

  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.ativar_promocao(p_promocao_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_promo promocoes%rowtype;
  v_chamador usuarios%rowtype;
  v_esc_cond promocao_escopos%rowtype;
  v_esc_ben promocao_escopos%rowtype;
  v_item_ben promocao_escopo_itens%rowtype;
  v_qtd_combinacoes_validas int;
begin
  select * into v_chamador from usuarios where id = auth.uid();
  if not found or v_chamador.role not in ('dono','gerente') then raise exception 'Sem permissao para ativar campanha.'; end if;

  select * into v_promo from promocoes where id = p_promocao_id for update;
  if not found or v_promo.restaurante_id <> v_chamador.restaurante_id then raise exception 'Campanha nao encontrada neste restaurante.'; end if;
  if v_promo.arquivado_em is not null then raise exception 'Campanha arquivada nao pode ser ativada.'; end if;

  if v_promo.beneficio_modo = 'escolha_cliente' then
    raise exception 'Promocoes com escolha do cliente ainda nao estao disponiveis no checkout.';
  end if;

  select * into v_esc_cond from promocao_escopos where promocao_id = p_promocao_id and papel = 'condicao';
  select * into v_esc_ben from promocao_escopos where promocao_id = p_promocao_id and papel = 'beneficio';
  if v_esc_cond.id is null or v_esc_ben.id is null then raise exception 'Campanha precisa de escopo de condicao e de beneficio definidos.'; end if;

  perform _validar_escopo_generico(v_esc_cond.id, v_esc_cond.tipo, v_promo.restaurante_id);
  perform _validar_escopo_generico(v_esc_ben.id, v_esc_ben.tipo, v_promo.restaurante_id);

  if v_promo.beneficio_modo = 'produto_fixo' and v_esc_ben.tipo <> 'produto' then raise exception 'produto_fixo exige escopo de beneficio do tipo produto unico.'; end if;
  if v_promo.beneficio_modo = 'escolha_cliente' and v_esc_ben.tipo = 'produto' then raise exception 'escolha_cliente exige escopo de beneficio do tipo lista_produtos ou categoria, nao produto unico.'; end if;

  if v_promo.beneficio_modo = 'produto_fixo' then
    select * into v_item_ben from promocao_escopo_itens where promocao_escopo_id = v_esc_ben.id;
    if v_item_ben.opcao_tamanho_id is null then
      select count(*) into v_qtd_combinacoes_validas from _opcoes_tamanho_validas_produto(v_item_ben.produto_id, v_promo.restaurante_id);
      if v_qtd_combinacoes_validas = 0 then raise exception 'Produto de beneficio fixo nao possui combinacao de tamanho/preco valida.'; end if;
      if v_qtd_combinacoes_validas > 1 then raise exception 'Produto de beneficio fixo tem mais de uma combinacao de tamanho valida; escolha o tamanho no cadastro do escopo antes de ativar.'; end if;
    end if;
  end if;

  if v_promo.beneficio_modo = 'menor_preco_elegivel' then
    if v_esc_ben.tipo = 'produto' then
      select * into v_item_ben from promocao_escopo_itens where promocao_escopo_id = v_esc_ben.id;
      if not _produto_tamanho_no_escopo(v_item_ben.produto_id, v_item_ben.opcao_tamanho_id, v_esc_cond.id, v_esc_cond.tipo) then
        raise exception 'menor_preco_elegivel: o produto/tamanho do beneficio precisa estar contido no escopo da condicao.'; end if;
    elsif v_esc_ben.tipo = 'lista_produtos' then
      if exists (select 1 from promocao_escopo_itens ben where ben.promocao_escopo_id = v_esc_ben.id
          and not _produto_tamanho_no_escopo(ben.produto_id, ben.opcao_tamanho_id, v_esc_cond.id, v_esc_cond.tipo)) then
        raise exception 'menor_preco_elegivel: todos os produtos/tamanhos do beneficio precisam estar contidos no escopo da condicao.'; end if;
    elsif v_esc_ben.tipo = 'categoria' then
      if v_esc_cond.tipo <> 'categoria' then
        raise exception 'menor_preco_elegivel: beneficio por categoria exige condicao pela mesma categoria (nao e permitido condicao por lista_produtos neste MVP).'; end if;
      if not exists (select 1 from promocao_escopo_itens a join promocao_escopo_itens b on b.categoria_id = a.categoria_id
          where a.promocao_escopo_id = v_esc_ben.id and b.promocao_escopo_id = v_esc_cond.id) then
        raise exception 'menor_preco_elegivel: categoria do beneficio precisa ser a mesma da condicao.'; end if;
    end if;
  end if;

  perform set_config('eafmenu.via_rpc_gestao_promocao', 'true', true);
  update promocoes set ativo = true where id = p_promocao_id;
end;
$function$;
