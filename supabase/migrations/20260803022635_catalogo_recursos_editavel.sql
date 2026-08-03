-- Catálogo totalmente editável de recursos, administrado exclusivamente por RPCs.

update public.recursos
set ordem = case codigo
  when 'pedido_manual' then 32000
  when 'app_motoboy' then 32001
end,
atualizado_em = now()
where codigo in ('pedido_manual', 'app_motoboy');

insert into public.recursos (codigo, nome, descricao, ordem, ativo)
values
  ('cardapio_online', 'Cardápio Online', 'Página pública para clientes consultarem o cardápio e enviarem pedidos.', 1, true),
  ('painel_pedidos', 'Painel de Pedidos', 'Monitor em tempo real para receber e acompanhar pedidos.', 2, true),
  ('produtos', 'Gestão de Produtos', 'Cadastro, preços, imagens e disponibilidade dos produtos.', 4, true),
  ('categorias', 'Gestão de Categorias', 'Organização das categorias e da ordem do cardápio.', 5, true),
  ('promocoes', 'Promoções', 'Criação e gerenciamento de campanhas promocionais.', 6, true),
  ('clientes', 'Gestão de Clientes', 'Base de clientes, dados de contato e histórico de compras.', 7, true),
  ('caixa', 'Caixa', 'Abertura, fechamento, despesas e movimentações financeiras.', 8, true),
  ('relatorio_financeiro', 'Relatório Financeiro', 'Indicadores, cancelamentos, formas de pagamento e exportação.', 9, true),
  ('gestao_equipe', 'Gestão de Equipe', 'Cadastro de usuários, cargos, acessos e redefinição de senhas.', 10, true),
  ('personalizacao_marca', 'Personalização da Marca', 'Identidade visual e configurações públicas do restaurante.', 11, true);

update public.recursos
set nome = case codigo
    when 'pedido_manual' then 'Pedido Manual'
    when 'app_motoboy' then 'App do Motoboy'
  end,
  descricao = case codigo
    when 'pedido_manual' then 'Criação de pedidos pela equipe do restaurante.'
    when 'app_motoboy' then 'Cadastro de entregadores, acesso ao aplicativo e operações de entrega.'
  end,
  ordem = case codigo
    when 'pedido_manual' then 3
    when 'app_motoboy' then 12
  end,
  ativo = true,
  atualizado_em = now()
where codigo in ('pedido_manual', 'app_motoboy');

insert into public.plano_recursos (
  plano_codigo, recurso_codigo, incluido, atualizado_em, atualizado_por
)
select p.codigo, r.codigo, true, now(), null
from public.planos p
cross join public.recursos r
where r.codigo in (
  'cardapio_online', 'painel_pedidos', 'produtos', 'categorias', 'promocoes',
  'clientes', 'caixa', 'relatorio_financeiro', 'gestao_equipe', 'personalizacao_marca'
)
on conflict on constraint plano_recursos_pkey do nothing;

