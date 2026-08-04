-- BLOQUEIO DOS MÓDULOS INTERNOS:
-- clientes, gestão de equipe, personalização da marca, caixa e relatório financeiro.

create or replace function public._exigir_recurso_operacional_restaurante(
  p_restaurante_id uuid,
  p_recurso_codigo text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_restaurante_id is null then
    raise exception using
      message = 'Não foi possível validar o restaurante desta operação.',
      detail = coalesce(p_recurso_codigo, ''),
      errcode = '42501';
  end if;

  if not public.restaurante_operacional(p_restaurante_id) then
    raise exception using
      message = 'Restaurante sem acesso operacional.',
      errcode = '55000';
  end if;

  if not public.recurso_disponivel_restaurante(
    p_restaurante_id,
    p_recurso_codigo
  ) then
    raise exception using
      message = 'Recurso indisponível para este restaurante.',
      detail = p_recurso_codigo,
      hint = 'Consulte o plano e as exceções individuais do restaurante.',
      errcode = '42501';
  end if;
end;
$$;

revoke all on function public._exigir_recurso_operacional_restaurante(uuid, text)
  from public, anon, authenticated;
grant execute on function public._exigir_recurso_operacional_restaurante(uuid, text)
  to service_role;

create or replace function public._recurso_staff_disponivel(
  p_restaurante_id uuid,
  p_recurso_codigo text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuarios u
    where u.id = auth.uid()
      and u.ativo
      and u.restaurante_id = p_restaurante_id
      and u.role in ('dono', 'gerente', 'atendente')
      and public.restaurante_operacional(p_restaurante_id)
      and public.recurso_disponivel_restaurante(
        p_restaurante_id,
        p_recurso_codigo
      )
  );
$$;

revoke all on function public._recurso_staff_disponivel(uuid, text)
  from public;
grant execute on function public._recurso_staff_disponivel(uuid, text)
  to anon, authenticated, service_role;

create or replace function public.trg_bloquear_recurso_painel_interno()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registro jsonb;
  v_anterior jsonb;
  v_restaurante_id uuid;
  v_recurso_codigo text;
  v_role_anterior text;
  v_role_novo text;
  v_actor public.usuarios%rowtype;
begin
  if auth.uid() is null or public.eh_super_admin() then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select u.*
    into v_actor
  from public.usuarios u
  where u.id = auth.uid()
    and u.ativo;

  if v_actor.id is null
     or v_actor.role not in ('dono', 'gerente', 'atendente') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_registro := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_anterior := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end;

  if tg_table_schema <> 'public' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_table_name = 'clientes' then
    v_restaurante_id := nullif(v_registro->>'restaurante_id', '')::uuid;
    v_recurso_codigo := 'clientes';

  elsif tg_table_name = 'convites_equipe' then
    v_restaurante_id := nullif(v_registro->>'restaurante_id', '')::uuid;
    v_recurso_codigo := 'gestao_equipe';

  elsif tg_table_name = 'usuarios' then
    v_restaurante_id := nullif(v_registro->>'restaurante_id', '')::uuid;
    v_role_anterior := nullif(v_anterior->>'role', '');
    v_role_novo := nullif(v_registro->>'role', '');

    -- Motoboys pertencem ao recurso app_motoboy, tratado em etapa própria.
    if coalesce(v_role_anterior, 'motoboy') = 'motoboy'
       and coalesce(v_role_novo, 'motoboy') = 'motoboy' then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    -- Primeiro acesso é um fluxo de autenticação, não gestão de equipe.
    if tg_op = 'UPDATE'
       and old.id = auth.uid()
       and new.primeiro_acesso is distinct from old.primeiro_acesso
       and (
         to_jsonb(new) - array['primeiro_acesso', 'telefone_normalizado']
       ) = (
         to_jsonb(old) - array['primeiro_acesso', 'telefone_normalizado']
       ) then
      return new;
    end if;

    v_recurso_codigo := 'gestao_equipe';

  elsif tg_table_name = 'restaurantes' then
    if tg_op <> 'UPDATE' then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    if new.nome is not distinct from old.nome
       and new.slug is not distinct from old.slug
       and new.endereco is not distinct from old.endereco
       and new.logo_url is not distinct from old.logo_url
       and new.cor_destaque is not distinct from old.cor_destaque
       and new.whatsapp is not distinct from old.whatsapp
       and new.instagram is not distinct from old.instagram
       and new.horario_funcionamento is not distinct from old.horario_funcionamento
       and new.horarios_semana is not distinct from old.horarios_semana
       and new.aceita_pedidos_24h is not distinct from old.aceita_pedidos_24h then
      return new;
    end if;

    v_restaurante_id := new.id;
    v_recurso_codigo := 'personalizacao_marca';

  elsif tg_table_name = 'fechamentos_caixa' then
    v_restaurante_id := nullif(v_registro->>'restaurante_id', '')::uuid;
    v_recurso_codigo := 'caixa';

  elsif tg_table_name = 'movimentacoes_financeiras' then
    if tg_op <> 'INSERT'
       or coalesce(v_registro->>'origem', '') not in (
         'lancamento_manual',
         'ajuste_compensatorio'
       ) then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    v_restaurante_id := nullif(v_registro->>'restaurante_id', '')::uuid;
    v_recurso_codigo := 'caixa';

  else
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if v_restaurante_id is null
     or v_actor.restaurante_id is distinct from v_restaurante_id then
    raise exception using
      message = 'Você não tem permissão para operar este restaurante.',
      errcode = '42501';
  end if;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id,
    v_recurso_codigo
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.trg_bloquear_recurso_painel_interno()
  from public, anon, authenticated;
grant execute on function public.trg_bloquear_recurso_painel_interno()
  to service_role;

drop trigger if exists bloquear_recurso_painel_interno on public.clientes;
create trigger bloquear_recurso_painel_interno
before insert or update or delete on public.clientes
for each row execute function public.trg_bloquear_recurso_painel_interno();

drop trigger if exists bloquear_recurso_painel_interno on public.convites_equipe;
create trigger bloquear_recurso_painel_interno
before insert or update or delete on public.convites_equipe
for each row execute function public.trg_bloquear_recurso_painel_interno();

drop trigger if exists bloquear_recurso_painel_interno on public.usuarios;
create trigger bloquear_recurso_painel_interno
before insert or update or delete on public.usuarios
for each row execute function public.trg_bloquear_recurso_painel_interno();

drop trigger if exists bloquear_recurso_painel_interno on public.restaurantes;
create trigger bloquear_recurso_painel_interno
before update on public.restaurantes
for each row execute function public.trg_bloquear_recurso_painel_interno();

drop trigger if exists bloquear_recurso_painel_interno on public.fechamentos_caixa;
create trigger bloquear_recurso_painel_interno
before insert or update or delete on public.fechamentos_caixa
for each row execute function public.trg_bloquear_recurso_painel_interno();

drop trigger if exists bloquear_recurso_painel_interno on public.movimentacoes_financeiras;
create trigger bloquear_recurso_painel_interno
before insert or update or delete on public.movimentacoes_financeiras
for each row execute function public.trg_bloquear_recurso_painel_interno();

-- Políticas de leitura: clientes gerenciados e dados do caixa.
drop policy if exists staff_ve_clientes on public.clientes;
create policy staff_ve_clientes
on public.clientes
for select
to public
using (
  restaurante_id = public.auth_restaurante_id()
  and public.auth_role() in ('dono', 'gerente', 'atendente')
  and public._recurso_staff_disponivel(restaurante_id, 'clientes')
);

drop policy if exists "dono/gerente gerencia convites do proprio restaurante"
on public.convites_equipe;
create policy "dono/gerente gerencia convites do proprio restaurante"
on public.convites_equipe
for all
to public
using (
  restaurante_id = public.auth_restaurante_id()
  and public.auth_role() in ('dono', 'gerente')
  and public._recurso_staff_disponivel(restaurante_id, 'gestao_equipe')
)
with check (
  restaurante_id = public.auth_restaurante_id()
  and public.auth_role() in ('dono', 'gerente')
  and public._recurso_staff_disponivel(restaurante_id, 'gestao_equipe')
);

drop policy if exists "equipe le convites do proprio restaurante"
on public.convites_equipe;
create policy "equipe le convites do proprio restaurante"
on public.convites_equipe
for select
to public
using (
  restaurante_id = public.auth_restaurante_id()
  and public.auth_role() in ('dono', 'gerente')
  and public._recurso_staff_disponivel(restaurante_id, 'gestao_equipe')
);

drop policy if exists staff_ve_caixa on public.fechamentos_caixa;
create policy staff_ve_caixa
on public.fechamentos_caixa
for select
to public
using (
  restaurante_id = public.auth_restaurante_id()
  and public.auth_role() in ('dono', 'gerente', 'atendente')
  and public._recurso_staff_disponivel(restaurante_id, 'caixa')
);

drop policy if exists somente_gerente_dono_ve_financeiro
on public.movimentacoes_financeiras;
create policy somente_gerente_dono_ve_financeiro
on public.movimentacoes_financeiras
for select
to public
using (
  restaurante_id = public.auth_restaurante_id()
  and public.auth_role() in ('dono', 'gerente')
  and public._recurso_staff_disponivel(restaurante_id, 'caixa')
);

-- A pasta marca passa a respeitar personalizacao_marca.
create or replace function public._storage_imagem_operacao_permitida(p_nome text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pastas text[];
  v_restaurante_id uuid;
  v_recurso_codigo text;
begin
  if auth.uid() is null then
    return false;
  end if;

  select u.restaurante_id
    into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid()
    and u.ativo;

  if v_restaurante_id is null then
    return false;
  end if;

  v_pastas := storage.foldername(p_nome);

  if v_pastas[1] is distinct from v_restaurante_id::text then
    return false;
  end if;

  v_recurso_codigo := case coalesce(v_pastas[2], '')
    when 'produtos' then 'produtos'
    when 'marca' then 'personalizacao_marca'
    else null
  end;

  if v_recurso_codigo is null then
    return true;
  end if;

  return public.restaurante_operacional(v_restaurante_id)
    and public.recurso_disponivel_restaurante(
      v_restaurante_id,
      v_recurso_codigo
    );
end;
$$;

revoke all on function public._storage_imagem_operacao_permitida(text)
  from public, anon;
grant execute on function public._storage_imagem_operacao_permitida(text)
  to authenticated, service_role;

-- Renomeia as implementações atuais e mantém os nomes públicos como wrappers protegidos.
alter function public.abrir_caixa_v2(numeric)
  rename to _abrir_caixa_v2_impl_recurso;
alter function public.fechar_caixa_v2(numeric, text)
  rename to _fechar_caixa_v2_impl_recurso;
alter function public.registrar_despesa_v2(text, numeric, text)
  rename to _registrar_despesa_v2_impl_recurso;
alter function public.listar_movimentacoes_financeiras_v2(text)
  rename to _listar_movimentacoes_financeiras_v2_impl_recurso;
alter function public.registrar_ajuste_financeiro_v1(uuid, text)
  rename to _registrar_ajuste_financeiro_v1_impl_recurso;
alter function public.listar_movimentos_dinheiro_sem_caixa_v1(date, date)
  rename to _listar_movimentos_dinheiro_sem_caixa_v1_impl_recurso;
alter function public.relatorio_financeiro_v2(date, date)
  rename to _relatorio_financeiro_v2_impl_recurso;
alter function public.criar_usuario_equipe(text, text, text, text, text, text, text)
  rename to _criar_usuario_equipe_impl_recurso;
alter function public.remover_usuario_equipe(uuid)
  rename to _remover_usuario_equipe_impl_recurso;
alter function public.redefinir_senha_usuario(uuid, text)
  rename to _redefinir_senha_usuario_impl_recurso;

revoke all on function public._abrir_caixa_v2_impl_recurso(numeric)
  from public, anon, authenticated;
revoke all on function public._fechar_caixa_v2_impl_recurso(numeric, text)
  from public, anon, authenticated;
revoke all on function public._registrar_despesa_v2_impl_recurso(text, numeric, text)
  from public, anon, authenticated;
revoke all on function public._listar_movimentacoes_financeiras_v2_impl_recurso(text)
  from public, anon, authenticated;
revoke all on function public._registrar_ajuste_financeiro_v1_impl_recurso(uuid, text)
  from public, anon, authenticated;
revoke all on function public._listar_movimentos_dinheiro_sem_caixa_v1_impl_recurso(date, date)
  from public, anon, authenticated;
revoke all on function public._relatorio_financeiro_v2_impl_recurso(date, date)
  from public, anon, authenticated;
revoke all on function public._criar_usuario_equipe_impl_recurso(text, text, text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public._remover_usuario_equipe_impl_recurso(uuid)
  from public, anon, authenticated;
revoke all on function public._redefinir_senha_usuario_impl_recurso(uuid, text)
  from public, anon, authenticated;

grant execute on function public._abrir_caixa_v2_impl_recurso(numeric)
  to service_role;
grant execute on function public._fechar_caixa_v2_impl_recurso(numeric, text)
  to service_role;
grant execute on function public._registrar_despesa_v2_impl_recurso(text, numeric, text)
  to service_role;
grant execute on function public._listar_movimentacoes_financeiras_v2_impl_recurso(text)
  to service_role;
grant execute on function public._registrar_ajuste_financeiro_v1_impl_recurso(uuid, text)
  to service_role;
grant execute on function public._listar_movimentos_dinheiro_sem_caixa_v1_impl_recurso(date, date)
  to service_role;
grant execute on function public._relatorio_financeiro_v2_impl_recurso(date, date)
  to service_role;
grant execute on function public._criar_usuario_equipe_impl_recurso(text, text, text, text, text, text, text)
  to service_role;
grant execute on function public._remover_usuario_equipe_impl_recurso(uuid)
  to service_role;
grant execute on function public._redefinir_senha_usuario_impl_recurso(uuid, text)
  to service_role;

create function public.abrir_caixa_v2(p_valor_abertura numeric)
returns public.fechamentos_caixa
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id, 'caixa'
  );

  return public._abrir_caixa_v2_impl_recurso(p_valor_abertura);
end;
$$;

create function public.fechar_caixa_v2(
  p_valor_contado numeric,
  p_observacoes text default null
)
returns public.fechamentos_caixa
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id, 'caixa'
  );

  return public._fechar_caixa_v2_impl_recurso(
    p_valor_contado, p_observacoes
  );
end;
$$;

create function public.registrar_despesa_v2(
  p_descricao text,
  p_valor numeric,
  p_forma_pagamento text
)
returns public.movimentacoes_financeiras
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id, 'caixa'
  );

  return public._registrar_despesa_v2_impl_recurso(
    p_descricao, p_valor, p_forma_pagamento
  );
