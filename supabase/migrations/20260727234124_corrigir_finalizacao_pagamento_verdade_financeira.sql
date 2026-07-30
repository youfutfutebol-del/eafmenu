-- Ponto 1: finalização, pagamento e verdade financeira.

create or replace function public.trg_validar_pagamento_finalizacao()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if tg_op = 'UPDATE'
     and old.pago = true
     and new.pago = false
     and coalesce(current_setting('eafmenu.via_estorno_financeiro', true), 'false') <> 'true'
  then
    raise exception 'Pagamento confirmado não pode ser desmarcado diretamente. Use o fluxo de estorno.';
  end if;

  if new.pago = true
     and (tg_op = 'INSERT' or coalesce(old.pago, false) = false)
  then
    if new.status = 'cancelado' then
      raise exception 'Pedido cancelado não pode ser marcado como pago.';
    end if;

    if nullif(trim(coalesce(new.forma_pagamento, '')), '') is null then
      raise exception 'Informe a forma de pagamento antes de confirmar o recebimento.';
    end if;
  end if;

  if new.status in ('entregue', 'retirado') and new.pago = false then
    raise exception 'Pedido precisa estar pago antes de ser finalizado.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_bloquear_05_pagamento_finalizacao on public.pedidos;
create trigger trg_bloquear_05_pagamento_finalizacao
before insert or update of status, pago on public.pedidos
for each row execute function public.trg_validar_pagamento_finalizacao();

