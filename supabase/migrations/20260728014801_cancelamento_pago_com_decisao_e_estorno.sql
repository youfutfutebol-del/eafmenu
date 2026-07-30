-- Ponto 3: cancelamento pago com decisão financeira explícita e estorno sem apagar a receita original.

alter table public.movimentacoes_financeiras
  add column if not exists origem text;

update public.movimentacoes_financeiras
set origem = case
  when pedido_id is not null and tipo = 'receita' then 'recebimento_pedido'
  when pedido_id is not null and tipo = 'despesa' then 'estorno_pedido'
  else 'lancamento_manual'
end
where origem is null;

alter table public.movimentacoes_financeiras
  alter column origem set default 'lancamento_manual',
  alter column origem set not null;

alter table public.movimentacoes_financeiras
  drop constraint if exists movimentacoes_financeiras_origem_check;

alter table public.movimentacoes_financeiras
  add constraint movimentacoes_financeiras_origem_check
  check (origem in ('lancamento_manual', 'recebimento_pedido', 'estorno_pedido'));

alter table public.movimentacoes_financeiras
  drop constraint if exists movimentacoes_financeiras_origem_pedido_check;

alter table public.movimentacoes_financeiras
  add constraint movimentacoes_financeiras_origem_pedido_check
  check (
    (origem = 'lancamento_manual' and pedido_id is null)
    or
    (origem in ('recebimento_pedido', 'estorno_pedido') and pedido_id is not null)
  );

alter table public.movimentacoes_financeiras
  drop constraint if exists movimentacoes_financeiras_pedido_id_key;

drop index if exists public.movimentacoes_pedido_unique;
drop index if exists public.movimentacoes_recebimento_pedido_uidx;
drop index if exists public.movimentacoes_estorno_pedido_uidx;

create unique index movimentacoes_recebimento_pedido_uidx
  on public.movimentacoes_financeiras (pedido_id)
  where origem = 'recebimento_pedido';

create unique index movimentacoes_estorno_pedido_uidx
  on public.movimentacoes_financeiras (pedido_id)
  where origem = 'estorno_pedido';

alter table public.pedidos
  add column if not exists cancelamento_decisao_financeira text,
  add column if not exists cancelamento_decisao_financeira_em timestamptz,
  add column if not exists cancelamento_decisao_financeira_por uuid;

alter table public.pedidos
  drop constraint if exists pedidos_cancelamento_decisao_financeira_por_fkey;

alter table public.pedidos
  add constraint pedidos_cancelamento_decisao_financeira_por_fkey
  foreign key (cancelamento_decisao_financeira_por)
  references public.usuarios(id);

update public.pedidos
set cancelamento_decisao_financeira = case
      when pago then 'pendente'
      else 'nao_aplicavel'
    end,
    cancelamento_decisao_financeira_em = case
      when pago then null
      else coalesce(cancelado_em, now())
    end,
    cancelamento_decisao_financeira_por = case
      when pago then null
      else coalesce(cancelado_confirmado_por, cancelado_por)
    end
where status = 'cancelado'
  and cancelamento_decisao_financeira is null;

alter table public.pedidos
  drop constraint if exists pedidos_cancelamento_decisao_financeira_check;

alter table public.pedidos
  add constraint pedidos_cancelamento_decisao_financeira_check
  check (
    cancelamento_decisao_financeira is null
    or cancelamento_decisao_financeira in ('nao_aplicavel', 'pendente', 'estornado', 'mantido')
  );

alter table public.pedidos
  drop constraint if exists pedidos_cancelamento_decisao_completa_check;

alter table public.pedidos
  add constraint pedidos_cancelamento_decisao_completa_check
  check (
    (cancelamento_decisao_financeira is null
      and cancelamento_decisao_financeira_em is null
      and cancelamento_decisao_financeira_por is null)
    or
    (cancelamento_decisao_financeira = 'pendente'
      and cancelamento_decisao_financeira_em is null
      and cancelamento_decisao_financeira_por is null)
    or
    (cancelamento_decisao_financeira in ('nao_aplicavel', 'estornado', 'mantido')
      and cancelamento_decisao_financeira_em is not null
      and cancelamento_decisao_financeira_por is not null)
  );