end;
$$;

create function public.listar_movimentacoes_financeiras_v2(
  p_periodo text default 'hoje'
)
returns table(
  id uuid,
  tipo text,
  descricao text,
  valor numeric,
  pedido_id uuid,
  criado_em timestamptz,
  forma_pagamento text,
  origem text,
  criado_por uuid,
  ajuste_de_id uuid,
  motivo_ajuste text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id, 'caixa'
  );

  return query
  select *
  from public._listar_movimentacoes_financeiras_v2_impl_recurso(p_periodo);
end;
$$;

create function public.registrar_ajuste_financeiro_v1(
  p_movimentacao_original_id uuid,
  p_motivo text
)
returns table(
  movimentacao_id uuid,
  movimentacao_original_id uuid,
  reutilizado boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id, 'caixa'
  );

  return query
  select *
  from public._registrar_ajuste_financeiro_v1_impl_recurso(
    p_movimentacao_original_id,
    p_motivo
  );
end;
$$;

create function public.listar_movimentos_dinheiro_sem_caixa_v1(
  p_data_inicio date default null,
  p_data_fim date default null
)
returns table(
  id uuid,
  tipo text,
  descricao text,
  valor numeric,
  criado_em timestamptz,
  forma_pagamento text,
  origem text,
  pedido_id uuid,
  ajuste_de_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id, 'caixa'
  );

  return query
  select *
  from public._listar_movimentos_dinheiro_sem_caixa_v1_impl_recurso(
    p_data_inicio,
    p_data_fim
  );
