ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_entrega_min_maximo_120
    CHECK (
      prazo_entrega_min_minutos IS NULL
      OR prazo_entrega_min_minutos <= 120
    );

ALTER TABLE public.restaurantes
  ADD CONSTRAINT chk_prazo_entrega_max_maximo_120
    CHECK (
      prazo_entrega_max_minutos IS NULL
      OR prazo_entrega_max_minutos <= 120
    );
