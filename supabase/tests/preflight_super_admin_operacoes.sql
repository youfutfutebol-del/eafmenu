-- Executar somente depois das três migrations desta rodada e sempre em BEGIN/ROLLBACK.

-- Compatibilidade do backfill e default de novas lojas.
do $$
declare
  v_novo uuid := gen_random_uuid();
begin
  if exists (select 1 from public.restaurantes where not modulo_motoboy_ativo) then
    raise exception 'PREFLIGHT: restaurante anterior à migration ficou sem módulo';
  end if;

  insert into public.restaurantes(id, nome, slug)
  values (v_novo, 'Preflight default', 'preflight-default-' || replace(v_novo::text, '-', ''));
  if (select modulo_motoboy_ativo from public.restaurantes where id = v_novo) then
    raise exception 'PREFLIGHT: restaurante novo não recebeu default false';
  end if;
end;
$$;

-- Pausa, módulo, auditoria, preservação de dados e FKs históricas.
do $$
declare
  v_admin uuid;
  v_comum uuid;
  v_restaurante uuid;
  v_restaurante_pausa uuid;
  v_motoboys bigint;
  v_pedidos bigint;
  v_erro boolean;
begin
  select id into strict v_admin from public.admins_plataforma order by criado_em limit 1;
  select id into strict v_comum
  from public.usuarios u
  where not exists (select 1 from public.admins_plataforma a where a.id = u.id)
  order by criado_em limit 1;
  select r.id into strict v_restaurante
  from public.restaurantes r
  where r.modulo_motoboy_ativo
  order by (select count(*) from public.motoboys m where m.restaurante_id = r.id) desc, r.criado_em
  limit 1;
  select r.id into strict v_restaurante_pausa
  from public.restaurantes r
  where not exists (
    select 1 from public.pedidos p
    where p.restaurante_id = r.id
      and p.status not in ('entregue', 'retirado', 'cancelado')
  )
  order by r.criado_em limit 1;

  select count(*) into v_motoboys from public.motoboys where restaurante_id = v_restaurante;
  select count(*) into v_pedidos from public.pedidos where restaurante_id = v_restaurante;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  perform * from public.super_admin_definir_modulo_motoboy(v_restaurante, false);
  if (select modulo_motoboy_ativo from public.restaurantes where id = v_restaurante) then
    raise exception 'PREFLIGHT: Super Admin não desativou o módulo';
  end if;
  if exists (
    select 1 from public.restaurantes
    where id = v_restaurante
      and (modulo_motoboy_alterado_em is null or modulo_motoboy_alterado_por <> v_admin)
  ) then
    raise exception 'PREFLIGHT: auditoria do módulo não foi preenchida';
  end if;
  if (select count(*) from public.motoboys where restaurante_id = v_restaurante) <> v_motoboys
     or (select count(*) from public.pedidos where restaurante_id = v_restaurante) <> v_pedidos then
    raise exception 'PREFLIGHT: desativação apagou motoboys ou histórico';
  end if;

  perform * from public.super_admin_definir_modulo_motoboy(v_restaurante, true);
  if not public.modulo_motoboy_operacional(v_restaurante) then
    raise exception 'PREFLIGHT: reativação não restaurou acesso operacional';
  end if;

  v_erro := false;
  begin
    perform * from public.super_admin_definir_modulo_motoboy(gen_random_uuid(), true);
  exception when no_data_found then v_erro := true;
  end;
  if not v_erro then raise exception 'PREFLIGHT: restaurante inexistente foi aceito'; end if;

  perform set_config('request.jwt.claim.sub', v_comum::text, true);
  v_erro := false;
  begin
    perform * from public.super_admin_definir_modulo_motoboy(v_restaurante, false);
  exception when insufficient_privilege then v_erro := true;
  end;
  if not v_erro then raise exception 'PREFLIGHT: usuário comum alterou módulo'; end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform * from public.super_admin_definir_pausa_restaurante(v_restaurante_pausa, true, 'Teste de FK');
  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.restaurantes'::regclass
      and c.conname in (
        'restaurantes_pausado_por_fkey',
        'restaurantes_modulo_motoboy_alterado_por_fkey'
      )
      and c.confdeltype = 'r'
  ) then
    raise exception 'PREFLIGHT: FKs de auditoria não usam RESTRICT/NO ACTION';
  end if;
  v_erro := false;
  begin
    delete from public.admins_plataforma where id = v_admin;
  exception when foreign_key_violation then v_erro := true;
  end;
  if not v_erro then raise exception 'PREFLIGHT: administrador auditado pôde ser removido'; end if;
  perform * from public.super_admin_definir_pausa_restaurante(v_restaurante_pausa, false, null);
