create or replace function public.bloquear_edicao_financeira_direta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('eafmenu.via_recalculo_interno', true), 'false') = 'true' then
    return new;
  end if;

  if new.total is distinct from old.total
     or new.subtotal is distinct from old.subtotal
     or new.taxa_entrega is distinct from old.taxa_entrega then
    raise exception 'Total, subtotal e taxa de entrega são calculados pelo sistema e não podem ser editados diretamente.';
  end if;

  return new;
end;
$$;

create trigger trg_bloquear_edicao_financeira_direta
before update of total, subtotal, taxa_entrega on public.pedidos
for each row
execute function public.bloquear_edicao_financeira_direta();