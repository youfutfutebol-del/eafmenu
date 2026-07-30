create or replace function public._validar_integridade_pedido_operacional(
 p_id uuid,p_status_atual status_pedido,p_status_novo status_pedido,
 p_bruto numeric,p_v3 numeric,p_v4 numeric,p_subtotal numeric,p_manual numeric,p_taxa numeric,p_total numeric
) returns void language plpgsql security definer set search_path=public as $$
declare q int; pend int; multi int; bruto numeric; efetivo numeric; v3 numeric; v4 numeric; subcalc numeric; totcalc numeric;
begin
 if p_status_atual='cancelado' or p_status_novo='cancelado' then raise exception 'Pedido cancelado não pode ser pago nem avançar.'; end if;
 select count(*),count(*) filter(where precificacao_finalizada_em is null),
 count(*) filter(where coalesce(sabores_esperados,1)>1 and precificacao_finalizada_em is null),
 coalesce(sum(quantidade*preco_original_unitario),0),coalesce(sum(quantidade*preco_efetivo_unitario),0),
 coalesce(sum(desconto_promocional_total),0),coalesce(sum(desconto_campanha_total),0)
 into q,pend,multi,bruto,efetivo,v3,v4 from itens_pedido where pedido_id=p_id;
 if q=0 then raise exception 'Pedido % não possui itens.',p_id; end if;
 if pend>0 then raise exception 'Pedido % possui item com precificação pendente.',p_id; end if;
 if multi>0 then raise exception 'Pedido % possui multissabor pendente.',p_id; end if;
 subcalc:=round(efetivo-v4,2); totcalc:=round(greatest(subcalc-coalesce(p_manual,0)+coalesce(p_taxa,0),0),2);
 if round(coalesce(p_bruto,0),2)<=0 then raise exception 'subtotal_bruto deve ser maior que zero.'; end if;
 if round(coalesce(p_subtotal,0),2)<0 or round(coalesce(p_total,0),2)<0 then raise exception 'Subtotal/total negativo.'; end if;
 if round(p_bruto,2) is distinct from round(bruto,2) or round(p_v3,2) is distinct from round(v3,2)
 or round(p_v4,2) is distinct from round(v4,2) or round(p_subtotal,2) is distinct from subcalc
 or round(p_total,2) is distinct from totcalc then raise exception 'Totais persistidos divergem do cálculo atual.'; end if;
end $$;

revoke all on function public._validar_integridade_pedido_operacional(uuid,status_pedido,status_pedido,numeric,numeric,numeric,numeric,numeric,numeric,numeric) from public,anon,authenticated;
grant execute on function public._validar_integridade_pedido_operacional(uuid,status_pedido,status_pedido,numeric,numeric,numeric,numeric,numeric,numeric,numeric) to service_role;

create or replace function public.trg_validar_integridade_pedido_operacional() returns trigger
language plpgsql security definer set search_path=public as $$
declare atual status_pedido;
begin
 if tg_op='INSERT' then
   if not new.pago then return new; end if; atual:=new.status;
 else
   if not ((new.pago and not coalesce(old.pago,false)) or
      (new.status in ('em_preparo','saiu_para_entrega','entregue','retirado') and new.status is distinct from old.status))
   then return new; end if;
   atual:=old.status;
 end if;
 perform _validar_integridade_pedido_operacional(new.id,atual,new.status,new.subtotal_bruto,new.desconto_promocional,new.desconto_campanha,new.subtotal,new.desconto_manual,new.taxa_entrega,new.total);
 return new;
end $$;

revoke all on function public.trg_validar_integridade_pedido_operacional() from public,anon,authenticated;

drop trigger if exists trg_bloquear_00_integridade_pedido on pedidos;
create trigger trg_bloquear_00_integridade_pedido before insert or update on pedidos
for each row execute function trg_validar_integridade_pedido_operacional();