create or replace function public.gerar_entrada_financeira_pedido()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_mov public.movimentacoes_financeiras%rowtype;
begin
  if new.pago = true
     and (tg_op = 'INSERT' or coalesce(old.pago, false) = false)
  then
    insert into public.movimentacoes_financeiras
      (restaurante_id, tipo, descricao, valor, pedido_id, criado_por, forma_pagamento)
    values (
      new.restaurante_id,
      'receita',
      case when new.numero_diario is not null
        then 'Pedido #' || new.numero_diario
        else 'Pedido #' || upper(substr(new.id::text, 1, 8))
      end,
      new.total,
      new.id,
      auth.uid(),
      new.forma_pagamento
    )
    on conflict (pedido_id) do nothing;

    select * into v_mov
    from public.movimentacoes_financeiras
    where pedido_id = new.id;

    if v_mov.id is null
       or v_mov.restaurante_id is distinct from new.restaurante_id
       or v_mov.tipo is distinct from 'receita'
       or round(v_mov.valor, 2) is distinct from round(new.total, 2)
       or v_mov.forma_pagamento is distinct from new.forma_pagamento
    then
      raise exception 'Falha de conciliação financeira do pedido %.', new.id;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.relatorio_financeiro_v2(
  p_data_inicio date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_role public.user_role;
  v_restaurante_id uuid;
  v_local_ts timestamp;
  v_hoje date;
  v_vendido_pedidos integer := 0;
  v_vendido_valor numeric := 0;
  v_recebido_pedidos integer := 0;
  v_recebido_valor numeric := 0;
  v_pendente_pedidos integer := 0;
  v_pendente_valor numeric := 0;
  v_cancelados_pedidos integer := 0;
  v_cancelados_valor numeric := 0;
  v_por_pagamento jsonb := '{}'::jsonb;
  v_por_tipo jsonb := '{}'::jsonb;
  v_top_produtos jsonb := '[]'::jsonb;
  v_periodo jsonb := null;
begin
  select u.role, u.restaurante_id
    into v_role, v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid();

  if v_role is null or v_role <> 'dono' then
    raise exception 'Acesso restrito ao dono do restaurante.';
  end if;

  if (p_data_inicio is null) <> (p_data_fim is null) then
    raise exception 'Informe data de início e data de fim juntas, ou nenhuma das duas.';
  end if;

  if p_data_inicio is not null and p_data_inicio > p_data_fim then
    raise exception 'A data de início não pode ser depois da data de fim.';
  end if;

  v_local_ts := now() at time zone 'America/Sao_Paulo';
  v_hoje := case when extract(hour from v_local_ts) < 7
    then v_local_ts::date - 1
    else v_local_ts::date
  end;

  if p_data_inicio is not null then
    select count(*)::integer, coalesce(sum(p.total), 0)
      into v_vendido_pedidos, v_vendido_valor
    from public.pedidos p
    where p.restaurante_id = v_restaurante_id
      and p.status in ('entregue', 'retirado')
      and p.data_pedido between p_data_inicio and p_data_fim;

    select count(distinct mf.pedido_id)::integer, coalesce(sum(mf.valor), 0)
      into v_recebido_pedidos, v_recebido_valor
    from public.movimentacoes_financeiras mf
    join public.pedidos p on p.id = mf.pedido_id
    where mf.restaurante_id = v_restaurante_id
      and mf.tipo = 'receita'
      and p.data_pedido between p_data_inicio and p_data_fim;

    select count(*)::integer, coalesce(sum(p.total), 0)
      into v_pendente_pedidos, v_pendente_valor
    from public.pedidos p
    where p.restaurante_id = v_restaurante_id
      and p.status in ('entregue', 'retirado')
      and p.data_pedido between p_data_inicio and p_data_fim
      and (
        p.pago = false
        or not exists (
          select 1
          from public.movimentacoes_financeiras mf
          where mf.pedido_id = p.id and mf.tipo = 'receita'
        )
      );

    select count(*)::integer, coalesce(sum(p.total), 0)
      into v_cancelados_pedidos, v_cancelados_valor
    from public.pedidos p
    where p.restaurante_id = v_restaurante_id
      and p.status = 'cancelado'
      and p.data_pedido between p_data_inicio and p_data_fim;

    select coalesce(jsonb_object_agg(x.forma_pagamento, x.valor), '{}'::jsonb)
      into v_por_pagamento
    from (
      select coalesce(mf.forma_pagamento, 'nao_informado') as forma_pagamento,
             sum(mf.valor) as valor
      from public.movimentacoes_financeiras mf
      join public.pedidos p on p.id = mf.pedido_id
      where mf.restaurante_id = v_restaurante_id
        and mf.tipo = 'receita'
        and p.data_pedido between p_data_inicio and p_data_fim
      group by coalesce(mf.forma_pagamento, 'nao_informado')
    ) x;

    select coalesce(jsonb_object_agg(x.tipo, x.valor), '{}'::jsonb)
      into v_por_tipo
    from (
      select p.tipo::text as tipo, sum(p.total) as valor
      from public.pedidos p
      where p.restaurante_id = v_restaurante_id
        and p.status in ('entregue', 'retirado')
        and p.data_pedido between p_data_inicio and p_data_fim
      group by p.tipo
    ) x;

    select coalesce(jsonb_agg(jsonb_build_object(
      'produto_id', x.produto_id,
      'nome', x.nome,
      'quantidade', x.quantidade
    ) order by x.quantidade desc, x.nome), '[]'::jsonb)
      into v_top_produtos
    from (
      select ip.produto_id, pr.nome, sum(ip.quantidade) as quantidade
      from public.itens_pedido ip
      join public.pedidos p on p.id = ip.pedido_id
      join public.produtos pr on pr.id = ip.produto_id
      where p.restaurante_id = v_restaurante_id
        and p.status in ('entregue', 'retirado')
        and p.data_pedido between p_data_inicio and p_data_fim
      group by ip.produto_id, pr.nome
      order by quantidade desc, pr.nome
      limit 5
    ) x;

    v_periodo := jsonb_build_object(
      'data_inicio', p_data_inicio,
      'data_fim', p_data_fim,
      'faturamento', round(v_vendido_valor, 2),
      'pedidos', v_vendido_pedidos,
      'ticket_medio', case when v_vendido_pedidos > 0
        then round(v_vendido_valor / v_vendido_pedidos, 2) else 0 end,
      'vendido', jsonb_build_object(
        'pedidos', v_vendido_pedidos,
        'valor', round(v_vendido_valor, 2)
      ),
      'recebido', jsonb_build_object(
        'pedidos', v_recebido_pedidos,
        'valor', round(v_recebido_valor, 2)
      ),
      'pendente', jsonb_build_object(
        'pedidos', v_pendente_pedidos,
        'valor', round(v_pendente_valor, 2)
      ),
      'cancelados', jsonb_build_object(
        'pedidos', v_cancelados_pedidos,
        'valor', round(v_cancelados_valor, 2),
        'percentual', case when (v_vendido_pedidos + v_cancelados_pedidos) > 0
          then round(v_cancelados_pedidos::numeric / (v_vendido_pedidos + v_cancelados_pedidos) * 100, 2)
          else 0 end
      ),
      'por_forma_pagamento', v_por_pagamento,
      'por_tipo', v_por_tipo,
      'top_produtos', v_top_produtos
    );
  end if;

  return jsonb_build_object(
    'dia_comercial_referencia', v_hoje,
    'periodo_personalizado', v_periodo
  );
end;
$$;

revoke all on function public.relatorio_financeiro_v2(date, date) from public, anon;
grant execute on function public.relatorio_financeiro_v2(date, date) to authenticated;

-- Saneia somente os oito itens legados normais sem marcador de precificação.
do $$
declare
  v_qtd integer;
begin
  select count(*)::integer into v_qtd
  from public.itens_pedido ip
  where ip.id in (
    'eb0ace53-4197-49ad-90ab-00733d79d486',
    '1fb6d929-e681-44ff-9658-8d89268f7c96',
    '10bbf72d-01d2-420b-902c-5d7885978771',
    '6143d450-f057-424e-a66f-f551c6832dbc',
    '5bfefd85-a856-4231-8bc2-0db394868813',
    'b77b4a08-1c15-4e04-bcc9-4ded16e44ddd',
    'd9ddc77d-47d8-4263-992a-dd73e84e7f1e',
    '0555b555-dcb0-40bd-9aac-1a34773672e4'
  )
    and ip.precificacao_finalizada_em is null
    and coalesce(ip.sabores_esperados, 1) = 1
    and ip.produto_id is not null
    and ip.preco_original_unitario > 0
    and ip.preco_efetivo_unitario > 0
    and not exists (
      select 1 from public.itens_pedido_sabores ips
      where ips.item_pedido_id = ip.id
    );

  if v_qtd <> 8 then
    raise exception 'Escopo dos itens legados divergiu: esperado 8, encontrado %.', v_qtd;
  end if;
end;
$$;

update public.itens_pedido ip
set precificacao_finalizada_em = coalesce(p.finalizado_em, p.criado_em)
from public.pedidos p
where p.id = ip.pedido_id
  and ip.id in (
    'eb0ace53-4197-49ad-90ab-00733d79d486',
    '1fb6d929-e681-44ff-9658-8d89268f7c96',
    '10bbf72d-01d2-420b-902c-5d7885978771',
    '6143d450-f057-424e-a66f-f551c6832dbc',
    '5bfefd85-a856-4231-8bc2-0db394868813',
    'b77b4a08-1c15-4e04-bcc9-4ded16e44ddd',
    'd9ddc77d-47d8-4263-992a-dd73e84e7f1e',
    '0555b555-dcb0-40bd-9aac-1a34773672e4'
  );

-- Guarda de escopo dos 17 pedidos terminais sem recebimento.
do $$
declare
  v_qtd integer;
  v_total numeric;
  v_sem_forma integer;
  v_com_mov integer;
begin
  select count(*)::integer, coalesce(sum(total), 0),
         count(*) filter (where nullif(trim(coalesce(forma_pagamento, '')), '') is null)::integer
    into v_qtd, v_total, v_sem_forma
  from public.pedidos
  where status in ('entregue', 'retirado') and pago = false;

  select count(*)::integer into v_com_mov
  from public.pedidos p
  where p.status in ('entregue', 'retirado') and p.pago = false
    and exists (select 1 from public.movimentacoes_financeiras mf where mf.pedido_id = p.id);

  if v_qtd <> 17 or round(v_total, 2) <> 627.00 or v_sem_forma <> 0 or v_com_mov <> 0 then
    raise exception 'Escopo legado divergente: qtd=%, total=%, sem_forma=%, com_mov=%',
      v_qtd, v_total, v_sem_forma, v_com_mov;
  end if;
end;
$$;

insert into public.movimentacoes_financeiras
  (restaurante_id, tipo, descricao, valor, pedido_id, criado_por, criado_em, forma_pagamento)
select
  p.restaurante_id,
  'receita',
  case when p.numero_diario is not null
    then 'Pedido #' || p.numero_diario
    else 'Pedido #' || upper(substr(p.id::text, 1, 8))
  end,
  p.total,
  p.id,
  null,
  coalesce(p.finalizado_em, p.criado_em),
  p.forma_pagamento
from public.pedidos p
where p.status in ('entregue', 'retirado')
  and p.pago = false
on conflict (pedido_id) do nothing;

update public.pedidos
set pago = true
where status in ('entregue', 'retirado')
  and pago = false;

-- Validação final da conciliação.
do $$
declare
  v_pendentes integer;
  v_movimentos integer;
  v_divergencias integer;
begin
  select count(*)::integer into v_pendentes
  from public.pedidos
  where status in ('entregue', 'retirado') and pago = false;

  select count(*)::integer into v_movimentos
  from public.movimentacoes_financeiras mf
  join public.pedidos p on p.id = mf.pedido_id
  where p.status in ('entregue', 'retirado')
    and p.pago = true
    and mf.tipo = 'receita';

  select count(*)::integer into v_divergencias
  from public.pedidos p
  join public.movimentacoes_financeiras mf on mf.pedido_id = p.id
  where p.pago = true
    and (
      mf.tipo <> 'receita'
      or mf.restaurante_id <> p.restaurante_id
      or round(mf.valor, 2) <> round(p.total, 2)
      or mf.forma_pagamento is distinct from p.forma_pagamento
    );

  if v_pendentes <> 0 or v_movimentos <> 28 or v_divergencias <> 0 then
    raise exception 'Validação final falhou: pendentes=%, movimentos_terminais=%, divergencias=%',
      v_pendentes, v_movimentos, v_divergencias;
  end if;
end;
$$;