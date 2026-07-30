
-- 1. Colunas
ALTER TABLE public.pedidos
  ADD COLUMN previsao_inicio timestamptz,
  ADD COLUMN previsao_fim timestamptz;

-- 2. Constraints
ALTER TABLE public.pedidos
  ADD CONSTRAINT chk_previsao_par_completo
    CHECK (
      (previsao_inicio IS NULL AND previsao_fim IS NULL)
      OR (previsao_inicio IS NOT NULL AND previsao_fim IS NOT NULL)
    );

ALTER TABLE public.pedidos
  ADD CONSTRAINT chk_previsao_ordem_valida
    CHECK (
      previsao_inicio IS NULL
      OR previsao_fim IS NULL
      OR previsao_fim >= previsao_inicio
    );

-- 3. Função principal: calcula e grava aceito_em/previsao na primeira transição para 'aceito'
CREATE OR REPLACE FUNCTION public.definir_previsao_pedido_ao_aceitar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_agora timestamptz;
  v_prazo_min integer;
  v_prazo_max integer;
  v_primeira_aceitacao boolean;
begin
  if tg_op = 'INSERT' then
    v_primeira_aceitacao := (new.status = 'aceito');
  else
    v_primeira_aceitacao := (new.status = 'aceito' and old.status is distinct from 'aceito');
  end if;

  if not v_primeira_aceitacao then
    if tg_op = 'INSERT' then
      -- Impede que um INSERT com status diferente de 'aceito' já chegue com previsão forjada
      new.previsao_inicio := null;
      new.previsao_fim := null;
    end if;
    return new;
  end if;

  v_agora := now();

  -- Nunca confiar em aceito_em vindo do frontend/cliente
  new.aceito_em := v_agora;

  if new.tipo = 'entrega' then
    select r.prazo_entrega_min_minutos, r.prazo_entrega_max_minutos
      into v_prazo_min, v_prazo_max
      from public.restaurantes r
     where r.id = new.restaurante_id;

    if v_prazo_min is not null and v_prazo_max is not null then
      new.previsao_inicio := v_agora + make_interval(mins => v_prazo_min);
      new.previsao_fim := v_agora + make_interval(mins => v_prazo_max);
    else
      new.previsao_inicio := null;
      new.previsao_fim := null;
    end if;
  else
    -- retirada: nesta fase, sem cálculo de previsão (F03.03)
    new.previsao_inicio := null;
    new.previsao_fim := null;
  end if;

  return new;
end;
$function$;

REVOKE EXECUTE ON FUNCTION public.definir_previsao_pedido_ao_aceitar() FROM public, anon, authenticated;

-- 4. Triggers de definição (insert + transição de status)
CREATE TRIGGER trg_definir_previsao_pedido_insert
  BEFORE INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.definir_previsao_pedido_ao_aceitar();

CREATE TRIGGER trg_definir_previsao_pedido_update
  BEFORE UPDATE OF status ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.definir_previsao_pedido_ao_aceitar();

-- 5. Bloqueio de edição direta de previsao_inicio/previsao_fim
CREATE OR REPLACE FUNCTION public.bloquear_edicao_previsao_direta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  raise exception 'previsao_inicio e previsao_fim sao calculados automaticamente pelo sistema no aceite do pedido e nao podem ser editados diretamente.';
end;
$function$;

REVOKE EXECUTE ON FUNCTION public.bloquear_edicao_previsao_direta() FROM public, anon, authenticated;

CREATE TRIGGER trg_bloquear_edicao_previsao_direta
  BEFORE UPDATE OF previsao_inicio, previsao_fim ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.bloquear_edicao_previsao_direta();
