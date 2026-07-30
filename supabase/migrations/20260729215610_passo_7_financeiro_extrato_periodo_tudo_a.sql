create or replace function public.listar_movimentacoes_financeiras_v2(
  p_periodo text default 'hoje'::text
)
returns table(
  id uuid,
  tipo text,
  descricao text,
  valor numeric,
  pedido_id uuid,
  criado_em timestamp with time zone,
  forma_pagamento text,
  origem text,
  criado_por uuid,
  ajuste_de_id uuid,
  motivo_ajuste text
)
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_usuario public.usuarios%rowtype;
  v_periodo text := lower(btrim(coalesce(p_periodo, 'hoje')));
  v_dia date;
  v_inicio timestamptz;
  v_fim timestamptz;
begin
  select u.*
    into v_usuario
    from public.usuarios u
   where u.id = auth.uid();

  if v_usuario.id is null
     or v_usuario.ativo is not true
     or v_usuario.role not in ('dono', 'gerente') then
    raise exception 'Você não tem permissão para consultar o financeiro.';
  end if;

  if v_usuario.restaurante_id is null then
    raise exception 'Seu usuário não possui restaurante.';
  end if;

  if v_periodo = 'tudo' then
    v_inicio := null;
    v_fim := null;
  else
    v_dia := public.dia_comercial_atual();

    if v_periodo = 'hoje' then
      v_inicio := public.inicio_dia_comercial(v_dia);
    elsif v_periodo = '7dias' then
      v_inicio := public.inicio_dia_comercial(v_dia - 6);
    elsif v_periodo = '30dias' then
      v_inicio := public.inicio_dia_comercial(v_dia - 29);
    else
      raise exception 'Período inválido.';
    end if;

    v_fim := public.fim_dia_comercial(v_dia);
  end if;

  return query
  select
    m.id,
    m.tipo,
    m.descricao,
    m.valor,
    m.pedido_id,
    m.criado_em,
    m.forma_pagamento,
    m.origem,
    m.criado_por,
    m.ajuste_de_id,
    m.motivo_ajuste
  from public.movimentacoes_financeiras m
  where m.restaurante_id = v_usuario.restaurante_id
    and (
      v_periodo = 'tudo'
      or (m.criado_em >= v_inicio and m.criado_em < v_fim)
    )
  order by m.criado_em desc, m.id;
end
$function$;