ALTER TABLE public.restaurantes
  ADD COLUMN prazo_entrega_min_minutos integer,
  ADD COLUMN prazo_entrega_max_minutos integer;

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_entrega_min_nao_negativo
    CHECK (
      prazo_entrega_min_minutos IS NULL
      OR prazo_entrega_min_minutos >= 0
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_entrega_max_nao_negativo
    CHECK (
      prazo_entrega_max_minutos IS NULL
      OR prazo_entrega_max_minutos >= 0
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_entrega_intervalo_completo
    CHECK (
      (
        prazo_entrega_min_minutos IS NULL
        AND prazo_entrega_max_minutos IS NULL
      )
      OR
      (
        prazo_entrega_min_minutos IS NOT NULL
        AND prazo_entrega_max_minutos IS NOT NULL
      )
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_entrega_min_menor_igual_max
    CHECK (
      prazo_entrega_min_minutos IS NULL
      OR prazo_entrega_max_minutos IS NULL
      OR prazo_entrega_min_minutos <= prazo_entrega_max_minutos
    );

COMMENT ON COLUMN public.restaurantes.prazo_entrega_min_minutos IS
  'F03.01: minutos mínimos do prazo estimado de entrega configurado pelo restaurante. NULL com o máximo também NULL significa não configurado.';

COMMENT ON COLUMN public.restaurantes.prazo_entrega_max_minutos IS
  'F03.01: minutos máximos do prazo estimado de entrega configurado pelo restaurante. NULL com o mínimo também NULL significa não configurado.';