create or replace function public.trg_proteger_movimento_financeiro_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if tg_op = 'INSERT' then
    if new.origem in ('recebimento_pedido', 'estorno_pedido')
       or new.pedido_id is not null
    then
      if coalesce(current_setting('eafmenu.via_movimento_pedido', true), 'false') <> 'true' then
        raise exception 'Movimento financeiro de pedido só pode ser criado pelo fluxo financeiro do sistema.';
      end if;
    end if;
    return new;
  end if;

  if old.origem in ('recebimento_pedido', 'estorno_pedido')
     or old.pedido_id is not null
  then
    raise exception 'Movimento financeiro de pedido é imutável e não pode ser alterado ou apagado.';
  end if;

  if tg_op = 'UPDATE' then
    if new.origem <> 'lancamento_manual' or new.pedido_id is not null then
      raise exception 'Lançamento manual não pode ser convertido em movimento de pedido.';
    end if;
    return new;
  end if;

  return old;
end;
$function$;

drop trigger if exists trg_proteger_movimento_financeiro_pedido on public.movimentacoes_financeiras;
create trigger trg_proteger_movimento_financeiro_pedido
before insert or update or delete on public.movimentacoes_financeiras
for each row execute function public.trg_proteger_movimento_financeiro_pedido();

create or replace function public.trg_proteger_decisao_financeira_cancelamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.cancelamento_decisao_financeira is distinct from old.cancelamento_decisao_financeira
     or new.cancelamento_decisao_financeira_em is distinct from old.cancelamento_decisao_financeira_em
     or new.cancelamento_decisao_financeira_por is distinct from old.cancelamento_decisao_financeira_por
  then
    if coalesce(current_setting('eafmenu.via_cancelar_pedido', true), 'false') <> 'true'
       and coalesce(current_setting('eafmenu.via_resolver_cancelamento_financeiro', true), 'false') <> 'true'
    then
      raise exception 'A decisão financeira do cancelamento só pode ser registrada pelo fluxo seguro de cancelamento.';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_proteger_decisao_financeira_cancelamento on public.pedidos;
create trigger trg_proteger_decisao_financeira_cancelamento
before update of cancelamento_decisao_financeira, cancelamento_decisao_financeira_em, cancelamento_decisao_financeira_por
on public.pedidos
for each row execute function public.trg_proteger_decisao_financeira_cancelamento();

create or replace function public.gerar_entrada_financeira_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_mov public.movimentacoes_financeiras%rowtype;
begin
  if new.pago = true
     and (tg_op = 'INSERT' or coalesce(old.pago, false) = false)
  then
    perform set_config('eafmenu.via_movimento_pedido', 'true', true);

    insert into public.movimentacoes_financeiras
      (restaurante_id, tipo, origem, descricao, valor, pedido_id, criado_por, forma_pagamento)
    values (
      new.restaurante_id,
      'receita',
      'recebimento_pedido',
      case when new.numero_diario is not null
        then 'Pedido #' || new.numero_diario
        else 'Pedido #' || upper(substr(new.id::text, 1, 8))
      end,
      new.total,
      new.id,
      auth.uid(),
      new.forma_pagamento
    )
    on conflict do nothing;

    select * into v_mov
    from public.movimentacoes_financeiras
    where pedido_id = new.id
      and origem = 'recebimento_pedido';

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
$function$;

create or replace function public.cancelar_pedido_v2(
  p_pedido_id uuid,
  p_motivo text,
  p_senha_confirmacao text,
  p_decisao_financeira text
)
returns table(
  pedido_id uuid,
  cancelado boolean,
  pago boolean,
  decisao_financeira text,
  estorno_movimentacao_id uuid,
  reutilizado boolean
)
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_chamador public.usuarios%rowtype;
  v_pedido public.pedidos%rowtype;
  v_confirmador_id uuid;
  v_senha_ok boolean := false;
  v_candidato record;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_decisao text := lower(btrim(coalesce(p_decisao_financeira, '')));
  v_decisao_final text;
  v_receita public.movimentacoes_financeiras%rowtype;
  v_estorno public.movimentacoes_financeiras%rowtype;
