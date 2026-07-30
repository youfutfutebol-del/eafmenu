-- =============================================================================
-- Telefone passa a ser dado de CONTATO, não identidade.
-- Identidade do cliente do cardápio público = (auth_user_id, restaurante_id).
-- Aprovado em cross-review: sem revinculação por telefone (anti-sequestro),
-- duplicidade de telefone entre sessões permitida, nenhum dado alterado.
-- =============================================================================

-- Parte 1: unicidade (restaurante_id, telefone) vira índice de pesquisa
DROP INDEX public.idx_clientes_restaurante_telefone;
CREATE INDEX idx_clientes_restaurante_telefone
  ON public.clientes (restaurante_id, telefone) WHERE telefone IS NOT NULL;
COMMENT ON INDEX public.idx_clientes_restaurante_telefone IS
  'Índice de PESQUISA (não único). Telefone é dado de CONTATO, não identidade. A identidade do cliente é (auth_user_id, restaurante_id).';

-- Parte 2: RPC busca/cria SOMENTE pelo cliente da sessão
CREATE OR REPLACE FUNCTION public.criar_ou_atualizar_cliente_sessao_v2(
  p_restaurante_id uuid, p_nome text, p_telefone text
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_auth_user_id uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_telefone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_cliente public.clientes%ROWTYPE;
BEGIN
  IF v_auth_user_id IS NULL THEN
    RAISE EXCEPTION USING MESSAGE = 'Sessão inválida.', ERRCODE = '28000';
  END IF;

  IF p_restaurante_id IS NULL OR v_nome = '' OR length(v_telefone) < 10 THEN
    RAISE EXCEPTION USING MESSAGE = 'Não foi possível concluir o cadastro com os dados informados.', ERRCODE = 'P0001';
  END IF;

  PERFORM 1 FROM public.restaurantes r WHERE r.id = p_restaurante_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING MESSAGE = 'Não foi possível concluir o cadastro com os dados informados.', ERRCODE = 'P0001';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('cliente-sessao:' || p_restaurante_id::text || ':' || v_auth_user_id::text, 0));

  SELECT c.* INTO v_cliente
  FROM public.clientes c
  WHERE c.restaurante_id = p_restaurante_id AND c.auth_user_id = v_auth_user_id
  FOR UPDATE;

  IF v_cliente.id IS NOT NULL THEN
    UPDATE public.clientes c SET nome = v_nome, telefone = v_telefone
    WHERE c.id = v_cliente.id RETURNING c.* INTO v_cliente;
  ELSE
    BEGIN
      INSERT INTO public.clientes (nome, telefone, restaurante_id, auth_user_id)
      VALUES (v_nome, v_telefone, p_restaurante_id, v_auth_user_id)
      RETURNING * INTO v_cliente;
    EXCEPTION WHEN unique_violation THEN
      -- Corrida no UNIQUE (auth_user_id, restaurante_id): relê o cliente da PRÓPRIA
      -- sessão e devolve sucesso idempotente. Se não existir, preserva o erro original.
      SELECT c.* INTO v_cliente
      FROM public.clientes c
      WHERE c.restaurante_id = p_restaurante_id AND c.auth_user_id = v_auth_user_id
      FOR UPDATE;

      IF v_cliente.id IS NULL THEN
        RAISE;
      END IF;

      UPDATE public.clientes c SET nome = v_nome, telefone = v_telefone
      WHERE c.id = v_cliente.id RETURNING c.* INTO v_cliente;
    END;
  END IF;

  RETURN QUERY SELECT v_cliente.id, v_cliente.nome, v_cliente.telefone;
END;
$function$;

COMMENT ON FUNCTION public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text) IS
  'Identificação do cliente do cardápio público. Busca/cria SOMENTE pelo cliente da sessão (auth_user_id + restaurante_id). Telefone é dado de CONTATO e pode se repetir entre sessões; nunca é usado como credencial nem para vincular/transferir cadastros.';

REVOKE ALL ON FUNCTION public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
TO authenticated, service_role;