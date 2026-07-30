
-- ============================================================
-- V4-A — CADASTRO GENÉRICO DE CAMPANHAS (aplicação definitiva)
-- ============================================================

alter table produtos add constraint uq_produtos_id_restaurante unique (id, restaurante_id);
alter table categorias add constraint uq_categorias_id_restaurante unique (id, restaurante_id);

create table promocoes (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references restaurantes(id),
  nome text not null,
  ativo boolean not null default false,
  arquivado_em timestamptz,
  condicao_quantidade integer not null check (condicao_quantidade > 0),
  beneficio_quantidade integer not null check (beneficio_quantidade > 0),
  beneficio_percentual numeric(5,2) not null check (beneficio_percentual > 0 and beneficio_percentual <= 100),
  beneficio_modo text not null check (beneficio_modo in ('produto_fixo','escolha_cliente','menor_preco_elegivel')),
  max_aplicacoes_por_pedido integer check (max_aplicacoes_por_pedido is null or max_aplicacoes_por_pedido >= 1),
  criado_por uuid not null references usuarios(id),
  criado_em timestamptz not null default now(),
  unique (id, restaurante_id),
  constraint chk_arquivada_inativa check (not ativo or arquivado_em is null)
);
create index idx_promocoes_restaurante_ativo on promocoes (restaurante_id, ativo);

create table promocao_escopos (
  id uuid primary key default gen_random_uuid(),
  promocao_id uuid not null,
  restaurante_id uuid not null,
  papel text not null check (papel in ('condicao','beneficio')),
  tipo text not null check (tipo in ('produto','lista_produtos','categoria')),
  unique (promocao_id, papel),
  unique (id, restaurante_id),
  foreign key (promocao_id, restaurante_id) references promocoes (id, restaurante_id)
);

create table promocao_escopo_itens (
  id uuid primary key default gen_random_uuid(),
  promocao_escopo_id uuid not null,
  restaurante_id uuid not null,
  produto_id uuid,
  categoria_id uuid,
  opcao_tamanho_id uuid references opcoes_tamanho(id),
  foreign key (promocao_escopo_id, restaurante_id) references promocao_escopos (id, restaurante_id),
  foreign key (produto_id, restaurante_id) references produtos (id, restaurante_id),
  foreign key (categoria_id, restaurante_id) references categorias (id, restaurante_id),
  constraint chk_pei_produto_xor_categoria check (
    (produto_id is not null and categoria_id is null)
    or (categoria_id is not null and produto_id is null and opcao_tamanho_id is null)
  )
);
create unique index uq_pei_produto_tamanho on promocao_escopo_itens (
  promocao_escopo_id, produto_id, coalesce(opcao_tamanho_id, '00000000-0000-0000-0000-000000000000'::uuid)
) where produto_id is not null;
create unique index uq_pei_categoria on promocao_escopo_itens (promocao_escopo_id, categoria_id) where categoria_id is not null;
create index idx_pei_produto on promocao_escopo_itens (produto_id);
create index idx_pei_categoria on promocao_escopo_itens (categoria_id);
create index idx_pei_opcao_tamanho on promocao_escopo_itens (opcao_tamanho_id);

create or replace function _opcoes_tamanho_validas_produto(p_produto_id uuid, p_restaurante_id uuid)
returns table(opcao_tamanho_id uuid) language sql security definer set search_path to 'public' as $f$
  select null::uuid where exists (
    select 1 from produtos p join produto_precos pp on pp.produto_id = p.id
    where p.id = p_produto_id and p.restaurante_id = p_restaurante_id
      and p.grupo_tamanho_id is null and pp.opcao_tamanho_id is null and pp.ativo = true
  )
  union all
  select ot.id from produtos p
    join grupos_tamanho gt on gt.id = p.grupo_tamanho_id
    join opcoes_tamanho ot on ot.grupo_id = gt.id
    join produto_precos pp on pp.produto_id = p.id and pp.opcao_tamanho_id = ot.id
  where p.id = p_produto_id and p.restaurante_id = p_restaurante_id
    and gt.ativo = true and gt.restaurante_id = p_restaurante_id
    and ot.ativo = true and pp.ativo = true;
$f$;

