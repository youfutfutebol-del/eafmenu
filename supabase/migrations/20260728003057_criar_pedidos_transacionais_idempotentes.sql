alter table public.pedidos
  add column origem_criacao text,
  add column chave_idempotencia text,
  add column conteudo_idempotencia jsonb;

alter table public.pedidos
  add constraint chk_pedido_idempotencia_completa check (
    (origem_criacao is null and chave_idempotencia is null and conteudo_idempotencia is null)
    or (
      origem_criacao in ('cliente', 'manual')
      and nullif(btrim(chave_idempotencia), '') is not null
      and conteudo_idempotencia is not null
    )
  );

create unique index pedidos_idempotencia_uidx
  on public.pedidos (restaurante_id, origem_criacao, chave_idempotencia)
  where chave_idempotencia is not null;

create or replace function public._inserir_itens_pedido_transacional(
  p_pedido_id uuid,
  p_itens jsonb
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_item jsonb;
  v_sabor text;
  v_sabores jsonb;
  v_item_id uuid;
  v_produto_id uuid;
  v_opcao_tamanho_id uuid;
  v_quantidade integer;
  v_preco numeric;
  v_qtd_sabores integer;
  v_qtd_sabores_unicos integer;
  v_qtd_itens integer := 0;
  v_pendentes integer;
begin
  if p_pedido_id is null then
    raise exception 'Pedido inválido.';
  end if;

  if p_itens is null or jsonb_typeof(p_itens) <> 'array'
     or jsonb_array_length(p_itens) = 0
     or jsonb_array_length(p_itens) > 100 then
    raise exception 'Informe entre 1 e 100 itens válidos.';
  end if;

  for v_item in select value from jsonb_array_elements(p_itens)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'Item do pedido inválido.';
    end if;

    begin
      v_produto_id := nullif(v_item->>'produto_id', '')::uuid;
      v_opcao_tamanho_id := nullif(v_item->>'opcao_tamanho_id', '')::uuid;
      v_quantidade := (v_item->>'quantidade')::integer;
      v_preco := (v_item->>'preco_unitario')::numeric;
    exception when others then
      raise exception 'Item do pedido possui campos inválidos.';
    end;

    v_sabores := v_item->'sabores_ids';

    if v_produto_id is null
       or v_quantidade is null or v_quantidade < 1 or v_quantidade > 1000
       or v_preco is null or v_preco = 'NaN'::numeric or v_preco <= 0
       or v_sabores is null or jsonb_typeof(v_sabores) <> 'array'
       or jsonb_array_length(v_sabores) < 1 then
      raise exception 'Item do pedido inválido.';
    end if;

    select count(*)::integer, count(distinct value)::integer
      into v_qtd_sabores, v_qtd_sabores_unicos
    from jsonb_array_elements_text(v_sabores);

    if v_qtd_sabores <> v_qtd_sabores_unicos
       or not (v_sabores ? v_produto_id::text) then
      raise exception 'Sabores do item inválidos.';
    end if;

    insert into public.itens_pedido(
      pedido_id,
      produto_id,
      opcao_tamanho_id,
      quantidade,
      preco_unitario,
      observacoes,
      sabores_esperados
    ) values (
      p_pedido_id,
      v_produto_id,
      v_opcao_tamanho_id,
      v_quantidade,
      round(v_preco, 2),
      nullif(btrim(coalesce(v_item->>'observacoes', '')), ''),
      v_qtd_sabores
    )
    returning id into v_item_id;

    if v_qtd_sabores > 1 then
      for v_sabor in select value from jsonb_array_elements_text(v_sabores)
      loop
        insert into public.itens_pedido_sabores(
          item_pedido_id,
          produto_id,
          preco_unitario,
          preco_original_unitario
        ) values (
          v_item_id,
          v_sabor::uuid,
          round(v_preco, 2),
          round(v_preco, 2)
        );
      end loop;
    end if;

    v_qtd_itens := v_qtd_itens + 1;
  end loop;

  select count(*) filter (where precificacao_finalizada_em is null)::integer
    into v_pendentes
  from public.itens_pedido
  where pedido_id = p_pedido_id;

  if v_qtd_itens = 0 or v_pendentes > 0 then
    raise exception 'Pedido permaneceu com item sem precificação finalizada.';
  end if;
end;
$$;

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
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_sessao public.cliente_sessoes%rowtype;
  v_chave text := btrim(coalesce(p_chave_idempotencia, ''));
  v_forma text := lower(btrim(coalesce(p_forma_pagamento, '')));
  v_payload jsonb;
  v_existente public.pedidos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_endereco_id uuid;
  v_logradouro text;
  v_numero text;
  v_bairro text;
  v_cidade text;
  v_complemento text;
  v_referencia text;
  v_total numeric;
begin
  if v_uid is null then
    raise exception using message = 'Sessão inválida.', errcode = '28000';
  end if;

  if p_restaurante_id is null or p_tipo not in ('entrega', 'retirada') then
    raise exception 'Dados do pedido inválidos.';
  end if;

  if v_forma not in ('dinheiro', 'pix', 'cartao') then
    raise exception 'Forma de pagamento inválida.';
  end if;

  if length(v_chave) < 16 or length(v_chave) > 200 then
    raise exception 'Chave de idempotência inválida.';
  end if;

  if p_troco_para is not null and (p_troco_para = 'NaN'::numeric or p_troco_para < 0) then
    raise exception 'Valor para troco inválido.';
  end if;

  select cs.* into v_sessao
  from public.cliente_sessoes cs
  where cs.auth_user_id = v_uid
    and cs.restaurante_id = p_restaurante_id
    and cs.dia_comercial = public.dia_comercial_atual();

  if v_sessao.auth_user_id is null then
    raise exception using message = 'Identificação do cliente expirada.', errcode = '28000';
  end if;

  if p_tipo <> 'entrega' and p_endereco is not null then
    p_endereco := null;
  end if;

  v_payload := jsonb_build_object(
    'cliente_id', v_sessao.cliente_id,
    'auth_user_id', v_uid,
    'dia_comercial', v_sessao.dia_comercial,
    'tipo', p_tipo,
    'forma_pagamento', v_forma,
    'troco_para', p_troco_para,
    'endereco', p_endereco,
    'itens', p_itens
  );

  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'pedido:cliente:' || p_restaurante_id::text || ':' || v_chave, 0
  ));

  select p.* into v_existente
  from public.pedidos p
  where p.restaurante_id = p_restaurante_id
    and p.origem_criacao = 'cliente'
    and p.chave_idempotencia = v_chave;

  if v_existente.id is not null then
    if v_existente.conteudo_idempotencia is distinct from v_payload then
      raise exception 'Chave de idempotência reutilizada com conteúdo diferente.';
    end if;
    if not exists (select 1 from public.itens_pedido ip where ip.pedido_id = v_existente.id)
       or exists (select 1 from public.itens_pedido ip where ip.pedido_id = v_existente.id and ip.precificacao_finalizada_em is null) then
      raise exception 'Pedido idempotente existente está incompleto.';
    end if;
    return query select v_existente.id, v_existente.numero_diario, v_existente.total, true;
    return;
  end if;

  if p_tipo = 'entrega' then
    if p_endereco is null or jsonb_typeof(p_endereco) <> 'object' then
      raise exception 'Endereço obrigatório para entrega.';
    end if;

    v_logradouro := btrim(coalesce(p_endereco->>'logradouro', p_endereco->>'rua', ''));
    v_numero := btrim(coalesce(p_endereco->>'numero', ''));
    v_bairro := btrim(coalesce(p_endereco->>'bairro', ''));
    v_cidade := btrim(coalesce(p_endereco->>'cidade', ''));
    v_complemento := nullif(btrim(coalesce(p_endereco->>'complemento', '')), '');
    v_referencia := nullif(btrim(coalesce(p_endereco->>'referencia', '')), '');

    if v_logradouro = '' or v_numero = '' or v_bairro = '' or v_cidade = '' then
      raise exception 'Endereço incompleto para entrega.';
    end if;

    select e.id into v_endereco_id
    from public.enderecos_cliente e
    where e.cliente_id = v_sessao.cliente_id
      and btrim(e.logradouro) = v_logradouro
      and btrim(coalesce(e.numero, '')) = v_numero
      and btrim(coalesce(e.bairro, '')) = v_bairro
      and btrim(coalesce(e.cidade, '')) = v_cidade
      and btrim(coalesce(e.complemento, '')) = coalesce(v_complemento, '')
      and btrim(coalesce(e.referencia, '')) = coalesce(v_referencia, '')
    order by e.padrao desc, e.id
    limit 1;

    if v_endereco_id is null then
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
        v_sessao.cliente_id,
        v_uid,
        v_sessao.dia_comercial,
        v_logradouro,
        v_numero,
        v_bairro,
        v_cidade,
        v_complemento,
        v_referencia,
        not exists (select 1 from public.enderecos_cliente e where e.cliente_id = v_sessao.cliente_id)
      ) returning id into v_endereco_id;
    end if;
  end if;

  insert into public.pedidos(
    restaurante_id,
    cliente_id,
    tipo,
    forma_pagamento,
    status,
    pago,
    endereco_entrega_id,
    troco_para,
    cliente_sessao_auth_user_id,
    cliente_sessao_dia_comercial,
    origem_criacao,
    chave_idempotencia,
    conteudo_idempotencia
  ) values (
    p_restaurante_id,
    v_sessao.cliente_id,
    p_tipo,
    v_forma,
    'recebido',
    false,
    v_endereco_id,
    null,
    v_uid,
    v_sessao.dia_comercial,
    'cliente',
    v_chave,
    v_payload
  ) returning * into v_pedido;

  perform public._inserir_itens_pedido_transacional(v_pedido.id, p_itens);

  select p.total into v_total from public.pedidos p where p.id = v_pedido.id for update;
  if v_total is null or v_total <= 0 then
    raise exception 'Total final do pedido inválido.';
  end if;

  if v_forma <> 'dinheiro' and p_troco_para is not null then
    raise exception 'Troco só pode ser informado para pagamento em dinheiro.';
  end if;
  if p_troco_para is not null and round(p_troco_para, 2) < round(v_total, 2) then
    raise exception 'Valor para troco menor que o total do pedido.';
  end if;

  if p_troco_para is not null then
    update public.pedidos set troco_para = round(p_troco_para, 2) where id = v_pedido.id;
  end if;

  select p.* into v_pedido from public.pedidos p where p.id = v_pedido.id;
  return query select v_pedido.id, v_pedido.numero_diario, v_pedido.total, false;
