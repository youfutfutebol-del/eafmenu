REVOKE ALL ON FUNCTION public.aplicar_desconto_manual(uuid, text, numeric, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aplicar_desconto_manual(uuid, text, numeric, text, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.aplicar_desconto_manual(uuid, text, numeric, text, uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.aplicar_desconto_manual(uuid, text, numeric, text, uuid) TO authenticated;