end;
$$;

create function public.relatorio_financeiro_v2(
  p_data_inicio date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  perform public._exigir_recurso_operacional_restaurante(
    v_restaurante_id, 'relatorio_financeiro'
  );

  return public._relatorio_financeiro_v2_impl_recurso(
    p_data_inicio,
    p_data_fim
  );
end;
$$;

create function public.criar_usuario_equipe(
  p_nome text,
  p_telefone text,
  p_email text,
  p_role text,
  p_senha text default null,
  p_veiculo text default null,
  p_placa text default null
)
returns table(
  novo_usuario_id uuid,
  senha_provisoria text,
  email_gerado text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select u.restaurante_id into v_restaurante_id
  from public.usuarios u
  where u.id = auth.uid() and u.ativo;

  if lower(btrim(coalesce(p_role, ''))) <> 'motoboy' then
    perform public._exigir_recurso_operacional_restaurante(
      v_restaurante_id, 'gestao_equipe'
    );
  end if;

  return query
  select *
  from public._criar_usuario_equipe_impl_recurso(
    p_nome, p_telefone, p_email, p_role, p_senha, p_veiculo, p_placa
  );
end;
$$;

create function public.remover_usuario_equipe(p_usuario_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_chamador uuid;
  v_restaurante_alvo uuid;
  v_role_alvo public.user_role;
begin
  select u.restaurante_id
    into v_restaurante_chamador
  from public.usuarios u
  where u.id = auth.uid()
    and u.ativo;

  select u.restaurante_id, u.role
    into v_restaurante_alvo, v_role_alvo
  from public.usuarios u
  where u.id = p_usuario_id;

  if v_restaurante_chamador is not null
     and v_restaurante_alvo is not distinct from v_restaurante_chamador
     and v_role_alvo is distinct from 'motoboy'::public.user_role then
    perform public._exigir_recurso_operacional_restaurante(
      v_restaurante_chamador, 'gestao_equipe'
    );
  end if;

  return public._remover_usuario_equipe_impl_recurso(p_usuario_id);
end;
$$;

create function public.redefinir_senha_usuario(
  p_usuario_id uuid,
  p_nova_senha text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_chamador uuid;
  v_restaurante_alvo uuid;
  v_role_alvo public.user_role;
begin
  select u.restaurante_id
    into v_restaurante_chamador
  from public.usuarios u
  where u.id = auth.uid()
    and u.ativo;

  select u.restaurante_id, u.role
    into v_restaurante_alvo, v_role_alvo
  from public.usuarios u
  where u.id = p_usuario_id;

  if v_restaurante_chamador is not null
     and v_restaurante_alvo is not distinct from v_restaurante_chamador
     and v_role_alvo is distinct from 'motoboy'::public.user_role then
    perform public._exigir_recurso_operacional_restaurante(
      v_restaurante_chamador, 'gestao_equipe'
    );
  end if;

  return public._redefinir_senha_usuario_impl_recurso(
    p_usuario_id,
    p_nova_senha
  );
end;
$$;

-- Fechar o relatório legado que não é usado pelo frontend atual.
revoke all on function public.relatorio_financeiro_v1(date, date)
  from public, anon, authenticated;
grant execute on function public.relatorio_financeiro_v1(date, date)
  to service_role;

-- Grants públicos somente nos wrappers.
revoke all on function public.abrir_caixa_v2(numeric)
  from public, anon;
revoke all on function public.fechar_caixa_v2(numeric, text)
  from public, anon;
revoke all on function public.registrar_despesa_v2(text, numeric, text)
  from public, anon;
revoke all on function public.listar_movimentacoes_financeiras_v2(text)
  from public, anon;
revoke all on function public.registrar_ajuste_financeiro_v1(uuid, text)
  from public, anon;
revoke all on function public.listar_movimentos_dinheiro_sem_caixa_v1(date, date)
  from public, anon;
revoke all on function public.relatorio_financeiro_v2(date, date)
  from public, anon;
revoke all on function public.criar_usuario_equipe(text, text, text, text, text, text, text)
  from public, anon;
revoke all on function public.remover_usuario_equipe(uuid)
  from public, anon;
revoke all on function public.redefinir_senha_usuario(uuid, text)
  from public, anon;

grant execute on function public.abrir_caixa_v2(numeric)
  to authenticated, service_role;
grant execute on function public.fechar_caixa_v2(numeric, text)
  to authenticated, service_role;
grant execute on function public.registrar_despesa_v2(text, numeric, text)
  to authenticated, service_role;
grant execute on function public.listar_movimentacoes_financeiras_v2(text)
  to authenticated, service_role;
grant execute on function public.registrar_ajuste_financeiro_v1(uuid, text)
  to authenticated, service_role;
grant execute on function public.listar_movimentos_dinheiro_sem_caixa_v1(date, date)
  to authenticated, service_role;
grant execute on function public.relatorio_financeiro_v2(date, date)
  to authenticated, service_role;
grant execute on function public.criar_usuario_equipe(text, text, text, text, text, text, text)
  to authenticated, service_role;
grant execute on function public.remover_usuario_equipe(uuid)
  to authenticated, service_role;
grant execute on function public.redefinir_senha_usuario(uuid, text)
  to authenticated, service_role;
