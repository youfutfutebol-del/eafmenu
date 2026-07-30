alter table public.restaurantes
  add column if not exists aceita_pedidos_24h boolean not null default false;

create or replace function public.horarios_semana_validos(p_horarios jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = pg_catalog
as $$
declare
  v_item jsonb;
  v_dia integer;
  v_dias integer[] := array[]::integer[];
  v_abre text;
  v_fecha text;
begin
  if p_horarios is null then return true; end if;
  if jsonb_typeof(p_horarios) <> 'array' then return false; end if;
  if jsonb_array_length(p_horarios) > 7 then return false; end if;

  for v_item in select value from jsonb_array_elements(p_horarios)
  loop
    if jsonb_typeof(v_item) <> 'object' then return false; end if;
    if jsonb_typeof(v_item->'dia') <> 'number' or (v_item->>'dia') !~ '^[0-6]$' then return false; end if;
    v_dia := (v_item->>'dia')::integer;
    if v_dia = any(v_dias) then return false; end if;
    v_dias := array_append(v_dias, v_dia);

    if jsonb_typeof(v_item->'aberto') <> 'boolean' then return false; end if;
    if (v_item->>'aberto')::boolean then
      v_abre := v_item->>'abre';
      v_fecha := v_item->>'fecha';
      if v_abre is null or v_fecha is null
         or v_abre !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
         or v_fecha !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
         or v_abre = v_fecha then
        return false;
      end if;
    end if;
  end loop;

  return true;
end;
$$;

alter table public.restaurantes drop constraint if exists restaurantes_horarios_semana_validos;
alter table public.restaurantes
  add constraint restaurantes_horarios_semana_validos
  check (public.horarios_semana_validos(horarios_semana));

create or replace function public._status_funcionamento_restaurante_em(
  p_restaurante_id uuid,
  p_instante timestamptz
)
returns table(
  aberto boolean,
  configurado boolean,
  horario_valido boolean,
  motivo text,
  proxima_abertura timestamptz,
  proxima_mudanca timestamptz,
  mensagem text,
  servidor_agora timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_horarios jsonb;
  v_24h boolean;
  v_local timestamp;
  v_data date;
  v_dow integer;
  v_cfg jsonb;
  v_abre time;
  v_fecha time;
  v_inicio timestamp;
  v_fim timestamp;
  v_i integer;
  v_dia integer;
  v_candidato timestamp;
  v_diferenca_dias integer;
  v_nome_dia text;
begin
  servidor_agora := coalesce(p_instante, now());

  select r.horarios_semana, r.aceita_pedidos_24h
    into v_horarios, v_24h
  from public.restaurantes r
  where r.id = p_restaurante_id;

  if not found then
    aberto := false; configurado := false; horario_valido := false;
    motivo := 'restaurante_nao_encontrado'; mensagem := 'Restaurante não encontrado.';
    return next; return;
  end if;

  if v_24h then
    aberto := true; configurado := true; horario_valido := true;
    motivo := 'aberto_24h'; mensagem := 'Aberto 24 horas';
    return next; return;
  end if;

  if v_horarios is null or jsonb_typeof(v_horarios) <> 'array' or jsonb_array_length(v_horarios) = 0 then
    aberto := false; configurado := false; horario_valido := true;
    motivo := 'sem_configuracao';
    mensagem := 'Configure o horário de funcionamento para liberar pedidos no cardápio.';
    return next; return;
  end if;

  if not public.horarios_semana_validos(v_horarios) then
    aberto := false; configurado := true; horario_valido := false;
    motivo := 'horario_invalido'; mensagem := 'Horário de funcionamento inválido.';
    return next; return;
  end if;

  configurado := true;
  horario_valido := true;
  v_local := servidor_agora at time zone 'America/Sao_Paulo';
  v_data := v_local::date;
  v_dow := extract(dow from v_local)::integer;

  select value into v_cfg
  from jsonb_array_elements(v_horarios)
  where (value->>'dia')::integer = v_dow
  limit 1;

  if v_cfg is not null and (v_cfg->>'aberto')::boolean then
    v_abre := (v_cfg->>'abre')::time;
    v_fecha := (v_cfg->>'fecha')::time;
    v_inicio := v_data + v_abre;
    v_fim := v_data + v_fecha + case when v_fecha < v_abre then interval '1 day' else interval '0 day' end;
    if v_local >= v_inicio and v_local < v_fim then
      aberto := true; motivo := 'aberto'; mensagem := 'Aberto agora';
      proxima_mudanca := v_fim at time zone 'America/Sao_Paulo';
      return next; return;
    end if;
  end if;

  v_cfg := null;
  select value into v_cfg
  from jsonb_array_elements(v_horarios)
  where (value->>'dia')::integer = ((v_dow + 6) % 7)
  limit 1;

  if v_cfg is not null and (v_cfg->>'aberto')::boolean then
    v_abre := (v_cfg->>'abre')::time;
    v_fecha := (v_cfg->>'fecha')::time;
    if v_fecha < v_abre then
      v_inicio := (v_data - 1) + v_abre;
      v_fim := v_data + v_fecha;
      if v_local >= v_inicio and v_local < v_fim then
        aberto := true; motivo := 'aberto'; mensagem := 'Aberto agora';
        proxima_mudanca := v_fim at time zone 'America/Sao_Paulo';
        return next; return;
      end if;
    end if;
  end if;

  aberto := false;
  motivo := 'fechado';

  for v_i in 0..7 loop
    v_dia := (v_dow + v_i) % 7;
    v_cfg := null;
    select value into v_cfg
    from jsonb_array_elements(v_horarios)
    where (value->>'dia')::integer = v_dia
    limit 1;

    if v_cfg is null or not (v_cfg->>'aberto')::boolean then continue; end if;
    v_abre := (v_cfg->>'abre')::time;
    v_candidato := (v_data + v_i) + v_abre;
    if v_candidato <= v_local then continue; end if;

    proxima_abertura := v_candidato at time zone 'America/Sao_Paulo';
    proxima_mudanca := proxima_abertura;
    v_diferenca_dias := v_candidato::date - v_data;

    if v_diferenca_dias = 0 then
      mensagem := 'Abre hoje às ' || to_char(v_candidato, 'HH24:MI');
    elsif v_diferenca_dias = 1 then
      mensagem := 'Abre amanhã às ' || to_char(v_candidato, 'HH24:MI');
    else
      v_nome_dia := case extract(dow from v_candidato)::integer
        when 0 then 'domingo'
        when 1 then 'segunda-feira'
        when 2 then 'terça-feira'
        when 3 then 'quarta-feira'
        when 4 then 'quinta-feira'
        when 5 then 'sexta-feira'
        else 'sábado' end;
      mensagem := 'Abre ' || v_nome_dia || ' às ' || to_char(v_candidato, 'HH24:MI');
    end if;
    return next; return;
  end loop;

  mensagem := 'Fechado no momento.';
  return next;
end;
$$;

revoke all on function public._status_funcionamento_restaurante_em(uuid,timestamptz)
from public, anon, authenticated, service_role;

create or replace function public.restaurante_esta_aberto_agora(p_restaurante_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select s.aberto
  from public._status_funcionamento_restaurante_em(p_restaurante_id, now()) s;
$$;

revoke all on function public.restaurante_esta_aberto_agora(uuid)
from public, anon, authenticated;
grant execute on function public.restaurante_esta_aberto_agora(uuid) to service_role;

create or replace function public.status_publico_restaurante(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_restaurante_id uuid;
  v_status record;
begin
  select r.id into v_restaurante_id
  from public.restaurantes r
  where r.slug = lower(btrim(coalesce(p_slug, '')))
  limit 1;

  if v_restaurante_id is null then return null; end if;

  select * into v_status
  from public._status_funcionamento_restaurante_em(v_restaurante_id, now());

  return jsonb_build_object(
    'restaurante_id', v_restaurante_id,
    'aberto', v_status.aberto,
    'configurado', v_status.configurado,
    'horario_valido', v_status.horario_valido,
    'motivo', v_status.motivo,
    'proxima_abertura', v_status.proxima_abertura,
    'proxima_mudanca', v_status.proxima_mudanca,
    'mensagem', v_status.mensagem,
    'servidor_agora', v_status.servidor_agora
  );
end;
$$;

revoke all on function public.status_publico_restaurante(text) from public;
grant execute on function public.status_publico_restaurante(text) to anon, authenticated, service_role;

alter function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
  rename to _criar_pedido_cliente_v1_impl_horario_servidor;

revoke all on function public._criar_pedido_cliente_v1_impl_horario_servidor(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
from public, anon, authenticated, service_role;

create or replace function public.criar_pedido_cliente_v1(
  p_restaurante_id uuid,
  p_tipo public.tipo_pedido,
  p_forma_pagamento text,
  p_troco_para numeric,
  p_endereco jsonb,
  p_itens jsonb,
  p_chave_idempotencia text
)
returns table(pedido_id uuid, numero_diario integer, total numeric, reutilizado boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_chave text := btrim(coalesce(p_chave_idempotencia, ''));
  v_existente boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'pedido:cliente:' || coalesce(p_restaurante_id::text, '') || ':' || v_chave, 0
  ));

  select exists(
    select 1 from public.pedidos p
    where p.restaurante_id = p_restaurante_id
      and p.origem_criacao = 'cliente'
      and p.chave_idempotencia = v_chave
  ) into v_existente;

  if v_existente then
    return query
    select * from public._criar_pedido_cliente_v1_impl_endereco_seguro(
      p_restaurante_id,p_tipo,p_forma_pagamento,p_troco_para,p_endereco,p_itens,p_chave_idempotencia
    );
    return;
  end if;

  if not coalesce(public.restaurante_esta_aberto_agora(p_restaurante_id), false) then
    raise exception 'O restaurante está fechado no momento. Consulte o próximo horário de funcionamento.';
  end if;

  return query
  select * from public._criar_pedido_cliente_v1_impl_horario_servidor(
    p_restaurante_id,p_tipo,p_forma_pagamento,p_troco_para,p_endereco,p_itens,p_chave_idempotencia
  );
end;
$$;

revoke all on function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
from public, anon;
grant execute on function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
to authenticated, service_role;

comment on column public.restaurantes.aceita_pedidos_24h is
  'Quando true, pedidos públicos são aceitos 24 horas e horarios_semana não é usado para bloqueio.';
comment on function public.status_publico_restaurante(text) is
  'Retorna estado público de funcionamento calculado no servidor em America/Sao_Paulo.';
comment on function public.criar_pedido_manual_v1(uuid,text,text,public.tipo_pedido,text,numeric,text,jsonb,jsonb,jsonb,text,text) is
  'Cria pedido manual transacional. Equipe autenticada pode registrar pedidos fora do horário público.';