end;
$$;

-- Grants reais: anon sem EXECUTE; authenticated entra na RPC e é barrado
-- internamente; Super Admin autenticado executa.
do $$
begin
  if has_function_privilege('anon', 'public.super_admin_definir_modulo_motoboy(uuid,boolean)', 'EXECUTE') then
    raise exception 'PREFLIGHT: anon possui grant administrativo';
  end if;
  if not has_function_privilege('authenticated', 'public.super_admin_definir_modulo_motoboy(uuid,boolean)', 'EXECUTE') then
    raise exception 'PREFLIGHT: authenticated não possui grant esperado';
  end if;
end;
$$;

-- Endurecimento da autorização central e presença dos locks de serialização.
do $$
declare
  v_config text;
  v_definicao text;
begin
  select setting into v_config
  from pg_proc p
  cross join lateral unnest(p.proconfig) setting
  where p.oid = 'public.eh_super_admin()'::regprocedure
    and setting like 'search_path=%';
  if v_config not in ('search_path=', 'search_path=""') then
    raise exception 'PREFLIGHT: eh_super_admin mantém search_path inseguro: %', v_config;
  end if;
  if not exists (
    select 1 from pg_proc p
    where p.oid = 'public.eh_super_admin()'::regprocedure
      and p.prosecdef and p.provolatile = 's'
  ) then
    raise exception 'PREFLIGHT: eh_super_admin não é STABLE SECURITY DEFINER';
  end if;

  select pg_get_functiondef('public.super_admin_definir_pausa_restaurante(uuid,boolean,text)'::regprocedure)
    into v_definicao;
  if position('FOR UPDATE' in upper(v_definicao)) = 0 then
    raise exception 'PREFLIGHT: RPC de pausa não bloqueia o restaurante FOR UPDATE';
  end if;
  select pg_get_functiondef('public.trg_bloquear_operacao_restaurante()'::regprocedure)
    into v_definicao;
  if position('FOR SHARE' in upper(v_definicao)) = 0 then
    raise exception 'PREFLIGHT: trigger operacional não usa FOR SHARE';
  end if;
  select pg_get_functiondef('public.trg_bloquear_operacao_motoboy()'::regprocedure)
    into v_definicao;
  if position('FOR SHARE' in upper(v_definicao)) = 0 then
    raise exception 'PREFLIGHT: trigger de motoboy não usa FOR SHARE';
  end if;
end;
$$;

set local role anon;
do $$
declare v_erro boolean := false;
begin
  begin
    perform * from public.super_admin_definir_modulo_motoboy(gen_random_uuid(), true);
  exception when insufficient_privilege then v_erro := true;
  end;
  if not v_erro then raise exception 'PREFLIGHT: anon executou RPC administrativa'; end if;
end;
$$;
reset role;

select set_config(
  'request.jwt.claim.sub',
  (select u.id::text from public.usuarios u
   where not exists (select 1 from public.admins_plataforma a where a.id = u.id)
   order by u.criado_em limit 1),
  true
);
set local role authenticated;
do $$
declare v_erro boolean := false;
begin
  begin
    perform * from public.super_admin_definir_modulo_motoboy(gen_random_uuid(), true);
  exception when insufficient_privilege then v_erro := true;
  end;
  if not v_erro then raise exception 'PREFLIGHT: authenticated comum passou pela autorização'; end if;
end;
$$;
reset role;

select set_config(
  'request.jwt.claim.sub',
  (select id::text from public.admins_plataforma order by criado_em limit 1),
  true
);
set local role authenticated;
do $$
declare v_restaurante uuid;
begin
  select id into strict v_restaurante from public.restaurantes order by criado_em limit 1;
  perform * from public.super_admin_definir_modulo_motoboy(v_restaurante, true);
