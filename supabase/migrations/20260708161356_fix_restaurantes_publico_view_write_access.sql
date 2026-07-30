revoke insert, update, delete on public.restaurantes_publico from anon, authenticated;

alter view public.restaurantes_publico set (security_invoker = true);