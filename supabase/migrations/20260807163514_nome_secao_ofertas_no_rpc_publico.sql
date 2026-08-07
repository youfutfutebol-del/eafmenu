-- Expõe restaurantes.nome_secao_ofertas (coluna já existente, hoje sempre null pra todo
-- mundo) no RPC público restaurante_publico_por_slug — usado pelo cliente pra nomear a
-- aba de ofertas (nomeSecaoOfertas() em cliente/index.html). A coluna em si já existe na
-- tabela restaurantes; o que faltava era o RPC público devolver esse campo.
--
-- RETURNS TABLE muda de forma (ganha 1 coluna), então precisa DROP + CREATE — Postgres não
-- permite CREATE OR REPLACE FUNCTION alterar o formato de retorno de uma função existente.
-- O DROP apaga os grants da função, por isso eles são reaplicados no final, idênticos aos
-- que já existiam em produção (anon, authenticated, service_role).

drop function if exists public.restaurante_publico_por_slug(text);

create function public.restaurante_publico_por_slug(p_slug text)
returns table(
  id uuid, nome text, slug text, logo_url text, cor_destaque text, whatsapp text,
  endereco text, instagram text, horarios_semana jsonb, taxa_entrega_padrao numeric,
  prazo_entrega_min_minutos integer, prazo_entrega_max_minutos integer,
  nome_secao_ofertas text
)
language sql
stable security definer
set search_path to 'public'
as $function$
  select
    r.id, r.nome, r.slug, r.logo_url, r.cor_destaque, r.whatsapp,
    r.endereco, r.instagram, r.horarios_semana, r.taxa_entrega_padrao,
    r.prazo_entrega_min_minutos, r.prazo_entrega_max_minutos,
    r.nome_secao_ofertas
  from restaurantes r
  where r.slug = lower(trim(coalesce(p_slug, '')))
  limit 1;
$function$;

revoke all on function public.restaurante_publico_por_slug(text) from public;
grant execute on function public.restaurante_publico_por_slug(text) to anon, authenticated, service_role;