end;
$$;
reset role;

-- Pedido de cliente: recuperação idempotente durante pausa e recusa de chave nova.
do $$
declare
  v_pedido public.pedidos%rowtype;
  v_payload jsonb;
  v_resultado record;
  v_qtd bigint;
  v_erro boolean := false;
begin
  select * into v_pedido
  from public.pedidos p
  where p.origem_criacao = 'cliente'
    and p.chave_idempotencia is not null
    and p.conteudo_idempotencia is not null
    and p.conteudo_idempotencia->>'tipo' = 'retirada'
  order by p.criado_em desc limit 1;
  if v_pedido.id is null then
    raise exception 'PREFLIGHT: falta pedido idempotente de referência';
  end if;
  v_payload := v_pedido.conteudo_idempotencia;
  v_payload := jsonb_set(v_payload, '{dia_comercial}', to_jsonb(public.dia_comercial_atual()));
  insert into public.cliente_sessoes(
    auth_user_id, restaurante_id, cliente_id, dia_comercial
  ) values (
    (v_payload->>'auth_user_id')::uuid,
    v_pedido.restaurante_id,
    (v_payload->>'cliente_id')::uuid,
    public.dia_comercial_atual()
  )
  on conflict (auth_user_id, restaurante_id)
  do update set
    cliente_id = excluded.cliente_id,
    dia_comercial = excluded.dia_comercial,
    atualizado_em = now();
  update public.pedidos
  set conteudo_idempotencia = v_payload,
      cliente_sessao_dia_comercial = public.dia_comercial_atual()
  where id = v_pedido.id;
  select count(*) into v_qtd from public.pedidos;
  update public.restaurantes
  set pausado = true,
      pausado_em = now(),
      pausado_por = (select id from public.admins_plataforma order by criado_em limit 1),
      motivo_pausa = 'Preflight idempotência'
  where id = v_pedido.restaurante_id;
  perform set_config('request.jwt.claim.sub', v_payload->>'auth_user_id', true);

  select * into v_resultado
  from public.criar_pedido_cliente_v1(
    v_pedido.restaurante_id,
    (v_payload->>'tipo')::public.tipo_pedido,
    v_payload->>'forma_pagamento',
    nullif(v_payload->>'troco_para', '')::numeric,
    v_payload->'endereco',
    v_payload->'itens',
    v_pedido.chave_idempotencia
  );
  if v_resultado.pedido_id <> v_pedido.id or not v_resultado.reutilizado then
    raise exception 'PREFLIGHT: retry idempotente não recuperou pedido';
  end if;
  if (select count(*) from public.pedidos) <> v_qtd then
    raise exception 'PREFLIGHT: retry criou pedido duplicado';
  end if;

  begin
    perform * from public.criar_pedido_cliente_v1(
      v_pedido.restaurante_id,
      (v_payload->>'tipo')::public.tipo_pedido,
      v_payload->>'forma_pagamento',
      nullif(v_payload->>'troco_para', '')::numeric,
      v_payload->'endereco',
      v_payload->'itens',
      'preflight-nova-' || gen_random_uuid()::text
    );
  exception when object_not_in_prerequisite_state then v_erro := true;
  end;
  if not v_erro then raise exception 'PREFLIGHT: pedido novo passou durante pausa'; end if;
  if (select count(*) from public.pedidos) <> v_qtd then
    raise exception 'PREFLIGHT: erro deixou alteração intermediária';
  end if;
  update public.restaurantes
  set pausado = false, pausado_em = null, pausado_por = null, motivo_pausa = null
  where id = v_pedido.restaurante_id;
end;
$$;

-- Notificações por papel, leitura individual e histórico do Super Admin.
do $$
declare
  v_admin uuid;
  v_restaurante uuid;
  v_usuario uuid;
  v_motoboy uuid;
  v_notificacao uuid;
  v_total integer;
  v_role public.user_role;
