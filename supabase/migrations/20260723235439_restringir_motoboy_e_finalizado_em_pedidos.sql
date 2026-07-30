
-- ============================================================
-- Migration: restringir_motoboy_e_finalizado_em_pedidos
-- ============================================================

-- PASSO 1: função de restrição do motoboy (campos + regra de pago,
-- com comparação segura contra NULL via IS TRUE / IS NOT TRUE)
CREATE OR REPLACE FUNCTION public.trg_restringir_campos_motoboy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role public.user_role;
  v_new jsonb;
  v_old jsonb;
  v_key text;
  v_esta_finalizando boolean;
BEGIN
  v_role := public.auth_role();
  IF v_role IS DISTINCT FROM 'motoboy'::public.user_role THEN
    RETURN NEW;
  END IF;

  IF OLD.motoboy_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Motoboy só pode atualizar pedidos atribuídos a ele.';
  END IF;

  v_new := to_jsonb(NEW);
  v_old := to_jsonb(OLD);
  FOR v_key IN SELECT jsonb_object_keys(v_old) LOOP
    IF v_key IN ('status', 'pago') THEN
      CONTINUE;
    END IF;
    IF v_new -> v_key IS DISTINCT FROM v_old -> v_key THEN
      RAISE EXCEPTION 'Campo "%" não pode ser alterado pelo motoboy.', v_key
        USING ERRCODE = '42501';
    END IF;
  END LOOP;

  v_esta_finalizando :=
    OLD.status NOT IN ('entregue', 'retirado')
    AND NEW.status IN ('entregue', 'retirado')
    AND OLD.status IS DISTINCT FROM NEW.status;

  IF NEW.pago IS DISTINCT FROM OLD.pago THEN
    IF OLD.pago IS TRUE THEN
      RAISE EXCEPTION 'Motoboy não pode reverter pagamento de um pedido já pago.';
    END IF;
    IF NEW.pago IS NOT TRUE THEN
      RAISE EXCEPTION 'Transição de pagamento inválida para motoboy.';
    END IF;
    IF NOT v_esta_finalizando THEN
      RAISE EXCEPTION 'Motoboy só pode confirmar pagamento junto com a conclusão da entrega/retirada.';
    END IF;
  ELSE
    IF v_esta_finalizando AND OLD.pago IS NOT TRUE THEN
      RAISE EXCEPTION 'Pedido não pago precisa ter pago=true na mesma operação que conclui a entrega/retirada.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_restringir_campos_motoboy() FROM PUBLIC;

-- PASSO 2: trigger de restrição do motoboy (nome garante disparo primeiro)
CREATE TRIGGER trg_000_restringir_campos_motoboy
BEFORE UPDATE ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trg_restringir_campos_motoboy();

-- PASSO 3: backfill confiável de finalizado_em (antes da trigger de controle,
-- para que ela não bloqueie este próprio passo da migration)
UPDATE public.pedidos p
SET finalizado_em = h.criado_em
FROM (
  SELECT DISTINCT ON (pedido_id) pedido_id, criado_em
  FROM public.pedido_status_historico
  WHERE status IN ('entregue', 'retirado')
  ORDER BY pedido_id, criado_em DESC
) h
WHERE p.id = h.pedido_id
  AND p.status IN ('entregue', 'retirado')
  AND p.finalizado_em IS NULL;

-- PASSO 4: função de controle de finalizado_em (bloqueia edição manual
-- em qualquer momento, para qualquer perfil; só o banco define o valor)
CREATE OR REPLACE FUNCTION public.trg_controlar_finalizado_em_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_transicao_para_final boolean;
BEGIN
  v_transicao_para_final :=
    NEW.status IN ('entregue', 'retirado')
    AND OLD.status NOT IN ('entregue', 'retirado')
    AND OLD.status IS DISTINCT FROM NEW.status;

  IF v_transicao_para_final THEN
    IF OLD.finalizado_em IS NOT NULL THEN
      NEW.finalizado_em := OLD.finalizado_em;
    ELSE
      NEW.finalizado_em := now();
    END IF;
  ELSE
    IF NEW.finalizado_em IS DISTINCT FROM OLD.finalizado_em THEN
      RAISE EXCEPTION 'finalizado_em é controlado exclusivamente pelo sistema e não pode ser alterado diretamente.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_controlar_finalizado_em_pedido() FROM PUBLIC;

-- PASSO 5: trigger de controle de finalizado_em
CREATE TRIGGER trg_bloquear_15_controlar_finalizado_em
BEFORE UPDATE OF status, finalizado_em ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trg_controlar_finalizado_em_pedido();

-- PASSO 6: índice parcial para "entregas concluídas hoje" por motoboy
CREATE INDEX IF NOT EXISTS idx_pedidos_motoboy_finalizado_em
ON public.pedidos (motoboy_id, finalizado_em)
WHERE status IN ('entregue', 'retirado') AND finalizado_em IS NOT NULL;
