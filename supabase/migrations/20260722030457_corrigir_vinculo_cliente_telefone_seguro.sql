CREATE OR REPLACE FUNCTION public.criar_ou_atualizar_cliente_sessao_v2(
  p_restaurante_id uuid,
  p_nome text,
  p_telefone text
)
RETURNS TABLE (
  id uuid,
  nome text,
  telefone text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_auth_user_id uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_telefone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_cliente public.clientes%ROWTYPE;
BEGIN
  IF v_auth_user_id IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Sessão inválida.',
      ERRCODE = '28000';
  END IF;

  IF p_restaurante_id IS NULL
     OR v_nome = ''
     OR length(v_telefone) < 10 THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Não foi possível concluir o cadastro com os dados informados.',
      ERRCODE = 'P0001';
  END IF;

  PERFORM 1
  FROM public.restaurantes r
  WHERE r.id = p_restaurante_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Não foi possível concluir o cadastro com os dados informados.',
      ERRCODE = 'P0001';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'cliente-sessao:'
      || p_restaurante_id::text
      || ':'
      || v_auth_user_id::text,
      0
    )
  );

  SELECT c.*
  INTO v_cliente
  FROM public.clientes c
  WHERE c.restaurante_id = p_restaurante_id
    AND c.auth_user_id = v_auth_user_id
  FOR UPDATE;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'cliente-telefone:'
      || p_restaurante_id::text
      || ':'
      || v_telefone,
      0
    )
  );

  IF v_cliente.id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.clientes c
      WHERE c.restaurante_id = p_restaurante_id
        AND c.id <> v_cliente.id
        AND regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g')
            = v_telefone
    ) THEN
      RAISE EXCEPTION USING
        MESSAGE = 'Não foi possível concluir o cadastro com os dados informados.',
        ERRCODE = 'P0001';
    END IF;

    UPDATE public.clientes c
       SET nome = v_nome,
           telefone = v_telefone
     WHERE c.id = v_cliente.id
    RETURNING c.* INTO v_cliente;
  ELSE
    IF EXISTS (
      SELECT 1
      FROM public.clientes c
      WHERE c.restaurante_id = p_restaurante_id
        AND regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g')
            = v_telefone
    ) THEN
      RAISE EXCEPTION USING
        MESSAGE = 'Não foi possível concluir o cadastro com os dados informados.',
        ERRCODE = 'P0001';
    END IF;

    BEGIN
      INSERT INTO public.clientes (
        nome,
        telefone,
        restaurante_id,
        auth_user_id
      )
      VALUES (
        v_nome,
        v_telefone,
        p_restaurante_id,
        v_auth_user_id
      )
      RETURNING * INTO v_cliente;
    EXCEPTION
      WHEN unique_violation THEN
        RAISE EXCEPTION USING
          MESSAGE = 'Não foi possível concluir o cadastro com os dados informados.',
          ERRCODE = 'P0001';
    END;
  END IF;

  RETURN QUERY
  SELECT v_cliente.id, v_cliente.nome, v_cliente.telefone;
END;
$function$;

REVOKE ALL
ON FUNCTION public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.criar_ou_atualizar_cliente_sessao_v2(uuid, text, text)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.vincular_cliente_por_telefone(
  p_restaurante_id uuid,
  p_telefone text,
  p_nome text
)
RETURNS public.clientes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_seguro record;
  v_retorno public.clientes;
BEGIN
  SELECT *
  INTO STRICT v_seguro
  FROM public.criar_ou_atualizar_cliente_sessao_v2(
    p_restaurante_id,
    p_nome,
    p_telefone
  );

  v_retorno := ROW(
    v_seguro.id,
    NULL::uuid,
    NULL::uuid,
    v_seguro.nome,
    v_seguro.telefone,
    NULL::timestamptz
  )::public.clientes;

  RETURN v_retorno;
END;
$function$;

REVOKE ALL
ON FUNCTION public.vincular_cliente_por_telefone(uuid, text, text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.vincular_cliente_por_telefone(uuid, text, text)
TO authenticated, service_role;