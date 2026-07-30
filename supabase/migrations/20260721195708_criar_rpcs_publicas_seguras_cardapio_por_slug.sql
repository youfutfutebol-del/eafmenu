
-- =========================================================
-- RPC 1: restaurante_publico_por_slug
-- =========================================================
CREATE OR REPLACE FUNCTION public.restaurante_publico_por_slug(p_slug text)
RETURNS TABLE (
  id uuid,
  nome text,
  slug text,
  logo_url text,
  cor_destaque text,
  whatsapp text,
  endereco text,
  instagram text,
  horarios_semana jsonb,
  taxa_entrega_padrao numeric,
  prazo_entrega_min_minutos integer,
  prazo_entrega_max_minutos integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    r.id, r.nome, r.slug, r.logo_url, r.cor_destaque, r.whatsapp,
    r.endereco, r.instagram, r.horarios_semana, r.taxa_entrega_padrao,
    r.prazo_entrega_min_minutos, r.prazo_entrega_max_minutos
  FROM restaurantes r
  WHERE r.slug = lower(trim(coalesce(p_slug, '')))
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.restaurante_publico_por_slug(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restaurante_publico_por_slug(text) TO anon, authenticated, service_role;

-- =========================================================
-- RPC 2: cardapio_publico_por_slug (com correção de EXISTS de preço válido)
-- =========================================================
CREATE OR REPLACE FUNCTION public.cardapio_publico_por_slug(p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_restaurante_id uuid;
  v_categorias jsonb;
  v_produtos jsonb;
  v_grupos jsonb;
  v_opcoes jsonb;
begin
  select id into v_restaurante_id
  from restaurantes
  where slug = lower(trim(coalesce(p_slug, '')))
  limit 1;

  if v_restaurante_id is null then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'nome', c.nome, 'ordem', c.ordem
         ) order by c.ordem), '[]'::jsonb)
    into v_categorias
  from categorias c
  where c.restaurante_id = v_restaurante_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id, 'max_sabores', g.max_sabores
         )), '[]'::jsonb)
    into v_grupos
  from grupos_tamanho g
  where g.restaurante_id = v_restaurante_id
    and g.ativo = true;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', ot.id, 'grupo_id', ot.grupo_id, 'nome', ot.nome, 'ordem', ot.ordem
         ) order by ot.ordem), '[]'::jsonb)
    into v_opcoes
  from opcoes_tamanho ot
  join grupos_tamanho g on g.id = ot.grupo_id
  where g.restaurante_id = v_restaurante_id
    and g.ativo = true
    and ot.ativo = true;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'nome', p.nome,
           'descricao', p.descricao,
           'imagem_url', p.imagem_url,
           'categoria_id', p.categoria_id,
           'grupo_tamanho_id', p.grupo_tamanho_id,
           'produto_precos', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'id', pp.id,
                      'preco', pp.preco,
                      'preco_promocional', pp.preco_promocional,
                      'promocao_ativa', pp.promocao_ativa,
                      'ativo', pp.ativo,
                      'opcao_tamanho_id', pp.opcao_tamanho_id
                    )), '[]'::jsonb)
             from produto_precos pp
             where pp.produto_id = p.id
               and pp.ativo = true
               and (
                 (p.grupo_tamanho_id is null and pp.opcao_tamanho_id is null)
                 or
                 (p.grupo_tamanho_id is not null and pp.opcao_tamanho_id in (
                    select ot2.id from opcoes_tamanho ot2
                    where ot2.grupo_id = p.grupo_tamanho_id and ot2.ativo = true
                 ))
               )
           )
         )), '[]'::jsonb)
    into v_produtos
  from produtos p
  where p.restaurante_id = v_restaurante_id
    and p.ativo = true
    and (
      p.grupo_tamanho_id is null
      or exists (
        select 1 from grupos_tamanho g2
        where g2.id = p.grupo_tamanho_id
          and g2.ativo = true
          and g2.restaurante_id = v_restaurante_id
      )
    )
    -- Correção obrigatória: só inclui o produto se existir ao menos 1 preço ativo/válido,
    -- usando exatamente a mesma regra do array produto_precos acima.
    and exists (
      select 1 from produto_precos pp
      where pp.produto_id = p.id
        and pp.ativo = true
        and (
          (p.grupo_tamanho_id is null and pp.opcao_tamanho_id is null)
          or
          (p.grupo_tamanho_id is not null and pp.opcao_tamanho_id in (
             select ot2.id from opcoes_tamanho ot2
             where ot2.grupo_id = p.grupo_tamanho_id and ot2.ativo = true
          ))
        )
    );

  return jsonb_build_object(
    'restaurante_id', v_restaurante_id,
    'categorias', v_categorias,
    'produtos', v_produtos,
    'grupos_tamanho', v_grupos,
    'opcoes_tamanho', v_opcoes
  );
end;
$$;

REVOKE ALL ON FUNCTION public.cardapio_publico_por_slug(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cardapio_publico_por_slug(text) TO anon, authenticated, service_role;
