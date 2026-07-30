
CREATE OR REPLACE FUNCTION public.definir_previsao_pedido_ao_aceitar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_agora timestamptz;
  v_prazo_min integer;
  v_prazo_max integer;
  v_primeira_aceitacao boolean;
begin
  if tg_op = 'INSERT' then
    v_primeira_aceitacao := (new.status = 'aceito');
  else
    v_primeira_aceitacao := (new.status = 'aceito' and old.status is distinct from 'aceito');
  end if;

  if not v_primeira_aceitacao then
    if tg_op = 'INSERT' then
      -- Impede que um INSERT com status diferente de 'aceito' já chegue com previsão forjada
      new.previsao_inicio := null;
      new.previsao_fim := null;
    end if;
    return new;
  end if;

  v_agora := now();

  -- Nunca confiar em aceito_em vindo do frontend/cliente
  new.aceito_em := v_agora;

  if new.tipo = 'entrega' then
    select r.prazo_entrega_min_minutos, r.prazo_entrega_max_minutos
      into v_prazo_min, v_prazo_max
      from public.restaurantes r
     where r.id = new.restaurante_id;
  elsif new.tipo = 'retirada' then
    select r.prazo_retirada_min_minutos, r.prazo_retirada_max_minutos
      into v_prazo_min, v_prazo_max
      from public.restaurantes r
     where r.id = new.restaurante_id;
  else
    v_prazo_min := null;
    v_prazo_max := null;
  end if;

  if v_prazo_min is not null and v_prazo_max is not null then
    new.previsao_inicio := v_agora + make_interval(mins => v_prazo_min);
    new.previsao_fim := v_agora + make_interval(mins => v_prazo_max);
  else
    new.previsao_inicio := null;
    new.previsao_fim := null;
  end if;

  return new;
end;
$function$;