create function public.super_admin_listar_catalogo_recursos()
returns table (
  codigo text,
  nome text,
  descricao text,
  ordem smallint,
  ativo boolean,
  criado_em timestamptz,
  atualizado_em timestamptz,
  planos_incluidos text[],
  quantidade_planos_incluidos bigint,
  quantidade_liberacoes bigint,
  quantidade_bloqueios bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using
      message = 'Apenas administradores da plataforma podem listar o catálogo de recursos.',
      errcode = '42501';
  end if;

  return query
  select
    r.codigo,
    r.nome,
    r.descricao,
    r.ordem,
    r.ativo,
    r.criado_em,
    r.atualizado_em,
    coalesce(m.planos_incluidos, array[]::text[]),
    coalesce(m.quantidade_planos_incluidos, 0),
    coalesce(e.quantidade_liberacoes, 0),
    coalesce(e.quantidade_bloqueios, 0)
  from public.recursos r
  left join lateral (
    select array_agg(p.nome order by p.ordem) as planos_incluidos,
           count(*) as quantidade_planos_incluidos
    from public.plano_recursos pr
    join public.planos p on p.codigo = pr.plano_codigo
    where pr.recurso_codigo = r.codigo and pr.incluido
  ) m on true
  left join lateral (
    select count(*) filter (where rr.decisao = 'liberar') as quantidade_liberacoes,
           count(*) filter (where rr.decisao = 'bloquear') as quantidade_bloqueios
    from public.restaurante_recursos rr
    where rr.recurso_codigo = r.codigo
  ) e on true
  order by r.ordem;
end;
$$;

create function public.super_admin_criar_recurso(
  p_codigo text,
  p_nome text,
  p_descricao text,
  p_ordem integer,
  p_ativo boolean
)
returns table (
  codigo text, nome text, descricao text, ordem smallint, ativo boolean,
  criado_em timestamptz, atualizado_em timestamptz, planos_incluidos text[],
  quantidade_planos_incluidos bigint, quantidade_liberacoes bigint,
  quantidade_bloqueios bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_descricao text := coalesce(p_descricao, '');
begin
  if v_admin_id is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem criar recursos.', errcode = '42501';
  end if;
  if p_codigo is null or char_length(p_codigo) > 80 or p_codigo !~ '^[a-z][a-z0-9_]*$' then
    raise exception using message = 'Código de recurso inválido.', errcode = '22023';
  end if;
  if p_nome is null or char_length(btrim(p_nome)) < 1 or char_length(btrim(p_nome)) > 80 then
    raise exception using message = 'Nome do recurso inválido.', errcode = '22023';
  end if;
  if char_length(v_descricao) > 240 then
    raise exception using message = 'Descrição do recurso inválida.', errcode = '22023';
  end if;
  if p_ordem is null or p_ordem < 1 or p_ordem > 32767 then
    raise exception using message = 'Ordem do recurso inválida.', errcode = '22023';
  end if;
  if p_ativo is null then
    raise exception using message = 'Situação do recurso é obrigatória.', errcode = '22023';
  end if;
  if exists (select 1 from public.recursos r where r.codigo = p_codigo) then
    raise exception using message = 'Código de recurso já cadastrado.', errcode = '23505';
  end if;
  if exists (select 1 from public.recursos r where r.ordem = p_ordem) then
    raise exception using message = 'A ordem informada já está sendo utilizada.', errcode = '23505';
  end if;

  begin
    insert into public.recursos (
      codigo, nome, descricao, ordem, ativo, criado_em, atualizado_em, atualizado_por
    ) values (
      p_codigo, btrim(p_nome), v_descricao, p_ordem::smallint, p_ativo, now(), now(), v_admin_id
    );
  exception when unique_violation then
    if exists (select 1 from public.recursos r where r.codigo = p_codigo) then
      raise exception using message = 'Código de recurso já cadastrado.', errcode = '23505';
    end if;
    raise exception using message = 'A ordem informada já está sendo utilizada.', errcode = '23505';
  end;

  insert into public.plano_recursos (
    plano_codigo, recurso_codigo, incluido, atualizado_em, atualizado_por
  )
  select p.codigo, p_codigo, false, now(), v_admin_id
  from public.planos p;

  return query
  select
    r.codigo, r.nome, r.descricao, r.ordem, r.ativo, r.criado_em, r.atualizado_em,
    array[]::text[], 0::bigint, 0::bigint, 0::bigint
  from public.recursos r
  where r.codigo = p_codigo;
end;
$$;

create function public.super_admin_atualizar_recurso(
  p_codigo text,
  p_nome text,
  p_descricao text,
  p_ordem integer,
  p_ativo boolean,
  p_confirmar_desativacao boolean
)
returns table (
  codigo text, nome text, descricao text, ordem smallint, ativo boolean,
  criado_em timestamptz, atualizado_em timestamptz, planos_incluidos text[],
  quantidade_planos_incluidos bigint, quantidade_liberacoes bigint,
  quantidade_bloqueios bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_descricao text := coalesce(p_descricao, '');
  v_ativo_atual boolean;
begin
  if v_admin_id is null or not public.eh_super_admin() then
    raise exception using message = 'Apenas administradores da plataforma podem atualizar recursos.', errcode = '42501';
  end if;
  if p_codigo is null then
    raise exception using message = 'Código do recurso é obrigatório.', errcode = '22023';
  end if;
  if p_nome is null or char_length(btrim(p_nome)) < 1 or char_length(btrim(p_nome)) > 80 then
    raise exception using message = 'Nome do recurso inválido.', errcode = '22023';
  end if;
  if char_length(v_descricao) > 240 then
    raise exception using message = 'Descrição do recurso inválida.', errcode = '22023';
  end if;
  if p_ordem is null or p_ordem < 1 or p_ordem > 32767 then
    raise exception using message = 'Ordem do recurso inválida.', errcode = '22023';
  end if;
  if p_ativo is null then
    raise exception using message = 'Situação do recurso é obrigatória.', errcode = '22023';
  end if;
  if p_confirmar_desativacao is null then
    raise exception using message = 'Confirmação de desativação é obrigatória.', errcode = '22023';
  end if;

  select r.ativo into v_ativo_atual
  from public.recursos r
  where r.codigo = p_codigo
  for update;
  if not found then
    raise exception using message = 'Recurso não encontrado.', errcode = 'P0002';
  end if;
  if exists (select 1 from public.recursos r where r.ordem = p_ordem and r.codigo <> p_codigo) then
    raise exception using message = 'A ordem informada já está sendo utilizada.', errcode = '23505';
  end if;
  if v_ativo_atual and not p_ativo and not p_confirmar_desativacao and (
    exists (select 1 from public.plano_recursos pr where pr.recurso_codigo = p_codigo and pr.incluido)
    or exists (select 1 from public.restaurante_recursos rr where rr.recurso_codigo = p_codigo)
  ) then
    raise exception using
      message = 'Confirmação necessária para desativar recurso em uso.',
      errcode = '22023';
  end if;

  begin
    update public.recursos r
    set nome = btrim(p_nome), descricao = v_descricao, ordem = p_ordem::smallint,
        ativo = p_ativo, atualizado_em = now(), atualizado_por = v_admin_id
    where r.codigo = p_codigo;
  exception when unique_violation then
    raise exception using message = 'A ordem informada já está sendo utilizada.', errcode = '23505';
  end;

  return query
  select
    r.codigo, r.nome, r.descricao, r.ordem, r.ativo, r.criado_em, r.atualizado_em,
    coalesce(m.planos_incluidos, array[]::text[]),
    coalesce(m.quantidade_planos_incluidos, 0),
    coalesce(e.quantidade_liberacoes, 0),
    coalesce(e.quantidade_bloqueios, 0)
  from public.recursos r
  left join lateral (
    select array_agg(p.nome order by p.ordem) as planos_incluidos,
           count(*) as quantidade_planos_incluidos
    from public.plano_recursos pr
    join public.planos p on p.codigo = pr.plano_codigo
    where pr.recurso_codigo = r.codigo and pr.incluido
  ) m on true
  left join lateral (
    select count(*) filter (where rr.decisao = 'liberar') as quantidade_liberacoes,
           count(*) filter (where rr.decisao = 'bloquear') as quantidade_bloqueios
    from public.restaurante_recursos rr
    where rr.recurso_codigo = r.codigo
  ) e on true
  where r.codigo = p_codigo
  ;
end;
$$;

revoke all on function public.super_admin_listar_catalogo_recursos() from public, anon;
revoke all on function public.super_admin_criar_recurso(text,text,text,integer,boolean) from public, anon;
revoke all on function public.super_admin_atualizar_recurso(text,text,text,integer,boolean,boolean) from public, anon;

grant execute on function public.super_admin_listar_catalogo_recursos() to authenticated, service_role;
grant execute on function public.super_admin_criar_recurso(text,text,text,integer,boolean) to authenticated, service_role;
grant execute on function public.super_admin_atualizar_recurso(text,text,text,integer,boolean,boolean) to authenticated, service_role;
