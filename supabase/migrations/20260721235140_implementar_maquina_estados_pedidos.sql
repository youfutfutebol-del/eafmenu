create or replace function public._validar_transicao_status_pedido(
  p_pedido_id uuid,
  p_restaurante_id uuid,
  p_cliente_id uuid,
  p_status_atual public.status_pedido,
  p_status_novo public.status_pedido,
  p_tipo public.tipo_pedido,
  p_endereco_entrega_id uuid,
  p_endereco_id uuid,
  p_motoboy_id uuid,
  p_taxa_entrega numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_endereco_id uuid := coalesce(p_endereco_entrega_id, p_endereco_id);
  v_qtd_itens integer;
  v_qtd_pendentes integer;
begin
  if p_status_atual is not distinct from p_status_novo then
    return;
  end if;

  if p_status_novo = 'cancelado' then
    if coalesce(current_setting('eafmenu.via_cancelar_pedido', true), 'false') = 'true' then
      return;
    end if;
    raise exception 'Cancelamento só pode ser feito por cancelar_pedido().';
  end if;

  if p_status_atual = 'cancelado' then
    raise exception 'Pedido cancelado não pode mudar de status.';
  end if;

  if not (
    (p_status_atual = 'recebido' and p_status_novo = 'aceito')
    or (p_status_atual = 'aceito' and p_status_novo = 'em_preparo')
    or (p_tipo = 'entrega' and p_status_atual = 'em_preparo' and p_status_novo = 'saiu_para_entrega')
    or (p_tipo = 'entrega' and p_status_atual = 'saiu_para_entrega' and p_status_novo = 'entregue')
    or (p_tipo = 'retirada' and p_status_atual = 'em_preparo' and p_status_novo = 'retirado')
  ) then
    raise exception
      'Transição de status inválida: % → % para pedido %.',
      p_status_atual,
      p_status_novo,
      p_pedido_id;
  end if;

  if p_status_novo = 'aceito' then
    select
      count(*),
      count(*) filter (where precificacao_finalizada_em is null)
    into v_qtd_itens, v_qtd_pendentes
    from public.itens_pedido
    where pedido_id = p_pedido_id;

    if v_qtd_itens = 0 then
      raise exception 'Pedido sem itens não pode ser aceito.';
    end if;

    if v_qtd_pendentes > 0 then
      raise exception 'Pedido com precificação pendente não pode ser aceito.';
    end if;
  end if;

  if p_status_novo in ('saiu_para_entrega', 'entregue') then
    if p_tipo <> 'entrega' then
      raise exception 'Status % exige pedido de entrega.', p_status_novo;
    end if;

    if v_endereco_id is null
       or not exists (
         select 1
         from public.enderecos_cliente e
         join public.clientes c on c.id = e.cliente_id
         where e.id = v_endereco_id
           and e.cliente_id = p_cliente_id
           and c.restaurante_id = p_restaurante_id
       )
    then
      raise exception 'Endereço de entrega ausente ou inválido para o cliente/restaurante.';
    end if;

    if p_motoboy_id is null
       or not exists (
         select 1
         from public.motoboys m
         join public.usuarios u on u.id = m.id
         where m.id = p_motoboy_id
           and m.restaurante_id = p_restaurante_id
           and u.restaurante_id = p_restaurante_id
           and u.role = 'motoboy'
           and u.ativo = true
       )
    then
      raise exception 'Motoboy ausente, inativo ou de outro restaurante.';
    end if;
  end if;

  if p_status_novo = 'retirado' then
    if p_tipo <> 'retirada' then
      raise exception 'Status retirado exige pedido de retirada.';
    end if;

    if round(coalesce(p_taxa_entrega, 0), 2) <> 0 then
      raise exception 'Pedido de retirada deve permanecer com taxa de entrega zero.';
    end if;
  end if;
end;
$function$;

revoke all
on function public._validar_transicao_status_pedido(
  uuid, uuid, uuid, public.status_pedido, public.status_pedido,
  public.tipo_pedido, uuid, uuid, uuid, numeric
)
from public, anon, authenticated;

grant execute
on function public._validar_transicao_status_pedido(
  uuid, uuid, uuid, public.status_pedido, public.status_pedido,
  public.tipo_pedido, uuid, uuid, uuid, numeric
)
to service_role;

create or replace function public.trg_validar_transicao_status_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public._validar_transicao_status_pedido(
    new.id,
    new.restaurante_id,
    new.cliente_id,
    old.status,
    new.status,
    new.tipo,
    new.endereco_entrega_id,
    new.endereco_id,
    new.motoboy_id,
    new.taxa_entrega
  );
  return new;
end;
$function$;

revoke all
on function public.trg_validar_transicao_status_pedido()
from public, anon, authenticated;

drop trigger if exists trg_bloquear_10_transicao_status
on public.pedidos;

create trigger trg_bloquear_10_transicao_status
before update of status
on public.pedidos
for each row
execute function public.trg_validar_transicao_status_pedido();