begin
  select * into v_chamador
  from public.usuarios u
  where u.id = auth.uid();

  if v_chamador.id is null
     or v_chamador.ativo is not true
     or v_chamador.role not in ('dono', 'gerente', 'atendente')
  then
    raise exception 'Você não tem permissão para cancelar pedidos.';
  end if;

  select * into v_pedido
  from public.pedidos p
  where p.id = p_pedido_id
  for update;

  if v_pedido.id is null
     or v_pedido.restaurante_id is distinct from v_chamador.restaurante_id
  then
    raise exception 'Pedido não encontrado nesse restaurante.';
  end if;

  if length(v_motivo) < 3 then
    raise exception 'Informe o motivo do cancelamento.';
  end if;

  if nullif(btrim(coalesce(p_senha_confirmacao, '')), '') is null then
    raise exception 'Informe a senha de confirmação.';
  end if;

  if v_chamador.role in ('dono', 'gerente') then
    select exists (
      select 1 from auth.users au
      where au.id = v_chamador.id
        and au.encrypted_password = extensions.crypt(p_senha_confirmacao, au.encrypted_password)
    ) into v_senha_ok;

    if v_senha_ok then v_confirmador_id := v_chamador.id; end if;
  else
    for v_candidato in
      select u.id, au.encrypted_password
      from public.usuarios u
      join auth.users au on au.id = u.id
      where u.restaurante_id = v_chamador.restaurante_id
        and u.role in ('dono', 'gerente')
        and u.ativo = true
    loop
      if v_candidato.encrypted_password = extensions.crypt(p_senha_confirmacao, v_candidato.encrypted_password) then
        v_confirmador_id := v_candidato.id;
        exit;
      end if;
    end loop;
    v_senha_ok := v_confirmador_id is not null;
  end if;

  if not v_senha_ok then
    raise exception 'Senha de confirmação incorreta.';
  end if;

  if v_pedido.status = 'cancelado' then
    if v_pedido.cancelamento_decisao_financeira = 'pendente' then
      raise exception 'Este pedido já está cancelado e ainda possui decisão financeira pendente. Use o fluxo de resolução financeira.';
    end if;

    if v_pedido.motivo_cancelamento is distinct from v_motivo then
      raise exception 'Este pedido já foi cancelado com outro motivo.';
    end if;

    if v_pedido.pago then
      if (v_decisao = 'estornar' and v_pedido.cancelamento_decisao_financeira <> 'estornado')
         or (v_decisao = 'manter_recebido' and v_pedido.cancelamento_decisao_financeira <> 'mantido')
      then
        raise exception 'Este pedido já foi cancelado com outra decisão financeira.';
      end if;
    end if;

    select m.* into v_estorno
    from public.movimentacoes_financeiras m
    where m.pedido_id = v_pedido.id and m.origem = 'estorno_pedido';

    return query select v_pedido.id, true, v_pedido.pago,
      v_pedido.cancelamento_decisao_financeira, v_estorno.id, true;
    return;
  end if;

  if v_pedido.status in ('entregue', 'retirado') then
    if v_pedido.finalizado_em is null or v_pedido.finalizado_em > now() then
      raise exception 'Pedido finalizado sem data válida de finalização. Contate o suporte.';
    end if;

    if now() > v_pedido.finalizado_em + interval '24 hours' then
      raise exception 'Pedidos finalizados só podem ser cancelados nas primeiras 24 horas.';
    end if;
  end if;

  if v_pedido.pago then
    if v_decisao not in ('estornar', 'manter_recebido') then
      raise exception 'Escolha se o valor pago será estornado ou mantido.';
    end if;

    select m.* into v_receita
    from public.movimentacoes_financeiras m
    where m.pedido_id = v_pedido.id
      and m.origem = 'recebimento_pedido';

    if v_receita.id is null
       or v_receita.tipo <> 'receita'
       or v_receita.restaurante_id is distinct from v_pedido.restaurante_id
       or round(v_receita.valor, 2) is distinct from round(v_pedido.total, 2)
    then
      raise exception 'Pedido pago sem recebimento financeiro conciliado. Contate o suporte.';
    end if;

    if v_decisao = 'estornar' then
      perform set_config('eafmenu.via_movimento_pedido', 'true', true);

      insert into public.movimentacoes_financeiras
        (restaurante_id, tipo, origem, descricao, valor, pedido_id, criado_por, forma_pagamento)
      values (
        v_pedido.restaurante_id,
        'despesa',
        'estorno_pedido',
        case when v_pedido.numero_diario is not null
          then 'Estorno do pedido #' || v_pedido.numero_diario
          else 'Estorno do pedido #' || upper(substr(v_pedido.id::text, 1, 8))
        end,
        v_pedido.total,
        v_pedido.id,
        v_chamador.id,
        v_pedido.forma_pagamento
      )
      on conflict do nothing;

      select m.* into v_estorno
      from public.movimentacoes_financeiras m
      where m.pedido_id = v_pedido.id
        and m.origem = 'estorno_pedido';

      if v_estorno.id is null
         or v_estorno.tipo <> 'despesa'
         or v_estorno.restaurante_id is distinct from v_pedido.restaurante_id
         or round(v_estorno.valor, 2) is distinct from round(v_pedido.total, 2)
         or v_estorno.forma_pagamento is distinct from v_pedido.forma_pagamento
      then
        raise exception 'Falha ao conciliar o estorno financeiro do pedido.';
      end if;

      v_decisao_final := 'estornado';
    else
      v_decisao_final := 'mantido';
    end if;
  else
    v_decisao_final := 'nao_aplicavel';
  end if;

  perform set_config('eafmenu.via_cancelar_pedido', 'true', true);

  update public.pedidos p
  set status = 'cancelado',
      status_anterior = v_pedido.status,
      cancelado_em = now(),
      motivo_cancelamento = v_motivo,
      cancelado_por = v_chamador.id,
      cancelado_confirmado_por = v_confirmador_id,
      cancelamento_decisao_financeira = v_decisao_final,
      cancelamento_decisao_financeira_em = now(),
      cancelamento_decisao_financeira_por = v_confirmador_id
  where p.id = v_pedido.id
  returning * into v_pedido;

  return query select v_pedido.id, true, v_pedido.pago,
    v_pedido.cancelamento_decisao_financeira, v_estorno.id, false;
