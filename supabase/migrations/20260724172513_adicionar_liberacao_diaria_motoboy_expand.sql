
-- ===================== COLUNAS =====================

ALTER TABLE public.motoboys
  ADD COLUMN liberado_em timestamptz NULL,
  ADD COLUMN liberado_por uuid NULL REFERENCES public.usuarios(id) ON DELETE SET NULL;

-- ===================== CONSTRAINT =====================

ALTER TABLE public.motoboys
  ADD CONSTRAINT motoboys_liberacao_consistente
  CHECK (
    liberado_por IS NULL
    OR liberado_em IS NOT NULL
  );

-- ===================== COMENTARIOS =====================

COMMENT ON COLUMN public.motoboys.liberado_em IS
  'Timestamp da liberação diária do motoboy pelo restaurante (dono/gerente). Expira automaticamente no início do próximo dia comercial (07:00 America/Sao_Paulo) — sem cron; validade recalculada a cada leitura via public.motoboy_esta_liberado_hoje(). NULL = não liberado hoje. Alterar somente via RPC definir_liberacao_diaria_motoboy(). Independente de usuarios.ativo, motoboys.disponivel e restaurantes.roteirizacao_motoboy_ativa. Determina sozinho a validade diária, mesmo que liberado_por tenha sido apagado.';

COMMENT ON COLUMN public.motoboys.liberado_por IS
  'Usuário (dono/gerente) que concedeu a liberação diária mais recente. Pode ficar NULL caso o usuário responsável pela liberação seja posteriormente removido (ON DELETE SET NULL) — isso não invalida a liberação em si, pois quem determina a validade diária é liberado_em. NULL também quando não há liberação ativa. Preenchido apenas pela RPC definir_liberacao_diaria_motoboy().';

-- ===================== FUNCAO DE VALIDADE =====================

CREATE OR REPLACE FUNCTION public.motoboy_esta_liberado_hoje()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_role public.user_role;
  v_ativo boolean;
  v_liberado_em timestamptz;
  v_inicio_dia_comercial timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  SELECT u.role, u.ativo INTO v_role, v_ativo
  FROM public.usuarios AS u
  WHERE u.id = auth.uid();

  IF NOT FOUND OR v_ativo IS NOT TRUE THEN
    RETURN false;
  END IF;

  IF v_role IS DISTINCT FROM 'motoboy'::public.user_role THEN
    RETURN false;
  END IF;

  SELECT m.liberado_em INTO v_liberado_em
  FROM public.motoboys AS m
  WHERE m.id = auth.uid();

  IF v_liberado_em IS NULL THEN
    RETURN false;
  END IF;

  v_inicio_dia_comercial := (
    CASE
      WHEN extract(hour from (now() AT TIME ZONE 'America/Sao_Paulo')) < 7
        THEN (((now() AT TIME ZONE 'America/Sao_Paulo')::date - 1) + time '07:00')
      ELSE (((now() AT TIME ZONE 'America/Sao_Paulo')::date) + time '07:00')
    END
  ) AT TIME ZONE 'America/Sao_Paulo';

  RETURN v_liberado_em >= v_inicio_dia_comercial;
END;
$function$;

REVOKE ALL ON FUNCTION public.motoboy_esta_liberado_hoje() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.motoboy_esta_liberado_hoje() TO authenticated;

-- ===================== RPC =====================

CREATE OR REPLACE FUNCTION public.definir_liberacao_diaria_motoboy(
  p_motoboy_id uuid,
  p_liberado boolean
)
RETURNS TABLE (liberado_em timestamptz, liberado_por uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_restaurante_id uuid;
  v_caller_role public.user_role;
  v_caller_ativo boolean;
  v_alvo_restaurante_id_usuarios uuid;
  v_alvo_role public.user_role;
  v_alvo_ativo boolean;
  v_alvo_restaurante_id_motoboys uuid;
BEGIN
  IF p_motoboy_id IS NULL THEN
    RAISE EXCEPTION 'Informe o motoboy.';
  END IF;

  IF p_liberado IS NULL THEN
    RAISE EXCEPTION 'A liberação deve ser true ou false.';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado. Faça login antes de alterar a liberação.';
  END IF;

  SELECT u.restaurante_id, u.role, u.ativo
  INTO v_caller_restaurante_id, v_caller_role, v_caller_ativo
  FROM public.usuarios AS u
  WHERE u.id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuário autenticado não encontrado.';
  END IF;

  IF v_caller_ativo IS NOT TRUE THEN
    RAISE EXCEPTION 'Usuário desativado ou inativo.';
  END IF;

  IF v_caller_role IS DISTINCT FROM 'dono'::public.user_role
     AND v_caller_role IS DISTINCT FROM 'gerente'::public.user_role THEN
    RAISE EXCEPTION 'Permissão negada. Apenas dono ou gerente podem liberar motoboys.';
  END IF;

  IF v_caller_restaurante_id IS NULL THEN
    RAISE EXCEPTION 'Você não está associado a nenhum restaurante. Contate o suporte.';
  END IF;

  SELECT u.restaurante_id, u.role, u.ativo, m.restaurante_id
  INTO v_alvo_restaurante_id_usuarios, v_alvo_role, v_alvo_ativo, v_alvo_restaurante_id_motoboys
  FROM public.usuarios AS u
  LEFT JOIN public.motoboys AS m ON m.id = u.id
  WHERE u.id = p_motoboy_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Motoboy não encontrado.';
  END IF;

  IF v_alvo_role IS DISTINCT FROM 'motoboy'::public.user_role THEN
    RAISE EXCEPTION 'O usuário alvo não é um motoboy.';
  END IF;

  IF v_alvo_ativo IS NOT TRUE THEN
    RAISE EXCEPTION 'O motoboy alvo está inativo.';
  END IF;

  IF v_alvo_restaurante_id_motoboys IS NULL THEN
    RAISE EXCEPTION 'Motoboy sem registro correspondente em motoboys. Contate o suporte.';
  END IF;

  IF v_alvo_restaurante_id_usuarios IS DISTINCT FROM v_alvo_restaurante_id_motoboys THEN
    RAISE EXCEPTION 'Inconsistência de dados: o motoboy pertence a restaurantes diferentes em usuarios e motoboys. Contate o suporte.';
  END IF;

  IF v_alvo_restaurante_id_usuarios IS DISTINCT FROM v_caller_restaurante_id THEN
    RAISE EXCEPTION 'Motoboy não pertence ao seu restaurante.';
  END IF;

  IF p_liberado THEN
    UPDATE public.motoboys
    SET liberado_em = now(), liberado_por = auth.uid()
    WHERE id = p_motoboy_id;
  ELSE
    UPDATE public.motoboys
    SET liberado_em = NULL, liberado_por = NULL
    WHERE id = p_motoboy_id;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Registro de motoboy não encontrado. Erro interno.';
  END IF;

  RETURN QUERY
    SELECT m.liberado_em, m.liberado_por
    FROM public.motoboys AS m
    WHERE m.id = p_motoboy_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.definir_liberacao_diaria_motoboy(uuid, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.definir_liberacao_diaria_motoboy(uuid, boolean) TO authenticated;
