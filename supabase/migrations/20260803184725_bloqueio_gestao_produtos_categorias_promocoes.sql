-- EAF Menu
-- Bloqueio operacional: Gestão de Produtos, Gestão de Categorias e Promoções.
--
-- Escopo:
--   categorias
--     public.categorias
--
--   produtos
--     public.produtos
--     public.produto_precos
--     public.grupos_tamanho
--     public.opcoes_tamanho
--     storage.objects em imagens/<restaurante_id>/produtos/*
--
--   promocoes
--     public.promocoes
--     public.promocao_escopos
--     public.promocao_escopo_itens
--     RPCs de ativar/desativar/arquivar são cobertas pelo trigger da tabela promocoes.
--
-- Não altera leituras públicas, cardápio, checkout ou aplicação de campanhas já ativas.

create or replace function public.trg_bloquear_recurso_gestao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registro jsonb;
  v_restaurante_id uuid;
  v_recurso_codigo text;
begin
  -- Operações internas, service role e Super Admin permanecem disponíveis.
  -- A segurança dos usuários comuns continua sendo complementada pela RLS.
  if auth.uid() is null or public.eh_super_admin() then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  v_registro := case
    when tg_op = 'DELETE' then to_jsonb(old)
    else to_jsonb(new)
  end;

  v_recurso_codigo := case
    when tg_table_schema <> 'public' then null
    when tg_table_name = 'categorias' then 'categorias'
    when tg_table_name in (
      'produtos',
      'produto_precos',
      'grupos_tamanho',
      'opcoes_tamanho'
    ) then 'produtos'
    when tg_table_name in (
      'promocoes',
      'promocao_escopos',
      'promocao_escopo_itens'
    ) then 'promocoes'
    else null
  end;

  if v_recurso_codigo is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  -- Tabelas com restaurante_id direto.
  if nullif(v_registro->>'restaurante_id', '') is not null then
    v_restaurante_id := (v_registro->>'restaurante_id')::uuid;

  -- Tabelas cujo tenant é resolvido pelo pai.
  elsif tg_table_name = 'produto_precos' then
    select p.restaurante_id
      into v_restaurante_id
    from public.produtos p
    where p.id = nullif(v_registro->>'produto_id', '')::uuid;

  elsif tg_table_name = 'opcoes_tamanho' then
    select g.restaurante_id
      into v_restaurante_id
    from public.grupos_tamanho g
    where g.id = nullif(v_registro->>'grupo_id', '')::uuid;
  end if;

  if v_restaurante_id is null then
    raise exception using
      message = 'Não foi possível validar a disponibilidade do recurso para esta operação.',
      detail = v_recurso_codigo,
      errcode = '42501';
  end if;

  if not public.recurso_disponivel_restaurante(
    v_restaurante_id,
    v_recurso_codigo
  ) then
    raise exception using
      message = 'Recurso indisponível para este restaurante.',
      detail = v_recurso_codigo,
      hint = 'Consulte o plano e as exceções individuais do restaurante.',
      errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.trg_bloquear_recurso_gestao()
from public, anon, authenticated;

grant execute on function public.trg_bloquear_recurso_gestao()
to service_role;


create or replace function public._storage_imagem_operacao_permitida(
  p_nome text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pastas text[];
  v_restaurante_id uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  select u.restaurante_id
    into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid()
    and u.ativo;

  if v_restaurante_id is null then
    return false;
  end if;

  v_pastas := storage.foldername(p_nome);

  if v_pastas[1] is distinct from v_restaurante_id::text then
    return false;
  end if;

  -- Somente imagens de produtos são subordinadas ao recurso produtos.
  -- Pastas já existentes, como marca, mantêm o comportamento atual.
  if coalesce(v_pastas[2], '') = 'produtos' then
    return public.recurso_disponivel_restaurante(
      v_restaurante_id,
      'produtos'
    );
  end if;

  return true;
end;
$$;

revoke all on function public._storage_imagem_operacao_permitida(text)
from public, anon;

grant execute on function public._storage_imagem_operacao_permitida(text)
to authenticated, service_role;


-- O trigger de restaurante pausado já existente tem nome alfabeticamente anterior:
-- bloquear_operacao_restaurante_pausado
-- Assim, a suspensão continua tendo prioridade e preserva SQLSTATE 55000.

drop trigger if exists bloquear_recurso_gestao on public.categorias;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.categorias
for each row execute function public.trg_bloquear_recurso_gestao();

drop trigger if exists bloquear_recurso_gestao on public.produtos;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.produtos
for each row execute function public.trg_bloquear_recurso_gestao();

drop trigger if exists bloquear_recurso_gestao on public.produto_precos;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.produto_precos
for each row execute function public.trg_bloquear_recurso_gestao();

drop trigger if exists bloquear_recurso_gestao on public.grupos_tamanho;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.grupos_tamanho
for each row execute function public.trg_bloquear_recurso_gestao();

drop trigger if exists bloquear_recurso_gestao on public.opcoes_tamanho;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.opcoes_tamanho
for each row execute function public.trg_bloquear_recurso_gestao();

drop trigger if exists bloquear_recurso_gestao on public.promocoes;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.promocoes
for each row execute function public.trg_bloquear_recurso_gestao();

drop trigger if exists bloquear_recurso_gestao on public.promocao_escopos;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.promocao_escopos
for each row execute function public.trg_bloquear_recurso_gestao();

drop trigger if exists bloquear_recurso_gestao on public.promocao_escopo_itens;
create trigger bloquear_recurso_gestao
before insert or update or delete on public.promocao_escopo_itens
for each row execute function public.trg_bloquear_recurso_gestao();


-- Preserva os nomes das policies existentes, restringindo a authenticated
-- e acrescentando a verificação do recurso somente na pasta produtos.

drop policy if exists "equipe envia imagens do proprio restaurante"
on storage.objects;

create policy "equipe envia imagens do proprio restaurante"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'imagens'
  and public._storage_imagem_operacao_permitida(name)
);


drop policy if exists "equipe atualiza/apaga imagens do proprio restaurante"
on storage.objects;

create policy "equipe atualiza/apaga imagens do proprio restaurante"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'imagens'
  and public._storage_imagem_operacao_permitida(name)
)
with check (
  bucket_id = 'imagens'
  and public._storage_imagem_operacao_permitida(name)
);


drop policy if exists "equipe apaga imagens do proprio restaurante"
on storage.objects;

create policy "equipe apaga imagens do proprio restaurante"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'imagens'
  and public._storage_imagem_operacao_permitida(name)
);
