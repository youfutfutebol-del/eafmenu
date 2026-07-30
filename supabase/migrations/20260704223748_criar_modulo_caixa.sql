-- Rastreia a forma de pagamento de cada movimentação, necessário pra saber
-- quanto de fato está em DINHEIRO físico na gaveta (pix/cartão não contam).
alter table movimentacoes_financeiras add column if not exists forma_pagamento text;

-- Trigger de entrada automática passa a copiar a forma de pagamento do pedido
create or replace function public.gerar_entrada_financeira_pedido()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.pago = true then
    insert into movimentacoes_financeiras (restaurante_id, tipo, descricao, valor, pedido_id, criado_por, forma_pagamento)
    values (
      new.restaurante_id,
      'receita',
      case when new.numero_diario is not null
        then 'Pedido #' || new.numero_diario
        else 'Pedido #' || upper(substr(new.id::text, 1, 8))
      end,
      new.total,
      new.id,
      auth.uid(),
      new.forma_pagamento
    )
    on conflict (pedido_id) do nothing;
  end if;
  return new;
end;
$$;

-- Backfill das movimentações já existentes: entradas puxam do pedido; despesas assumem dinheiro (eram lançadas manualmente do caixa)
update movimentacoes_financeiras m
set forma_pagamento = p.forma_pagamento
from pedidos p
where m.pedido_id = p.id and m.forma_pagamento is null;

update movimentacoes_financeiras
set forma_pagamento = 'dinheiro'
where forma_pagamento is null and tipo = 'despesa';

-- Tabela de fechamento de caixa
create table if not exists fechamentos_caixa (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references restaurantes(id) on delete cascade,
  status text not null default 'aberto' check (status in ('aberto','fechado')),
  valor_abertura numeric(10,2) not null default 0,
  aberto_por uuid references usuarios(id),
  aberto_em timestamptz not null default now(),
  valor_dinheiro_esperado numeric(10,2),
  valor_dinheiro_informado numeric(10,2),
  diferenca numeric(10,2),
  observacoes text,
  fechado_por uuid references usuarios(id),
  fechado_em timestamptz
);
alter table fechamentos_caixa enable row level security;

create policy staff_ve_caixa on fechamentos_caixa
  for select
  using (restaurante_id = auth_restaurante_id() and auth_role() = ANY (ARRAY['dono'::user_role,'gerente'::user_role,'atendente'::user_role]));

create policy staff_abre_caixa on fechamentos_caixa
  for insert
  with check (restaurante_id = auth_restaurante_id() and auth_role() = ANY (ARRAY['dono'::user_role,'gerente'::user_role,'atendente'::user_role]));

create policy staff_fecha_caixa on fechamentos_caixa
  for update
  using (restaurante_id = auth_restaurante_id() and auth_role() = ANY (ARRAY['dono'::user_role,'gerente'::user_role,'atendente'::user_role]));

create index if not exists idx_fechamentos_caixa_restaurante on fechamentos_caixa (restaurante_id, status);
