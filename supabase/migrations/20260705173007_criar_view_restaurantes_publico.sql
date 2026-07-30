create view public.restaurantes_publico as
select id, nome, slug, logo_url, cor_destaque, whatsapp, endereco, instagram, horarios_semana, taxa_entrega_padrao
from public.restaurantes;

grant select on public.restaurantes_publico to anon, authenticated;