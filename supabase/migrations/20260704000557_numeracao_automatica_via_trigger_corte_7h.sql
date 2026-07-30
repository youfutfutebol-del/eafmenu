-- Atribui numero_diario/data_pedido automaticamente em QUALQUER insert em pedidos
-- (painel manual, PWA do cliente, etc), com corte às 7h no horário de Brasília.
create or replace function public.atribuir_numero_diario_pedido()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_local_ts timestamp;
  v_dia_comercial date;
  v_numero int;
begin
  -- Se algo já definiu o número explicitamente, respeita e não mexe.
  if new.numero_diario is not null then
    return new;
  end if;

  v_local_ts := (coalesce(new.criado_em, now()) at time zone 'America/Sao_Paulo');

  if extract(hour from v_local_ts) < 7 then
    v_dia_comercial := (v_local_ts::date) - 1;
  else
    v_dia_comercial := v_local_ts::date;
  end if;

  insert into contadores_diarios (restaurante_id, data, ultimo_numero)
  values (new.restaurante_id, v_dia_comercial, 1)
  on conflict (restaurante_id, data)
  do update set ultimo_numero = contadores_diarios.ultimo_numero + 1
  returning ultimo_numero into v_numero;

  new.numero_diario := v_numero;
  new.data_pedido := v_dia_comercial;

  return new;
end;
$$;

drop trigger if exists trg_atribuir_numero_diario on pedidos;
create trigger trg_atribuir_numero_diario
before insert on pedidos
for each row
execute function atribuir_numero_diario_pedido();

-- Backfill dos 3 pedidos de teste que já existem sem número, na ordem em que foram criados
with pedidos_sem_numero as (
  select
    id,
    restaurante_id,
    criado_em,
    (case
      when extract(hour from (criado_em at time zone 'America/Sao_Paulo')) < 7
      then ((criado_em at time zone 'America/Sao_Paulo')::date) - 1
      else (criado_em at time zone 'America/Sao_Paulo')::date
    end) as dia_comercial,
    row_number() over (
      partition by restaurante_id,
        (case
          when extract(hour from (criado_em at time zone 'America/Sao_Paulo')) < 7
          then ((criado_em at time zone 'America/Sao_Paulo')::date) - 1
          else (criado_em at time zone 'America/Sao_Paulo')::date
        end)
      order by criado_em asc
    ) as rn
  from pedidos
  where numero_diario is null
)
update pedidos p
set numero_diario = ps.rn,
    data_pedido = ps.dia_comercial
from pedidos_sem_numero ps
where p.id = ps.id;

-- Sincroniza os contadores para não colidir com os números já usados no backfill
insert into contadores_diarios (restaurante_id, data, ultimo_numero)
select restaurante_id, data_pedido, max(numero_diario)
from pedidos
where numero_diario is not null
group by restaurante_id, data_pedido
on conflict (restaurante_id, data)
do update set ultimo_numero = greatest(contadores_diarios.ultimo_numero, excluded.ultimo_numero);
