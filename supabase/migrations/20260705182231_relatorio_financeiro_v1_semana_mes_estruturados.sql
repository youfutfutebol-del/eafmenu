create or replace function public.relatorio_financeiro_v1(
  p_data_inicio date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_role user_role;
  v_restaurante_id uuid;
  v_local_ts timestamp;
  v_hoje date;
  v_inicio_semana date;
  v_inicio_mes date;

  v_pedidos_hoje int;
  v_faturamento_hoje numeric;

  v_pedidos_semana int;
  v_faturamento_semana numeric;

  v_pedidos_mes int;
  v_faturamento_mes numeric;

  v_por_pagamento jsonb;
  v_por_tipo jsonb;
  v_top_produtos jsonb;

  v_periodo_personalizado jsonb := null;
  v_pedidos_periodo int;
  v_faturamento_periodo numeric;
  v_por_pagamento_periodo jsonb;
  v_por_tipo_periodo jsonb;
  v_top_produtos_periodo jsonb;
begin
  -- 1) só dono acessa
  select role, restaurante_id into v_role, v_restaurante_id
  from usuarios where id = auth.uid();

  if v_role is null or v_role <> 'dono' then
    raise exception 'Acesso restrito ao dono do restaurante.';
  end if;

  -- 2) validação das datas
  if (p_data_inicio is not null and p_data_fim is null)
     or (p_data_inicio is null and p_data_fim is not null) then
    raise exception 'Informe data de início e data de fim juntas, ou nenhuma das duas.';
  end if;

  if p_data_inicio is not null and p_data_fim is not null and p_data_inicio > p_data_fim then
    raise exception 'A data de início não pode ser depois da data de fim.';
  end if;

  -- 3) dia comercial (corte às 7h)
  v_local_ts := (now() at time zone 'America/Sao_Paulo');
  if extract(hour from v_local_ts) < 7 then
    v_hoje := (v_local_ts::date) - 1;
  else
    v_hoje := v_local_ts::date;
  end if;

  v_inicio_semana := v_hoje - 6;
  v_inicio_mes := date_trunc('month', v_hoje)::date;

  -- 4) hoje
  select count(*), coalesce(sum(total), 0)
  into v_pedidos_hoje, v_faturamento_hoje
  from pedidos
  where restaurante_id = v_restaurante_id
    and status in ('entregue', 'retirado')
    and data_pedido = v_hoje;

  -- 5) semana
  select count(*), coalesce(sum(total), 0)
  into v_pedidos_semana, v_faturamento_semana
  from pedidos
  where restaurante_id = v_restaurante_id
    and status in ('entregue', 'retirado')
    and data_pedido between v_inicio_semana and v_hoje;

  -- 6) mês
  select count(*), coalesce(sum(total), 0)
  into v_pedidos_mes, v_faturamento_mes
  from pedidos
  where restaurante_id = v_restaurante_id
    and status in ('entregue', 'retirado')
    and data_pedido between v_inicio_mes and v_hoje;

  -- 7) por forma de pagamento (mês corrente)
  select coalesce(jsonb_object_agg(forma_pagamento, total_forma), '{}'::jsonb)
  into v_por_pagamento
  from (
    select coalesce(forma_pagamento, 'nao_informado') as forma_pagamento, sum(total) as total_forma
    from pedidos
    where restaurante_id = v_restaurante_id
      and status in ('entregue', 'retirado')
      and data_pedido between v_inicio_mes and v_hoje
    group by coalesce(forma_pagamento, 'nao_informado')
  ) t;

  -- 8) por tipo (mês corrente)
  select coalesce(jsonb_object_agg(tipo, total_tipo), '{}'::jsonb)
  into v_por_tipo
  from (
    select tipo::text as tipo, sum(total) as total_tipo
    from pedidos
    where restaurante_id = v_restaurante_id
      and status in ('entregue', 'retirado')
      and data_pedido between v_inicio_mes and v_hoje
    group by tipo
  ) t;

  -- 9) top 5 produtos (mês corrente)
  select coalesce(jsonb_agg(jsonb_build_object('produto_id', produto_id, 'nome', nome, 'quantidade', qtd_total) order by qtd_total desc), '[]'::jsonb)
  into v_top_produtos
  from (
    select ip.produto_id, p.nome, sum(ip.quantidade) as qtd_total
    from itens_pedido ip
    join pedidos pe on pe.id = ip.pedido_id
    join produtos p on p.id = ip.produto_id
    where pe.restaurante_id = v_restaurante_id
      and pe.status in ('entregue', 'retirado')
      and pe.data_pedido between v_inicio_mes and v_hoje
    group by ip.produto_id, p.nome
    order by qtd_total desc
    limit 5
  ) t;

  -- 10) período personalizado
  if p_data_inicio is not null and p_data_fim is not null then

    select count(*), coalesce(sum(total), 0)
    into v_pedidos_periodo, v_faturamento_periodo
    from pedidos
    where restaurante_id = v_restaurante_id
      and status in ('entregue', 'retirado')
      and data_pedido between p_data_inicio and p_data_fim;

    select coalesce(jsonb_object_agg(forma_pagamento, total_forma), '{}'::jsonb)
    into v_por_pagamento_periodo
    from (
      select coalesce(forma_pagamento, 'nao_informado') as forma_pagamento, sum(total) as total_forma
      from pedidos
      where restaurante_id = v_restaurante_id
        and status in ('entregue', 'retirado')
        and data_pedido between p_data_inicio and p_data_fim
      group by coalesce(forma_pagamento, 'nao_informado')
    ) t;

    select coalesce(jsonb_object_agg(tipo, total_tipo), '{}'::jsonb)
    into v_por_tipo_periodo
    from (
      select tipo::text as tipo, sum(total) as total_tipo
      from pedidos
      where restaurante_id = v_restaurante_id
        and status in ('entregue', 'retirado')
        and data_pedido between p_data_inicio and p_data_fim
      group by tipo
    ) t;

    select coalesce(jsonb_agg(jsonb_build_object('produto_id', produto_id, 'nome', nome, 'quantidade', qtd_total) order by qtd_total desc), '[]'::jsonb)
    into v_top_produtos_periodo
    from (
      select ip.produto_id, p.nome, sum(ip.quantidade) as qtd_total
      from itens_pedido ip
      join pedidos pe on pe.id = ip.pedido_id
      join produtos p on p.id = ip.produto_id
      where pe.restaurante_id = v_restaurante_id
        and pe.status in ('entregue', 'retirado')
        and pe.data_pedido between p_data_inicio and p_data_fim
      group by ip.produto_id, p.nome
      order by qtd_total desc
      limit 5
    ) t;

    v_periodo_personalizado := jsonb_build_object(
      'data_inicio', p_data_inicio,
      'data_fim', p_data_fim,
      'faturamento', v_faturamento_periodo,
      'pedidos', v_pedidos_periodo,
      'ticket_medio', case when v_pedidos_periodo > 0 then round(v_faturamento_periodo / v_pedidos_periodo, 2) else 0 end,
      'por_forma_pagamento', v_por_pagamento_periodo,
      'por_tipo', v_por_tipo_periodo,
      'top_produtos', v_top_produtos_periodo
    );
  end if;

  return jsonb_build_object(
    'dia_comercial_referencia', v_hoje,
    'hoje', jsonb_build_object(
      'faturamento', v_faturamento_hoje,
      'pedidos', v_pedidos_hoje,
      'ticket_medio', case when v_pedidos_hoje > 0 then round(v_faturamento_hoje / v_pedidos_hoje, 2) else 0 end
    ),
    'semana', jsonb_build_object(
      'faturamento', v_faturamento_semana,
      'pedidos', v_pedidos_semana,
      'ticket_medio', case when v_pedidos_semana > 0 then round(v_faturamento_semana / v_pedidos_semana, 2) else 0 end
    ),
    'mes', jsonb_build_object(
      'faturamento', v_faturamento_mes,
      'pedidos', v_pedidos_mes,
      'ticket_medio', case when v_pedidos_mes > 0 then round(v_faturamento_mes / v_pedidos_mes, 2) else 0 end
    ),
    'por_forma_pagamento', v_por_pagamento,
    'por_tipo', v_por_tipo,
    'top_produtos_mes', v_top_produtos,
    'periodo_personalizado', v_periodo_personalizado
  );
end;
$$;

revoke all on function public.relatorio_financeiro_v1(date, date) from public;
grant execute on function public.relatorio_financeiro_v1(date, date) to authenticated;