end;
$$;

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
set search_path to 'pg_catalog', 'public', 'extensions'
as $$
declare
  v_uid uuid := auth.uid();
  v_usuario public.usuarios%rowtype;
  v_cliente public.clientes%rowtype;
  v_nome text := btrim(coalesce(p_nome_cliente, ''));
  v_telefone text := regexp_replace(coalesce(p_telefone_cliente, ''), '[^0-9]', '', 'g');
  v_chave text := btrim(coalesce(p_chave_idempotencia, ''));
  v_forma text := lower(btrim(coalesce(p_forma_pagamento, '')));
  v_payload jsonb;
  v_existente public.pedidos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_endereco_id uuid;
  v_logradouro text;
  v_numero text;
  v_bairro text;
  v_cidade text;
  v_complemento text;
  v_referencia text;
  v_total numeric;
  v_desconto_tipo text;
  v_desconto_valor numeric;
  v_desconto_motivo text;
  v_desconto_autorizado_por uuid;
begin
  if v_uid is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select u.* into v_usuario from public.usuarios u where u.id = v_uid;
  if v_usuario.id is null or v_usuario.ativo is not true
     or v_usuario.role not in ('dono', 'gerente', 'atendente') then
    raise exception 'Usuário não autorizado a criar pedido manual.';
  end if;

  if p_restaurante_id is null or p_restaurante_id <> v_usuario.restaurante_id then
    raise exception 'Restaurante inválido para o usuário atual.';
  end if;

  if v_nome = '' or p_tipo not in ('entrega', 'retirada') then
    raise exception 'Dados do pedido manual inválidos.';
  end if;

  if v_forma not in ('dinheiro', 'pix', 'cartao') then
    raise exception 'Forma de pagamento inválida.';
  end if;

  if length(v_chave) < 16 or length(v_chave) > 200 then
    raise exception 'Chave de idempotência inválida.';
  end if;

  if p_troco_para is not null and (p_troco_para = 'NaN'::numeric or p_troco_para < 0) then
    raise exception 'Valor para troco inválido.';
  end if;

  if p_tipo <> 'entrega' and p_endereco is not null then
    p_endereco := null;
  end if;

  v_payload := jsonb_build_object(
    'usuario_id', v_uid,
    'nome_cliente', v_nome,
    'telefone_cliente', nullif(v_telefone, ''),
    'tipo', p_tipo,
    'forma_pagamento', v_forma,
    'troco_para', p_troco_para,
    'observacoes', nullif(btrim(coalesce(p_observacoes, '')), ''),
    'endereco', p_endereco,
    'itens', p_itens,
    'desconto', p_desconto
  );

  perform pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'pedido:manual:' || p_restaurante_id::text || ':' || v_chave, 0
  ));

  select p.* into v_existente
  from public.pedidos p
  where p.restaurante_id = p_restaurante_id
    and p.origem_criacao = 'manual'
    and p.chave_idempotencia = v_chave;

  if v_existente.id is not null then
    if v_existente.conteudo_idempotencia is distinct from v_payload then
      raise exception 'Chave de idempotência reutilizada com conteúdo diferente.';
    end if;
    if not exists (select 1 from public.itens_pedido ip where ip.pedido_id = v_existente.id)
       or exists (select 1 from public.itens_pedido ip where ip.pedido_id = v_existente.id and ip.precificacao_finalizada_em is null) then
      raise exception 'Pedido idempotente existente está incompleto.';
    end if;
    return query select v_existente.id, v_existente.numero_diario, v_existente.total, true;
    return;
  end if;

  if v_telefone <> '' then
    perform pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'cliente-telefone:' || p_restaurante_id::text || ':' || v_telefone, 0
    ));

    select c.* into v_cliente
    from public.clientes c
    where c.restaurante_id = p_restaurante_id and c.telefone = v_telefone
    for update;
  end if;

  if v_cliente.id is null then
    insert into public.clientes(nome, telefone, restaurante_id, auth_user_id)
    values (v_nome, nullif(v_telefone, ''), p_restaurante_id, null)
    returning * into v_cliente;
  elsif v_cliente.nome is distinct from v_nome then
    update public.clientes set nome = v_nome where id = v_cliente.id returning * into v_cliente;
  end if;

  if p_tipo = 'entrega' then
    if p_endereco is null or jsonb_typeof(p_endereco) <> 'object' then
      raise exception 'Endereço obrigatório para entrega.';
    end if;

    v_logradouro := btrim(coalesce(p_endereco->>'logradouro', p_endereco->>'rua', ''));
    v_numero := btrim(coalesce(p_endereco->>'numero', ''));
    v_bairro := btrim(coalesce(p_endereco->>'bairro', ''));
    v_cidade := nullif(btrim(coalesce(p_endereco->>'cidade', '')), '');
    v_complemento := nullif(btrim(coalesce(p_endereco->>'complemento', '')), '');
    v_referencia := nullif(btrim(coalesce(p_endereco->>'referencia', '')), '');

    if v_logradouro = '' or v_numero = '' or v_bairro = '' then
      raise exception 'Endereço incompleto para entrega.';
    end if;

    select e.id into v_endereco_id
    from public.enderecos_cliente e
    where e.cliente_id = v_cliente.id
      and btrim(e.logradouro) = v_logradouro
      and btrim(coalesce(e.numero, '')) = v_numero
      and btrim(coalesce(e.bairro, '')) = v_bairro
      and btrim(coalesce(e.cidade, '')) = coalesce(v_cidade, '')
      and btrim(coalesce(e.complemento, '')) = coalesce(v_complemento, '')
      and btrim(coalesce(e.referencia, '')) = coalesce(v_referencia, '')
    order by e.padrao desc, e.id
    limit 1;

    if v_endereco_id is null then
      insert into public.enderecos_cliente(
        cliente_id, logradouro, numero, bairro, cidade, complemento, referencia, padrao
      ) values (
        v_cliente.id, v_logradouro, v_numero, v_bairro, v_cidade, v_complemento, v_referencia,
        not exists (select 1 from public.enderecos_cliente e where e.cliente_id = v_cliente.id)
      ) returning id into v_endereco_id;
    end if;
  end if;

  insert into public.pedidos(
    restaurante_id,
    cliente_id,
    tipo,
    forma_pagamento,
    status,
    pago,
    endereco_entrega_id,
    troco_para,
    observacoes,
    origem_criacao,
    chave_idempotencia,
    conteudo_idempotencia
  ) values (
    p_restaurante_id,
    v_cliente.id,
    p_tipo,
    v_forma,
    'recebido',
    false,
    v_endereco_id,
    null,
    nullif(btrim(coalesce(p_observacoes, '')), ''),
    'manual',
    v_chave,
    v_payload
  ) returning * into v_pedido;

  perform public._inserir_itens_pedido_transacional(v_pedido.id, p_itens);

  if p_desconto is not null and p_desconto <> '{}'::jsonb then
    v_desconto_tipo := nullif(btrim(coalesce(p_desconto->>'tipo', '')), '');
    v_desconto_valor := nullif(p_desconto->>'valor', '')::numeric;
    v_desconto_motivo := nullif(btrim(coalesce(p_desconto->>'motivo', '')), '');
    v_desconto_autorizado_por := nullif(p_desconto->>'autorizado_por', '')::uuid;

    perform public.aplicar_desconto_manual_v2(
      v_pedido.id,
      v_desconto_tipo,
      v_desconto_valor,
      v_desconto_motivo,
      v_desconto_autorizado_por,
      p_senha_autorizador
    );
  end if;

  select p.total into v_total from public.pedidos p where p.id = v_pedido.id for update;
  if v_total is null or v_total <= 0 then
    raise exception 'Total final do pedido inválido.';
  end if;

  if v_forma <> 'dinheiro' and p_troco_para is not null then
    raise exception 'Troco só pode ser informado para pagamento em dinheiro.';
  end if;
  if p_troco_para is not null and round(p_troco_para, 2) < round(v_total, 2) then
    raise exception 'Valor para troco menor que o total do pedido.';
  end if;

  if p_troco_para is not null then
    update public.pedidos set troco_para = round(p_troco_para, 2) where id = v_pedido.id;
  end if;

  select p.* into v_pedido from public.pedidos p where p.id = v_pedido.id;
  return query select v_pedido.id, v_pedido.numero_diario, v_pedido.total, false;
end;
$$;

revoke all on function public._inserir_itens_pedido_transacional(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text) from public, anon;
grant execute on function public.criar_pedido_cliente_v1(uuid, public.tipo_pedido, text, numeric, jsonb, jsonb, text) to authenticated;
revoke all on function public.criar_pedido_manual_v1(uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text) from public, anon;
grant execute on function public.criar_pedido_manual_v1(uuid, text, text, public.tipo_pedido, text, numeric, text, jsonb, jsonb, jsonb, text, text) to authenticated;