begin
  select id into strict v_admin from public.admins_plataforma order by criado_em limit 1;
  select r.id into strict v_restaurante
  from public.restaurantes r
  where not r.pausado
    and exists (
      select 1 from public.usuarios u
      where u.restaurante_id = r.id and u.ativo and u.role in ('dono','gerente','atendente')
    )
  order by r.criado_em limit 1;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  select notificacao_id, total_destinos into v_notificacao, v_total
  from public.super_admin_enviar_notificacao(
    'Preflight histórico', 'Mensagem de teste', 'informativa', array[v_restaurante], false
  );
  if v_total <> 1 then raise exception 'PREFLIGHT: destino de notificação incorreto'; end if;

  foreach v_role in array array['dono','gerente','atendente']::public.user_role[]
  loop
    select id into v_usuario
    from public.usuarios
    where restaurante_id = v_restaurante and role = v_role and ativo
    order by criado_em limit 1;
    if v_usuario is not null then
      perform set_config('request.jwt.claim.sub', v_usuario::text, true);
      if not exists (
        select 1 from public.listar_notificacoes_restaurante() where id = v_notificacao
      ) then
        raise exception 'PREFLIGHT: papel % não listou notificação', v_role;
      end if;
    end if;
  end loop;

  select id into v_usuario
  from public.usuarios
  where restaurante_id = v_restaurante and role in ('dono','gerente','atendente') and ativo
  order by criado_em limit 1;
  perform set_config('request.jwt.claim.sub', v_usuario::text, true);
  perform public.marcar_notificacao_restaurante_lida(v_notificacao);

  select u.id into v_motoboy
  from public.usuarios u where u.role = 'motoboy' and u.ativo order by u.criado_em limit 1;
  if v_motoboy is not null then
    perform set_config('request.jwt.claim.sub', v_motoboy::text, true);
    begin
      perform * from public.listar_notificacoes_restaurante();
      raise exception 'PREFLIGHT: motoboy listou notificações';
    exception when insufficient_privilege then null;
    end;
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  if not exists (
    select 1
    from public.super_admin_listar_notificacoes_enviadas() h
    where h.id = v_notificacao and h.total_destinatarios = 1 and h.total_leituras = 1
  ) then
    raise exception 'PREFLIGHT: histórico não consolidou destinos e leituras';
  end if;
  if not exists (
    select 1
    from public.super_admin_detalhar_notificacao_enviada(v_notificacao) d
    where d.restaurante_id = v_restaurante
      and jsonb_array_length(d.leituras) = 1
      and d.leituras->0->>'usuario_nome' is not null
      and d.leituras->0->>'papel' is not null
      and d.leituras->0->>'lida_em' is not null
  ) then
    raise exception 'PREFLIGHT: detalhe não retornou destinatário e leitura';
  end if;
end;
$$;

-- RPCs de leitura do painel não podem consultar durante a suspensão.
do $$
declare
  v_dono uuid;
  v_restaurante uuid;
  v_erro boolean;
begin
  select u.id, u.restaurante_id into strict v_dono, v_restaurante
  from public.usuarios u
  where u.role = 'dono' and u.ativo
  order by u.criado_em limit 1;
  update public.restaurantes
  set pausado = true,
      pausado_em = now(),
      pausado_por = (select id from public.admins_plataforma order by criado_em limit 1),
      motivo_pausa = 'Preflight RPC leitura'
  where id = v_restaurante;
  perform set_config('request.jwt.claim.sub', v_dono::text, true);

  v_erro := false;
  begin perform public.relatorio_financeiro_v2(null, null);
  exception when object_not_in_prerequisite_state then v_erro := true; end;
  if not v_erro then raise exception 'PREFLIGHT: relatório financeiro passou suspenso'; end if;

  v_erro := false;
  begin perform public.relatorio_cancelamentos_v1('hoje', null, null);
  exception when object_not_in_prerequisite_state then v_erro := true; end;
  if not v_erro then raise exception 'PREFLIGHT: cancelamentos passou suspenso'; end if;

  v_erro := false;
  begin perform * from public.listar_movimentacoes_financeiras_v2('hoje');
  exception when object_not_in_prerequisite_state then v_erro := true; end;
  if not v_erro then raise exception 'PREFLIGHT: movimentações passou suspenso'; end if;
end;
$$;

select 'PREFLIGHT_OK' as resultado;