end;
$function$;

create or replace function public.cancelar_pedido(
  p_pedido_id uuid,
  p_motivo text,
  p_senha_confirmacao text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $function$
begin
  perform 1
  from public.cancelar_pedido_v2(
    p_pedido_id,
    p_motivo,
    p_senha_confirmacao,
    null
  );
  return true;
end;
$function$;

create or replace function public.resolver_cancelamento_financeiro_v1(
  p_pedido_id uuid,
  p_decisao_financeira text,
  p_senha_confirmacao text
)
returns table(
  pedido_id uuid,
  decisao_financeira text,
  estorno_movimentacao_id uuid,
  reutilizado boolean
)
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_chamador public.usuarios%rowtype;
  v_pedido public.pedidos%rowtype;
  v_confirmador_id uuid;
  v_senha_ok boolean := false;
  v_candidato record;
  v_decisao text := lower(btrim(coalesce(p_decisao_financeira, '')));
  v_decisao_final text;
  v_receita public.movimentacoes_financeiras%rowtype;
  v_estorno public.movimentacoes_financeiras%rowtype;
begin
  select * into v_chamador
  from public.usuarios u
  where u.id = auth.uid();

  if v_chamador.id is null
     or v_chamador.ativo is not true
     or v_chamador.role not in ('dono', 'gerente', 'atendente')
  then
    raise exception 'Você não tem permissão para resolver o cancelamento financeiro.';
  end if;

  if v_decisao not in ('estornar', 'manter_recebido') then
    raise exception 'Escolha se o valor pago será estornado ou mantido.';
  end if;

  if nullif(btrim(coalesce(p_senha_confirmacao, '')), '') is null then
    raise exception 'Informe a senha de confirmação.';
  end if;

  select * into v_pedido
  from public.pedidos p
  where p.id = p_pedido_id
  for update;

  if v_pedido.id is null
     or v_pedido.restaurante_id is distinct from v_chamador.restaurante_id
  then
    raise exception 'Pedido não encontrado nesse restaurante.';
  end if;

  if v_pedido.status <> 'cancelado' or not v_pedido.pago then
    raise exception 'Somente pedido cancelado e pago pode ter a decisão financeira resolvida.';
  end if;

  if v_chamador.role in ('dono', 'gerente') then
    select exists (
      select 1 from auth.users au
      where au.id = v_chamador.id
        and au.encrypted_password = extensions.crypt(p_senha_confirmacao, au.encrypted_password)
    ) into v_senha_ok;
    if v_senha_ok then v_confirmador_id := v_chamador.id; end if;
  else
    for v_candidato in
      select u.id, au.encrypted_password
      from public.usuarios u
      join auth.users au on au.id = u.id
      where u.restaurante_id = v_chamador.restaurante_id
        and u.role in ('dono', 'gerente')
        and u.ativo = true
    loop
      if v_candidato.encrypted_password = extensions.crypt(p_senha_confirmacao, v_candidato.encrypted_password) then
        v_confirmador_id := v_candidato.id;
        exit;
      end if;
    end loop;
    v_senha_ok := v_confirmador_id is not null;
  end if;

  if not v_senha_ok then
    raise exception 'Senha de confirmação incorreta.';
  end if;

  if v_pedido.cancelamento_decisao_financeira in ('estornado', 'mantido') then
    if (v_decisao = 'estornar' and v_pedido.cancelamento_decisao_financeira <> 'estornado')
       or (v_decisao = 'manter_recebido' and v_pedido.cancelamento_decisao_financeira <> 'mantido')
    then
      raise exception 'Este cancelamento já possui outra decisão financeira.';
    end if;

    select m.* into v_estorno
    from public.movimentacoes_financeiras m
    where m.pedido_id = v_pedido.id and m.origem = 'estorno_pedido';

    return query select v_pedido.id, v_pedido.cancelamento_decisao_financeira,
      v_estorno.id, true;
    return;
  end if;

  if v_pedido.cancelamento_decisao_financeira <> 'pendente' then
    raise exception 'Este cancelamento não possui decisão financeira pendente.';
  end if;

  select m.* into v_receita
  from public.movimentacoes_financeiras m
  where m.pedido_id = v_pedido.id
    and m.origem = 'recebimento_pedido';

  if v_receita.id is null
     or v_receita.tipo <> 'receita'
     or v_receita.restaurante_id is distinct from v_pedido.restaurante_id
     or round(v_receita.valor, 2) is distinct from round(v_pedido.total, 2)
  then
    raise exception 'Pedido pago sem recebimento financeiro conciliado. Contate o suporte.';
  end if;

  if v_decisao = 'estornar' then
    perform set_config('eafmenu.via_movimento_pedido', 'true', true);

    insert into public.movimentacoes_financeiras
      (restaurante_id, tipo, origem, descricao, valor, pedido_id, criado_por, forma_pagamento)
    values (
      v_pedido.restaurante_id,
      'despesa',
      'estorno_pedido',
      case when v_pedido.numero_diario is not null
        then 'Estorno do pedido #' || v_pedido.numero_diario
        else 'Estorno do pedido #' || upper(substr(v_pedido.id::text, 1, 8))
      end,
      v_pedido.total,
      v_pedido.id,
      v_chamador.id,
      v_pedido.forma_pagamento
    )
    on conflict do nothing;

    select m.* into v_estorno
    from public.movimentacoes_financeiras m
    where m.pedido_id = v_pedido.id
      and m.origem = 'estorno_pedido';

    if v_estorno.id is null
       or v_estorno.tipo <> 'despesa'
       or round(v_estorno.valor, 2) is distinct from round(v_pedido.total, 2)
    then
      raise exception 'Falha ao conciliar o estorno financeiro do pedido.';
    end if;

    v_decisao_final := 'estornado';
  else
    v_decisao_final := 'mantido';
  end if;

  perform set_config('eafmenu.via_resolver_cancelamento_financeiro', 'true', true);

  update public.pedidos p
  set cancelamento_decisao_financeira = v_decisao_final,
      cancelamento_decisao_financeira_em = now(),
      cancelamento_decisao_financeira_por = v_confirmador_id
  where p.id = v_pedido.id
  returning * into v_pedido;

  return query select v_pedido.id, v_pedido.cancelamento_decisao_financeira,
    v_estorno.id, false;
end;
$function$;

create or replace function public.relatorio_financeiro_v2(
  p_data_inicio date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_role public.user_role;
  v_restaurante_id uuid;
  v_local_ts timestamp;
  v_hoje date;
  v_vendido_pedidos integer := 0;
  v_vendido_valor numeric := 0;
  v_recebido_pedidos integer := 0;
  v_recebido_valor numeric := 0;
  v_recebido_bruto_pedidos integer := 0;
  v_recebido_bruto_valor numeric := 0;
  v_estornado_pedidos integer := 0;
  v_estornado_valor numeric := 0;
  v_pendente_pedidos integer := 0;
  v_pendente_valor numeric := 0;
  v_cancelados_pedidos integer := 0;
  v_cancelados_valor numeric := 0;
  v_cancelados_pagos_pendentes integer := 0;
  v_cancelados_pagos_pendentes_valor numeric := 0;
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
      into v_recebido_bruto_pedidos, v_recebido_bruto_valor
    from public.movimentacoes_financeiras mf
    join public.pedidos p on p.id = mf.pedido_id
    where mf.restaurante_id = v_restaurante_id
      and mf.origem = 'recebimento_pedido'
      and p.data_pedido between p_data_inicio and p_data_fim;

    select count(distinct mf.pedido_id)::integer, coalesce(sum(mf.valor), 0)
      into v_estornado_pedidos, v_estornado_valor
    from public.movimentacoes_financeiras mf
    join public.pedidos p on p.id = mf.pedido_id
    where mf.restaurante_id = v_restaurante_id
      and mf.origem = 'estorno_pedido'
      and p.data_pedido between p_data_inicio and p_data_fim;

    select count(distinct r.pedido_id)::integer,
           round(v_recebido_bruto_valor - v_estornado_valor, 2)
      into v_recebido_pedidos, v_recebido_valor
    from public.movimentacoes_financeiras r
    join public.pedidos p on p.id = r.pedido_id
    where r.restaurante_id = v_restaurante_id
      and r.origem = 'recebimento_pedido'
      and p.data_pedido between p_data_inicio and p_data_fim
      and not exists (
        select 1 from public.movimentacoes_financeiras e
        where e.pedido_id = r.pedido_id and e.origem = 'estorno_pedido'
      );

    select count(*)::integer, coalesce(sum(p.total), 0)
      into v_pendente_pedidos, v_pendente_valor
    from public.pedidos p
    where p.restaurante_id = v_restaurante_id
      and p.status in ('entregue', 'retirado')
      and p.data_pedido between p_data_inicio and p_data_fim
      and (
        p.pago = false
        or not exists (
          select 1 from public.movimentacoes_financeiras mf
          where mf.pedido_id = p.id and mf.origem = 'recebimento_pedido'
        )
      );

    select count(*)::integer, coalesce(sum(p.total), 0)
      into v_cancelados_pedidos, v_cancelados_valor
    from public.pedidos p
    where p.restaurante_id = v_restaurante_id
      and p.status = 'cancelado'
      and p.data_pedido between p_data_inicio and p_data_fim;

    select count(*)::integer, coalesce(sum(p.total), 0)
      into v_cancelados_pagos_pendentes, v_cancelados_pagos_pendentes_valor
    from public.pedidos p
    where p.restaurante_id = v_restaurante_id
      and p.status = 'cancelado'
      and p.pago = true
      and p.cancelamento_decisao_financeira = 'pendente'
      and p.data_pedido between p_data_inicio and p_data_fim;

    select coalesce(jsonb_object_agg(x.forma_pagamento, x.valor), '{}'::jsonb)
      into v_por_pagamento
    from (
      select forma_pagamento, sum(valor_assinado) as valor
      from (
        select coalesce(mf.forma_pagamento, 'nao_informado') as forma_pagamento,
               case when mf.origem = 'estorno_pedido' then -mf.valor else mf.valor end as valor_assinado
        from public.movimentacoes_financeiras mf
        join public.pedidos p on p.id = mf.pedido_id
        where mf.restaurante_id = v_restaurante_id
          and mf.origem in ('recebimento_pedido', 'estorno_pedido')
          and p.data_pedido between p_data_inicio and p_data_fim
      ) s
      group by forma_pagamento
      having sum(valor_assinado) <> 0
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
      'recebido_bruto', jsonb_build_object(
        'pedidos', v_recebido_bruto_pedidos,
        'valor', round(v_recebido_bruto_valor, 2)
      ),
      'estornado', jsonb_build_object(
        'pedidos', v_estornado_pedidos,
        'valor', round(v_estornado_valor, 2)
      ),
      'pendente', jsonb_build_object(
        'pedidos', v_pendente_pedidos,
        'valor', round(v_pendente_valor, 2)
      ),
      'cancelamentos_pagos_pendentes', jsonb_build_object(
        'pedidos', v_cancelados_pagos_pendentes,
        'valor', round(v_cancelados_pagos_pendentes_valor, 2)
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
$function$;

revoke all on function public.cancelar_pedido_v2(uuid, text, text, text) from public, anon;
grant execute on function public.cancelar_pedido_v2(uuid, text, text, text) to authenticated;

revoke all on function public.resolver_cancelamento_financeiro_v1(uuid, text, text) from public, anon;
grant execute on function public.resolver_cancelamento_financeiro_v1(uuid, text, text) to authenticated;

revoke all on function public.cancelar_pedido(uuid, text, text) from public, anon;
grant execute on function public.cancelar_pedido(uuid, text, text) to authenticated;

revoke all on function public.relatorio_financeiro_v2(date, date) from public, anon;
grant execute on function public.relatorio_financeiro_v2(date, date) to authenticated;

do $validation$
declare
  v_receitas integer;
  v_receitas_origem integer;
  v_cancelados_pagos integer;
  v_cancelados_pendentes integer;
  v_unique_receita boolean;
  v_unique_estorno boolean;
begin
  select count(*) into v_receitas
  from public.movimentacoes_financeiras
  where pedido_id is not null and tipo = 'receita';

  select count(*) into v_receitas_origem
  from public.movimentacoes_financeiras
  where pedido_id is not null and tipo = 'receita' and origem = 'recebimento_pedido';

  if v_receitas <> v_receitas_origem then
    raise exception 'Existem receitas de pedido sem origem financeira canônica.';
  end if;

  select count(*) into v_cancelados_pagos
  from public.pedidos where status = 'cancelado' and pago = true;

  select count(*) into v_cancelados_pendentes
  from public.pedidos
  where status = 'cancelado' and pago = true
    and cancelamento_decisao_financeira = 'pendente';

  if v_cancelados_pagos <> v_cancelados_pendentes then
    raise exception 'Cancelamentos pagos legados não foram marcados como pendentes de decisão.';
  end if;

  select exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'movimentacoes_recebimento_pedido_uidx'
  ) into v_unique_receita;

  select exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'movimentacoes_estorno_pedido_uidx'
  ) into v_unique_estorno;

  if not v_unique_receita or not v_unique_estorno then
    raise exception 'Índices financeiros idempotentes não foram criados.';
  end if;
end;
$validation$;