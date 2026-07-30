create or replace function public.debug_auth_contexto()
returns table(uid_visto uuid, role_visto text, claims_brutos text, achou_usuario boolean)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
begin
  return query
  select
    auth.uid(),
    current_setting('request.jwt.claim.role', true),
    current_setting('request.jwt.claims', true),
    exists(select 1 from usuarios where id = auth.uid());
end;
$$;
grant execute on function debug_auth_contexto() to authenticated;
