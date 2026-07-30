-- Contador diário de pedidos por restaurante
create table if not exists contadores_diarios (
  restaurante_id uuid not null references restaurantes(id) on delete cascade,
  data date not null,
  ultimo_numero int not null default 0,
  primary key (restaurante_id, data)
);
alter table contadores_diarios enable row level security;

-- Colunas novas em pedidos
alter table pedidos add column if not exists numero_diario int;
alter table pedidos add column if not exists data_pedido date;
create index if not exists idx_pedidos_restaurante_data on pedidos (restaurante_id, data_pedido);

-- Função atômica para gerar o próximo número do dia
create or replace function proximo_numero_diario(p_restaurante_id uuid, p_data date)
returns int
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_numero int;
begin
  insert into contadores_diarios (restaurante_id, data, ultimo_numero)
  values (p_restaurante_id, p_data, 1)
  on conflict (restaurante_id, data)
  do update set ultimo_numero = contadores_diarios.ultimo_numero + 1
  returning ultimo_numero into v_numero;
  return v_numero;
end;
$$;
grant execute on function proximo_numero_diario(uuid, date) to anon, authenticated;

-- Telefone único por restaurante (não havia duplicados, então é seguro criar)
create unique index if not exists idx_clientes_restaurante_telefone
  on clientes (restaurante_id, telefone)
  where telefone is not null;

-- Faz o lançamento financeiro automático (trigger existente) usar o número diário
-- quando disponível, em vez do código UUID, mantendo consistência com o painel.
create or replace function public.gerar_entrada_financeira_pedido()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.pago = true then
    insert into movimentacoes_financeiras (restaurante_id, tipo, descricao, valor, pedido_id, criado_por)
    values (
      new.restaurante_id,
      'receita',
      case when new.numero_diario is not null
        then 'Pedido #' || new.numero_diario
        else 'Pedido #' || upper(substr(new.id::text, 1, 8))
      end,
      new.total,
      new.id,
      auth.uid()
    )
    on conflict (pedido_id) do nothing;
  end if;
  return new;
end;
$$;
