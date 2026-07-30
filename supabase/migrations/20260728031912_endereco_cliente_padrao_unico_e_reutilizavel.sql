create unique index if not exists enderecos_cliente_um_padrao_por_cliente
  on public.enderecos_cliente (cliente_id)
  where padrao = true;

create or replace function public.normalizar_campo_endereco(p_valor text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select lower(regexp_replace(btrim(coalesce(p_valor, '')), '[[:space:]]+', ' ', 'g'));
$$;

create or replace function public._salvar_endereco_cliente_transacional(
  p_cliente_id uuid,
  p_restaurante_id uuid,
  p_endereco jsonb,
  p_cliente_sessao_auth_user_id uuid default null,
  p_cliente_sessao_dia_comercial date default null
)
returns table(endereco_id uuid, reutilizado boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_cliente public.clientes%rowtype;
  v_existente public.enderecos_cliente%rowtype;
  v_logradouro text;
  v_numero text;
  v_bairro text;
  v_cidade text;
  v_complemento text;
  v_referencia text;
begin
  if p_cliente_id is null or p_restaurante_id is null then
    raise exception 'Cliente ou restaurante inválido para salvar endereço.';
  end if;

  if p_endereco is null or jsonb_typeof(p_endereco) <> 'object' then
    raise exception 'Endereço inválido.';
  end if;

  select c.* into v_cliente
  from public.clientes c
  where c.id = p_cliente_id
  for update;

  if v_cliente.id is null
     or v_cliente.restaurante_id is distinct from p_restaurante_id then
    raise exception 'Cliente não pertence a este restaurante.';
  end if;

  v_logradouro := btrim(coalesce(p_endereco->>'logradouro', p_endereco->>'rua', ''));
  v_numero := btrim(coalesce(p_endereco->>'numero', ''));
  v_bairro := btrim(coalesce(p_endereco->>'bairro', ''));
  v_cidade := nullif(btrim(coalesce(p_endereco->>'cidade', '')), '');
  v_complemento := nullif(btrim(coalesce(p_endereco->>'complemento', '')), '');
  v_referencia := nullif(btrim(coalesce(p_endereco->>'referencia', '')), '');

  if v_logradouro = '' or v_numero = '' or v_bairro = '' then
    raise exception 'Endereço incompleto. Informe rua, número e bairro.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('endereco-cliente:' || p_cliente_id::text, 0)
  );

  select e.* into v_existente
  from public.enderecos_cliente e
  where e.cliente_id = p_cliente_id
    and public.normalizar_campo_endereco(e.logradouro) = public.normalizar_campo_endereco(v_logradouro)
    and public.normalizar_campo_endereco(e.numero) = public.normalizar_campo_endereco(v_numero)
    and public.normalizar_campo_endereco(e.bairro) = public.normalizar_campo_endereco(v_bairro)
    and public.normalizar_campo_endereco(e.cidade) = public.normalizar_campo_endereco(v_cidade)
    and public.normalizar_campo_endereco(e.complemento) = public.normalizar_campo_endereco(v_complemento)
    and public.normalizar_campo_endereco(e.referencia) = public.normalizar_campo_endereco(v_referencia)
  order by e.padrao desc,
           (select max(p.criado_em) from public.pedidos p where p.endereco_entrega_id = e.id) desc nulls last,
           e.id
  limit 1
  for update;

  update public.enderecos_cliente e
  set padrao = false
  where e.cliente_id = p_cliente_id
    and e.padrao = true
    and (v_existente.id is null or e.id <> v_existente.id);

  if v_existente.id is not null then
    update public.enderecos_cliente e
    set logradouro = v_logradouro,
        numero = v_numero,
        bairro = v_bairro,
        cidade = v_cidade,
        complemento = v_complemento,
        referencia = v_referencia,
        padrao = true,
        cliente_sessao_auth_user_id = coalesce(p_cliente_sessao_auth_user_id, e.cliente_sessao_auth_user_id),
        cliente_sessao_dia_comercial = coalesce(p_cliente_sessao_dia_comercial, e.cliente_sessao_dia_comercial)
    where e.id = v_existente.id;

    return query select v_existente.id, true;
    return;
  end if;

  insert into public.enderecos_cliente(
    cliente_id,
    cliente_sessao_auth_user_id,
    cliente_sessao_dia_comercial,
    logradouro,
    numero,
    bairro,
    cidade,
    complemento,
    referencia,
    padrao
  ) values (
    p_cliente_id,
    p_cliente_sessao_auth_user_id,
    p_cliente_sessao_dia_comercial,
    v_logradouro,
    v_numero,
    v_bairro,
    v_cidade,
    v_complemento,
    v_referencia,
    true
  ) returning id into endereco_id;

  reutilizado := false;
  return next;
end;
$$;

revoke all on function public._salvar_endereco_cliente_transacional(uuid, uuid, jsonb, uuid, date)
  from public, anon, authenticated, service_role;

create or replace function public.salvar_endereco_cliente(
  p_cliente_id uuid,
  p_restaurante_id uuid,
  p_endereco jsonb
)
returns table(endereco_id uuid, reutilizado boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_usuario public.usuarios%rowtype;
  v_sessao public.cliente_sessoes%rowtype;
begin
  if v_uid is null then
    raise exception using message = 'Sessão inválida.', errcode = '28000';
  end if;

  select u.* into v_usuario
  from public.usuarios u
  where u.id = v_uid
    and u.ativo = true;

  if v_usuario.id is not null
     and v_usuario.role in ('dono', 'gerente', 'atendente')
  then
    if v_usuario.restaurante_id is distinct from p_restaurante_id then
      raise exception 'Restaurante inválido para o usuário atual.';
    end if;

    return query
    select * from public._salvar_endereco_cliente_transacional(
      p_cliente_id,
      p_restaurante_id,
      p_endereco,
      null,
      null
    );
    return;
  end if;

  select cs.* into v_sessao
  from public.cliente_sessoes cs
  where cs.auth_user_id = v_uid
    and cs.restaurante_id = p_restaurante_id
    and cs.cliente_id = p_cliente_id
    and cs.dia_comercial = public.dia_comercial_atual();

  if v_sessao.auth_user_id is null then
    raise exception using message = 'Cliente não pertence à sessão atual.', errcode = '42501';
  end if;

  return query
  select * from public._salvar_endereco_cliente_transacional(
    p_cliente_id,
    p_restaurante_id,
    p_endereco,
    v_uid,
    v_sessao.dia_comercial
  );
end;
$$;

revoke all on function public.salvar_endereco_cliente(uuid, uuid, jsonb) from public, anon;
grant execute on function public.salvar_endereco_cliente(uuid, uuid, jsonb)
  to authenticated, service_role;

alter function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
  rename to _criar_pedido_cliente_v1_impl_endereco_seguro;

revoke all on function public._criar_pedido_cliente_v1_impl_endereco_seguro(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
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
  v_uid uuid := auth.uid();
  v_sessao public.cliente_sessoes%rowtype;
begin
  if p_tipo = 'entrega' then
    select cs.* into v_sessao
    from public.cliente_sessoes cs
    where cs.auth_user_id = v_uid
      and cs.restaurante_id = p_restaurante_id
      and cs.dia_comercial = public.dia_comercial_atual();

    if v_sessao.auth_user_id is null then
      raise exception using message = 'Identificação do cliente expirada.', errcode = '28000';
    end if;

    perform 1
    from public._salvar_endereco_cliente_transacional(
      v_sessao.cliente_id,
      p_restaurante_id,
      p_endereco,
      v_uid,
      v_sessao.dia_comercial
    );
  end if;

  return query
  select *
  from public._criar_pedido_cliente_v1_impl_endereco_seguro(
    p_restaurante_id,
    p_tipo,
    p_forma_pagamento,
    p_troco_para,
    p_endereco,
    p_itens,
    p_chave_idempotencia
  );
end;
$$;

revoke all on function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
  from public, anon;
grant execute on function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text)
  to authenticated, service_role;

alter function public.criar_pedido_manual_v1(uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text)
  rename to _criar_pedido_manual_v1_impl_endereco_seguro;

revoke all on function public._criar_pedido_manual_v1_impl_endereco_seguro(uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text)
  from public, anon, authenticated, service_role;

create or replace function public.criar_pedido_manual_v1(
  p_restaurante_id uuid,
  p_nome_cliente text,
  p_telefone_cliente text,
  p_tipo public.tipo_pedido,
  p_forma_pagamento text,
  p_troco_para numeric,
  p_observacoes text,
  p_endereco jsonb,
  p_itens jsonb,
  p_desconto jsonb,
  p_senha_autorizador text,
  p_chave_idempotencia text
)
returns table(pedido_id uuid, numero_diario integer, total numeric, reutilizado boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_resultado record;
  v_cliente_id uuid;
  v_endereco_anterior_id uuid;
  v_endereco_canonico_id uuid;
begin
  select * into v_resultado
  from public._criar_pedido_manual_v1_impl_endereco_seguro(
    p_restaurante_id,
    p_nome_cliente,
    p_telefone_cliente,
    p_tipo,
    p_forma_pagamento,
    p_troco_para,
    p_observacoes,
    p_endereco,
    p_itens,
    p_desconto,
    p_senha_autorizador,
    p_chave_idempotencia
  );

  if p_tipo = 'entrega' then
    select p.cliente_id, p.endereco_entrega_id
      into v_cliente_id, v_endereco_anterior_id
    from public.pedidos p
    where p.id = v_resultado.pedido_id
    for update;

    select s.endereco_id into v_endereco_canonico_id
    from public._salvar_endereco_cliente_transacional(
      v_cliente_id,
      p_restaurante_id,
      p_endereco,
      null,
      null
    ) s;

    if v_endereco_canonico_id is distinct from v_endereco_anterior_id then
      update public.pedidos p
      set endereco_entrega_id = v_endereco_canonico_id
      where p.id = v_resultado.pedido_id;

      delete from public.enderecos_cliente e
      where e.id = v_endereco_anterior_id
        and e.id <> v_endereco_canonico_id
        and not exists (
          select 1 from public.pedidos p where p.endereco_entrega_id = e.id
        );
    end if;
  end if;

  return query
  select v_resultado.pedido_id,
         v_resultado.numero_diario,
         v_resultado.total,
         v_resultado.reutilizado;
end;
$$;

revoke all on function public.criar_pedido_manual_v1(uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text)
  from public, anon;
grant execute on function public.criar_pedido_manual_v1(uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text)
  to authenticated, service_role;

comment on index public.enderecos_cliente_um_padrao_por_cliente is
  'Garante no máximo um endereço padrão por cliente, inclusive sob concorrência.';
comment on function public.salvar_endereco_cliente(uuid, uuid, jsonb) is
  'Salva ou reutiliza endereço do cliente com validação de sessão/tenant e troca atômica do endereço padrão.';