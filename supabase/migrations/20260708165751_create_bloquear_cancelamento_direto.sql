create or replace function public.bloquear_cancelamento_direto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelado' and old.status is distinct from 'cancelado' then
    if coalesce(current_setting('eafmenu.via_cancelar_pedido', true), 'false') <> 'true' then
      raise exception 'Cancelamento de pedido só pode ser feito pela função cancelar_pedido().';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_bloquear_cancelamento_direto
before update of status on public.pedidos
for each row
execute function public.bloquear_cancelamento_direto();