create or replace function _validar_produto_tamanho_ativo(p_produto_id uuid, p_opcao_tamanho_id uuid, p_restaurante_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare
  v_produto produtos%rowtype;
  v_existe boolean;
begin
  select * into v_produto from produtos where id = p_produto_id;
  if v_produto.id is null then raise exception 'Produto (%) nao encontrado.', p_produto_id; end if;
  if not v_produto.ativo then raise exception 'Produto (%) esta inativo.', p_produto_id; end if;
  if v_produto.restaurante_id <> p_restaurante_id then raise exception 'Produto (%) pertence a outro restaurante.', p_produto_id; end if;

  if p_opcao_tamanho_id is not null then
    select exists (select 1 from _opcoes_tamanho_validas_produto(p_produto_id, p_restaurante_id) v where v.opcao_tamanho_id = p_opcao_tamanho_id) into v_existe;
    if not v_existe then raise exception 'Opcao de tamanho (%) nao e uma combinacao valida para o produto (%).', p_opcao_tamanho_id, p_produto_id; end if;
  else
    select exists (select 1 from _opcoes_tamanho_validas_produto(p_produto_id, p_restaurante_id)) into v_existe;
    if not v_existe then raise exception 'Produto (%) nao possui combinacao de tamanho/preco valida.', p_produto_id; end if;
  end if;
end;
$f$;

create or replace function trg_validar_tamanho_escopo_item()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if new.produto_id is null then return new; end if;
  perform _validar_produto_tamanho_ativo(new.produto_id, new.opcao_tamanho_id, new.restaurante_id);
  return new;
end;
$f$;
create trigger trg_pei_valida_tamanho before insert or update on promocao_escopo_itens for each row execute function trg_validar_tamanho_escopo_item();

create or replace function trg_validar_sobreposicao_tamanho_escopo()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare v_conflito boolean;
begin
  if new.produto_id is null then return new; end if;
  if new.opcao_tamanho_id is null then
    select exists (select 1 from promocao_escopo_itens where promocao_escopo_id = new.promocao_escopo_id and produto_id = new.produto_id and id <> new.id) into v_conflito;
    if v_conflito then raise exception 'Produto (%) ja possui outra linha de tamanho neste escopo; "qualquer tamanho" nao pode coexistir com linhas especificas.', new.produto_id; end if;
  else
    select exists (select 1 from promocao_escopo_itens where promocao_escopo_id = new.promocao_escopo_id and produto_id = new.produto_id and opcao_tamanho_id is null and id <> new.id) into v_conflito;
    if v_conflito then raise exception 'Produto (%) ja possui uma linha "qualquer tamanho" neste escopo; nao pode coexistir com tamanho especifico.', new.produto_id; end if;
  end if;
  return new;
end;
$f$;
create trigger trg_pei_sobreposicao_tamanho before insert or update on promocao_escopo_itens for each row execute function trg_validar_sobreposicao_tamanho_escopo();

create or replace function trg_validar_criador_promocao()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if not exists (select 1 from usuarios u where u.id = new.criado_por and u.restaurante_id = new.restaurante_id) then
    raise exception 'Criador da campanha nao pertence ao restaurante informado.';
  end if;
  return new;
end;
$f$;
create trigger trg_promocao_valida_criador before insert or update on promocoes for each row execute function trg_validar_criador_promocao();

create or replace function trg_promocao_forcar_insert()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  new.ativo := false;
  new.arquivado_em := null;
  new.criado_por := auth.uid();
  new.criado_em := now();
  return new;
end;
$f$;
create trigger trg_promocao_insert_forcado before insert on promocoes for each row execute function trg_promocao_forcar_insert();

create or replace function trg_promocao_campos_estado_rpc()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if new.id is distinct from old.id then raise exception 'id de uma campanha nao pode ser alterado.'; end if;
  if new.criado_em is distinct from old.criado_em then raise exception 'criado_em de uma campanha nao pode ser alterado.'; end if;
  if coalesce(current_setting('eafmenu.via_rpc_gestao_promocao', true), 'false') = 'true' then return new; end if;
  if new.ativo is distinct from old.ativo
     or new.arquivado_em is distinct from old.arquivado_em
     or new.restaurante_id is distinct from old.restaurante_id
     or new.criado_por is distinct from old.criado_por then
    raise exception 'Campos ativo, arquivado_em, restaurante_id e criado_por so podem ser alterados pelas RPCs de gestao de campanha.';
  end if;
  return new;
end;
$f$;
create trigger trg_promocao_campos_estado before update on promocoes for each row execute function trg_promocao_campos_estado_rpc();

create or replace function trg_promocao_arquivada_imutavel()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if old.arquivado_em is not null then raise exception 'Campanha arquivada e imutavel e nao pode ser alterada.'; end if;
  return new;
end;
$f$;
create trigger trg_promocao_arquivada_lock before update on promocoes for each row execute function trg_promocao_arquivada_imutavel();

create or replace function trg_bloquear_edicao_estrutural_promocao_ativa()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if old.ativo = true and (
    new.nome is distinct from old.nome
    or new.condicao_quantidade is distinct from old.condicao_quantidade
    or new.beneficio_quantidade is distinct from old.beneficio_quantidade
    or new.beneficio_percentual is distinct from old.beneficio_percentual
    or new.beneficio_modo is distinct from old.beneficio_modo
    or new.max_aplicacoes_por_pedido is distinct from old.max_aplicacoes_por_pedido
  ) then raise exception 'Campanha ativa nao pode ter sua estrutura editada. Desative a campanha antes de editar.'; end if;
  return new;
end;
$f$;
create trigger trg_promocao_estrutural_ativa before update on promocoes for each row execute function trg_bloquear_edicao_estrutural_promocao_ativa();

create or replace function trg_escopo_parentesco_imutavel()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if new.id is distinct from old.id then raise exception 'id de um escopo nao pode ser alterado.'; end if;
  if new.promocao_id is distinct from old.promocao_id or new.restaurante_id is distinct from old.restaurante_id then
    raise exception 'promocao_id e restaurante_id de um escopo nao podem ser alterados. Exclua e recrie o escopo.';
  end if;
  return new;
end;
$f$;
create trigger trg_escopo_parentesco before update on promocao_escopos for each row execute function trg_escopo_parentesco_imutavel();

create or replace function trg_item_escopo_parentesco_imutavel()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if new.id is distinct from old.id then raise exception 'id de um item de escopo nao pode ser alterado.'; end if;
  if new.promocao_escopo_id is distinct from old.promocao_escopo_id or new.restaurante_id is distinct from old.restaurante_id then
    raise exception 'promocao_escopo_id e restaurante_id de um item nao podem ser alterados. Exclua e recrie o item.';
  end if;
  return new;
end;
$f$;
create trigger trg_item_escopo_parentesco before update on promocao_escopo_itens for each row execute function trg_item_escopo_parentesco_imutavel();

create or replace function trg_bloquear_edicao_escopo_ativo()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare v_ativo boolean; v_arquivado_em timestamptz; v_promocao_id uuid;
begin
  if coalesce(current_setting('eafmenu.via_rpc_gestao_promocao', true), 'false') = 'true' then return coalesce(new, old); end if;
  v_promocao_id := case when tg_op = 'INSERT' then new.promocao_id else old.promocao_id end;
  select ativo, arquivado_em into v_ativo, v_arquivado_em from promocoes where id = v_promocao_id;
  if v_ativo then raise exception 'Escopo de campanha ativa nao pode ser editado. Desative a campanha antes de editar.'; end if;
  if v_arquivado_em is not null then raise exception 'Escopo de campanha arquivada e imutavel.'; end if;
  return coalesce(new, old);
end;
$f$;
create trigger trg_escopo_edicao_ativa before insert or update or delete on promocao_escopos for each row execute function trg_bloquear_edicao_escopo_ativo();

create or replace function trg_bloquear_edicao_item_escopo_ativo()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare v_ativo boolean; v_arquivado_em timestamptz; v_escopo_id uuid;
begin
  if coalesce(current_setting('eafmenu.via_rpc_gestao_promocao', true), 'false') = 'true' then return coalesce(new, old); end if;
  v_escopo_id := case when tg_op = 'INSERT' then new.promocao_escopo_id else old.promocao_escopo_id end;
  select p.ativo, p.arquivado_em into v_ativo, v_arquivado_em from promocao_escopos pe join promocoes p on p.id = pe.promocao_id where pe.id = v_escopo_id;
  if v_ativo then raise exception 'Item de escopo de campanha ativa nao pode ser editado.'; end if;
  if v_arquivado_em is not null then raise exception 'Item de escopo de campanha arquivada e imutavel.'; end if;
  return coalesce(new, old);
end;
$f$;
create trigger trg_item_escopo_edicao_ativa before insert or update or delete on promocao_escopo_itens for each row execute function trg_bloquear_edicao_item_escopo_ativo();

create or replace function _validar_escopo_generico(p_escopo_id uuid, p_tipo text, p_restaurante_id uuid) returns void
language plpgsql security definer set search_path to 'public' as $f$
declare v_qtd_linhas int; v_qtd_produto_col int; v_qtd_categoria_col int; v_item record;
begin
  select count(*) into v_qtd_linhas from promocao_escopo_itens where promocao_escopo_id = p_escopo_id;
  select count(*) filter (where produto_id is not null), count(*) filter (where categoria_id is not null)
    into v_qtd_produto_col, v_qtd_categoria_col from promocao_escopo_itens where promocao_escopo_id = p_escopo_id;

  if p_tipo = 'produto' then
    if v_qtd_linhas <> 1 or v_qtd_produto_col <> 1 then raise exception 'Escopo tipo produto exige exatamente 1 linha com produto_id preenchido.'; end if;
    for v_item in select * from promocao_escopo_itens where promocao_escopo_id = p_escopo_id loop
      perform _validar_produto_tamanho_ativo(v_item.produto_id, v_item.opcao_tamanho_id, p_restaurante_id);
    end loop;
  elsif p_tipo = 'lista_produtos' then
    if v_qtd_linhas < 1 or v_qtd_categoria_col > 0 then raise exception 'Escopo tipo lista_produtos exige ao menos 1 linha, somente com produto_id preenchido.'; end if;
    for v_item in select * from promocao_escopo_itens where promocao_escopo_id = p_escopo_id loop
      perform _validar_produto_tamanho_ativo(v_item.produto_id, v_item.opcao_tamanho_id, p_restaurante_id);
    end loop;
  elsif p_tipo = 'categoria' then
    if v_qtd_linhas <> 1 or v_qtd_produto_col > 0 then raise exception 'Escopo tipo categoria exige exatamente 1 linha com categoria_id preenchido.'; end if;
    if not exists (select 1 from promocao_escopo_itens pei join categorias c on c.id = pei.categoria_id where pei.promocao_escopo_id = p_escopo_id and c.restaurante_id = p_restaurante_id) then
      raise exception 'Categoria do escopo nao pertence a este restaurante.';
    end if;
    if not exists (
      select 1 from promocao_escopo_itens pei join produtos p on p.categoria_id = pei.categoria_id
      where pei.promocao_escopo_id = p_escopo_id and p.ativo = true and p.restaurante_id = p_restaurante_id
        and exists (select 1 from _opcoes_tamanho_validas_produto(p.id, p_restaurante_id))
    ) then raise exception 'Categoria do escopo nao possui nenhum produto com combinacao de tamanho/preco valida.'; end if;
  else raise exception 'Tipo de escopo desconhecido: %', p_tipo; end if;
end;
$f$;

create or replace function _produto_tamanho_no_escopo(p_produto_id uuid, p_opcao_tamanho_id uuid, p_escopo_id uuid, p_tipo text) returns boolean
language sql security definer set search_path to 'public' as $f$
  select case
    when p_tipo in ('produto','lista_produtos') then exists (
      select 1 from promocao_escopo_itens pei where pei.promocao_escopo_id = p_escopo_id and pei.produto_id = p_produto_id
        and (pei.opcao_tamanho_id is null or pei.opcao_tamanho_id = p_opcao_tamanho_id))
    when p_tipo = 'categoria' then exists (
      select 1 from promocao_escopo_itens pei join produtos p on p.categoria_id = pei.categoria_id
      where pei.promocao_escopo_id = p_escopo_id and p.id = p_produto_id)
    else false end;
$f$;

create or replace function ativar_promocao(p_promocao_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare
  v_promo promocoes%rowtype;
  v_chamador usuarios%rowtype;
  v_esc_cond promocao_escopos%rowtype;
  v_esc_ben promocao_escopos%rowtype;
  v_item_ben promocao_escopo_itens%rowtype;
  v_qtd_combinacoes_validas int;
begin
  select * into v_chamador from usuarios where id = auth.uid();
  if not found or v_chamador.role not in ('dono','gerente') then raise exception 'Sem permissao para ativar campanha.'; end if;

  select * into v_promo from promocoes where id = p_promocao_id for update;
  if not found or v_promo.restaurante_id <> v_chamador.restaurante_id then raise exception 'Campanha nao encontrada neste restaurante.'; end if;
  if v_promo.arquivado_em is not null then raise exception 'Campanha arquivada nao pode ser ativada.'; end if;

  select * into v_esc_cond from promocao_escopos where promocao_id = p_promocao_id and papel = 'condicao';
  select * into v_esc_ben from promocao_escopos where promocao_id = p_promocao_id and papel = 'beneficio';
  if v_esc_cond.id is null or v_esc_ben.id is null then raise exception 'Campanha precisa de escopo de condicao e de beneficio definidos.'; end if;

  perform _validar_escopo_generico(v_esc_cond.id, v_esc_cond.tipo, v_promo.restaurante_id);
  perform _validar_escopo_generico(v_esc_ben.id, v_esc_ben.tipo, v_promo.restaurante_id);

  if v_promo.beneficio_modo = 'produto_fixo' and v_esc_ben.tipo <> 'produto' then raise exception 'produto_fixo exige escopo de beneficio do tipo produto unico.'; end if;
  if v_promo.beneficio_modo = 'escolha_cliente' and v_esc_ben.tipo = 'produto' then raise exception 'escolha_cliente exige escopo de beneficio do tipo lista_produtos ou categoria, nao produto unico.'; end if;

  if v_promo.beneficio_modo = 'produto_fixo' then
    select * into v_item_ben from promocao_escopo_itens where promocao_escopo_id = v_esc_ben.id;
    if v_item_ben.opcao_tamanho_id is null then
      select count(*) into v_qtd_combinacoes_validas from _opcoes_tamanho_validas_produto(v_item_ben.produto_id, v_promo.restaurante_id);
      if v_qtd_combinacoes_validas = 0 then raise exception 'Produto de beneficio fixo nao possui combinacao de tamanho/preco valida.'; end if;
      if v_qtd_combinacoes_validas > 1 then raise exception 'Produto de beneficio fixo tem mais de uma combinacao de tamanho valida; escolha o tamanho no cadastro do escopo antes de ativar.'; end if;
    end if;
  end if;

  if v_promo.beneficio_modo = 'menor_preco_elegivel' then
    if v_esc_ben.tipo = 'produto' then
      select * into v_item_ben from promocao_escopo_itens where promocao_escopo_id = v_esc_ben.id;
      if not _produto_tamanho_no_escopo(v_item_ben.produto_id, v_item_ben.opcao_tamanho_id, v_esc_cond.id, v_esc_cond.tipo) then
        raise exception 'menor_preco_elegivel: o produto/tamanho do beneficio precisa estar contido no escopo da condicao.'; end if;
    elsif v_esc_ben.tipo = 'lista_produtos' then
      if exists (select 1 from promocao_escopo_itens ben where ben.promocao_escopo_id = v_esc_ben.id
          and not _produto_tamanho_no_escopo(ben.produto_id, ben.opcao_tamanho_id, v_esc_cond.id, v_esc_cond.tipo)) then
        raise exception 'menor_preco_elegivel: todos os produtos/tamanhos do beneficio precisam estar contidos no escopo da condicao.'; end if;
    elsif v_esc_ben.tipo = 'categoria' then
      if v_esc_cond.tipo <> 'categoria' then
        raise exception 'menor_preco_elegivel: beneficio por categoria exige condicao pela mesma categoria (nao e permitido condicao por lista_produtos neste MVP).'; end if;
      if not exists (select 1 from promocao_escopo_itens a join promocao_escopo_itens b on b.categoria_id = a.categoria_id
          where a.promocao_escopo_id = v_esc_ben.id and b.promocao_escopo_id = v_esc_cond.id) then
        raise exception 'menor_preco_elegivel: categoria do beneficio precisa ser a mesma da condicao.'; end if;
    end if;
  end if;

  perform set_config('eafmenu.via_rpc_gestao_promocao', 'true', true);
  update promocoes set ativo = true where id = p_promocao_id;
end;
$f$;

create or replace function desativar_promocao(p_promocao_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare v_chamador usuarios%rowtype; v_promo promocoes%rowtype;
begin
  select * into v_chamador from usuarios where id = auth.uid();
  if not found or v_chamador.role not in ('dono','gerente') then raise exception 'Sem permissao para desativar campanha.'; end if;
  select * into v_promo from promocoes where id = p_promocao_id for update;
  if not found or v_promo.restaurante_id <> v_chamador.restaurante_id then raise exception 'Campanha nao encontrada neste restaurante.'; end if;
  if v_promo.arquivado_em is not null then raise exception 'Campanha arquivada nao pode ser desativada.'; end if;
  if v_promo.ativo = false then raise exception 'Campanha ja esta inativa.'; end if;
  perform set_config('eafmenu.via_rpc_gestao_promocao', 'true', true);
  update promocoes set ativo = false where id = p_promocao_id;
end;
$f$;

create or replace function arquivar_promocao(p_promocao_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare v_chamador usuarios%rowtype; v_promo promocoes%rowtype;
begin
  select * into v_chamador from usuarios where id = auth.uid();
  if not found or v_chamador.role not in ('dono','gerente') then raise exception 'Sem permissao para arquivar campanha.'; end if;
  select * into v_promo from promocoes where id = p_promocao_id for update;
  if not found or v_promo.restaurante_id <> v_chamador.restaurante_id then raise exception 'Campanha nao encontrada neste restaurante.'; end if;
  if v_promo.arquivado_em is not null then raise exception 'Campanha ja esta arquivada.'; end if;
  perform set_config('eafmenu.via_rpc_gestao_promocao', 'true', true);
  update promocoes set ativo = false, arquivado_em = now() where id = p_promocao_id;
end;
$f$;

alter table promocoes enable row level security;
alter table promocao_escopos enable row level security;
alter table promocao_escopo_itens enable row level security;

create policy sel_promocoes on promocoes for select using (restaurante_id = auth_restaurante_id() and auth_role() <> 'motoboy');
create policy ins_promocoes on promocoes for insert with check (restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente') and ativo = false and arquivado_em is null and criado_por = auth.uid());
create policy upd_promocoes on promocoes for update using (restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente')) with check (restaurante_id = auth_restaurante_id());

create policy sel_promocao_escopos on promocao_escopos for select using (restaurante_id = auth_restaurante_id() and auth_role() <> 'motoboy');
create policy ins_promocao_escopos on promocao_escopos for insert with check (restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente'));
create policy upd_promocao_escopos on promocao_escopos for update using (restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente'));
create policy del_promocao_escopos on promocao_escopos for delete using (restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente'));

create policy sel_promocao_escopo_itens on promocao_escopo_itens for select using (restaurante_id = auth_restaurante_id() and auth_role() <> 'motoboy');
create policy ins_promocao_escopo_itens on promocao_escopo_itens for insert with check (restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente'));
create policy upd_promocao_escopo_itens on promocao_escopo_itens for update using (
  restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente')
  and not exists (select 1 from promocao_escopos pe join promocoes p on p.id = pe.promocao_id where pe.id = promocao_escopo_itens.promocao_escopo_id and (p.ativo = true or p.arquivado_em is not null))
);
create policy del_promocao_escopo_itens on promocao_escopo_itens for delete using (restaurante_id = auth_restaurante_id() and auth_role() in ('dono','gerente'));

revoke all on promocoes, promocao_escopos, promocao_escopo_itens from anon, public;
grant select, insert, update, delete on promocoes, promocao_escopos, promocao_escopo_itens to authenticated;
revoke execute on function ativar_promocao(uuid) from anon, public;
revoke execute on function desativar_promocao(uuid) from anon, public;
revoke execute on function arquivar_promocao(uuid) from anon, public;
revoke execute on function _validar_escopo_generico(uuid, text, uuid) from anon, public;
revoke execute on function _validar_produto_tamanho_ativo(uuid, uuid, uuid) from anon, public;
revoke execute on function _opcoes_tamanho_validas_produto(uuid, uuid) from anon, public;
revoke execute on function _produto_tamanho_no_escopo(uuid, uuid, uuid, text) from anon, public;
grant execute on function ativar_promocao(uuid) to authenticated;
grant execute on function desativar_promocao(uuid) to authenticated;
grant execute on function arquivar_promocao(uuid) to authenticated;
