
-- =========================================================
-- Desliga de vez o motor antigo de campanha (condição + benefício
-- simples), totalmente substituído pelo modelo de promoção por etapas
-- (promocao_etapas / promocao_etapa_itens / adicionar_pacote_promocao_pedido).
--
-- 1) bloquear_avanco_pedido_precificacao_pendente() / trigger
--    trg_bloquear_avanco_pedido_precificacao_pendente (BEFORE UPDATE OF
--    status, pago ON pedidos): a migration 20260721220630 acoplou nessa
--    função, além da checagem de sabores pendentes (que continua usada),
--    uma checagem de consistência do motor antigo de campanha
--    (_calcular_melhor_campanha_pedido + snapshot em pedido_promocoes).
--    Essa checagem pressupõe "uma única melhor campanha por pedido" — um
--    invariante que não existe mais no modelo por etapas, onde um pedido
--    pode ter vários pacotes de promoções diferentes ao mesmo tempo (cada
--    um com seu próprio desconto_campanha_* setado por
--    adicionar_pacote_promocao_pedido()). É essa checagem obsoleta que
--    dispara "Pedido % está com o cálculo de campanhas desatualizado ou
--    inconsistente..." e trava a tela de pedidos. A checagem de sabores é
--    mantida (hoje redundante com _validar_integridade_pedido_operacional
--    da máquina de estados, mas inofensiva e não é o que foi pedido para
--    remover).
--
-- 2) trg_recalcular_campanha_pedido (AFTER INSERT OR DELETE OR UPDATE OF
--    quantidade, produto_id, opcao_tamanho_id, preco_unitario,
--    preco_efetivo_unitario, precificacao_finalizada_em ON itens_pedido):
--    também é só o motor antigo — a cada alteração de item ele recalculava
--    e sobrescrevia desconto_campanha_* usando o mesmo cálculo de "melhor
--    campanha única", inclusive nos itens que adicionar_pacote_promocao_pedido()
--    acabara de inserir para um pacote de promoção por etapas. Isso é o que
--    deixou o pedido #1 (0861e32a-5122-4b85-b440-27153edc71ed) com
--    desconto_campanha em itens de pacotes diferentes e nenhum snapshot em
--    pedido_promocoes: o gatilho ficava resetando tudo e reaplicando um
--    "vencedor" a cada item novo inserido. Confirmado que nenhuma outra
--    função/tela depende dele: _calcular_melhor_campanha_pedido e
--    _aplicar_melhor_campanha_pedido só eram chamadas por esses dois
--    gatilhos (grep no schema e no frontend), então pode ser desligado.
-- =========================================================

DROP TRIGGER IF EXISTS trg_recalcular_campanha_pedido ON public.itens_pedido;

COMMENT ON FUNCTION public._calcular_melhor_campanha_pedido(uuid) IS
  'DEPRECATED (2026-08-08): motor antigo de campanha (condição + benefício simples). Substituído pelo modelo de promoção por etapas. Sem chamadores ativos.';
COMMENT ON FUNCTION public._aplicar_melhor_campanha_pedido(uuid) IS
  'DEPRECATED (2026-08-08): motor antigo de campanha (condição + benefício simples). Substituído pelo modelo de promoção por etapas. Sem chamadores ativos.';

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
