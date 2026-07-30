
ALTER TABLE public.restaurantes
  ADD COLUMN prazo_retirada_min_minutos integer,
  ADD COLUMN prazo_retirada_max_minutos integer;

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_retirada_min_nao_negativo
    CHECK (
      prazo_retirada_min_minutos IS NULL
      OR prazo_retirada_min_minutos >= 0
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_retirada_max_nao_negativo
    CHECK (
      prazo_retirada_max_minutos IS NULL
      OR prazo_retirada_max_minutos >= 0
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_retirada_min_maximo_120
    CHECK (
      prazo_retirada_min_minutos IS NULL
      OR prazo_retirada_min_minutos <= 120
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_retirada_max_maximo_120
    CHECK (
      prazo_retirada_max_minutos IS NULL
      OR prazo_retirada_max_minutos <= 120
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_retirada_intervalo_completo
    CHECK (
      (
        prazo_retirada_min_minutos IS NULL
        AND prazo_retirada_max_minutos IS NULL
      )
      OR
      (
        prazo_retirada_min_minutos IS NOT NULL
        AND prazo_retirada_max_minutos IS NOT NULL
      )
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_retirada_min_menor_igual_max
    CHECK (
      prazo_retirada_min_minutos IS NULL
      OR prazo_retirada_max_minutos IS NULL
      OR prazo_retirada_min_minutos <= prazo_retirada_max_minutos
    );

COMMENT ON COLUMN public.restaurantes.prazo_retirada_min_minutos IS
  'F03.03A: minutos mínimos do prazo estimado de retirada configurado pelo restaurante. NULL com o máximo também NULL significa não configurado.';
COMMENT ON COLUMN public.restaurantes.prazo_retirada_max_minutos IS
  'F03.03A: minutos máximos do prazo estimado de retirada configurado pelo restaurante. NULL com o mínimo também NULL significa não configurado.';

CREATE OR REPLACE VIEW public.restaurantes_publico
WITH (security_invoker = false) AS
SELECT
    id,
    nome,
    slug,
    logo_url,
    cor_destaque,
    whatsapp,
    endereco,
    instagram,
    horarios_semana,
    taxa_entrega_padrao,
    prazo_entrega_min_minutos,
    prazo_entrega_max_minutos,
    prazo_retirada_min_minutos,
    prazo_retirada_max_minutos
FROM public.restaurantes;
