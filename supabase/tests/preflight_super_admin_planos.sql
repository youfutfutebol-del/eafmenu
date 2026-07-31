-- Preflight transacional para criar_restaurante_com_plano.
-- Executar depois do SQL da migration, dentro de BEGIN ... ROLLBACK.

do $preflight_estrutura$
declare
  v_assinaturas integer;
  v_defaults text;
begin
  if to_regclass('public.planos') is null then
    raise exception 'Preflight 01: public.planos nao existe.';
  end if;

  if to_regprocedure('public.eh_super_admin()') is null
     or to_regprocedure('public.super_admin_definir_plano_restaurante(uuid,text)') is null then
    raise exception 'Preflight 01: dependencias administrativas ausentes.';
  end if;

  if to_regprocedure('public.criar_restaurante_com_dono(text,text,text,text,text)') is null then
    raise exception 'Preflight 02: assinatura legada de cinco argumentos ausente.';
  end if;

  if to_regprocedure('public.criar_restaurante_com_dono(text,text,text,text,text,text)') is null then
    raise exception 'Preflight 03: nova assinatura de seis argumentos ausente.';
  end if;

  select count(*) into v_assinaturas
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'criar_restaurante_com_dono'
    and p.pronargs in (5, 6);

  if v_assinaturas <> 2 then
    raise exception 'Preflight 03: quantidade inesperada de sobrecargas: %.', v_assinaturas;
  end if;

  select pg_catalog.pg_get_expr(p.proargdefaults, 0) into v_defaults
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'criar_restaurante_com_dono'
    and p.pronargs = 6;

  if v_defaults is not null then
    raise exception 'Preflight 03: a nova assinatura nao pode ter argumentos default.';
  end if;

  if has_function_privilege('anon', 'public.criar_restaurante_com_dono(text,text,text,text,text,text)', 'EXECUTE')
     or exists (
       select 1
       from pg_catalog.pg_proc p
       cross join lateral pg_catalog.aclexplode(
         coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
       ) acl
       where p.oid = 'public.criar_restaurante_com_dono(text,text,text,text,text,text)'::regprocedure
         and acl.grantee = 0
         and acl.privilege_type = 'EXECUTE'
     ) then
    raise exception 'Preflight 04: anon/public nao podem executar a nova assinatura.';
  end if;

  if not has_function_privilege('authenticated', 'public.criar_restaurante_com_dono(text,text,text,text,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.criar_restaurante_com_dono(text,text,text,text,text,text)', 'EXECUTE') then
    raise exception 'Preflight 04: grants esperados para authenticated/service_role ausentes.';
  end if;

  if exists (
    select 1
    from public.restaurantes r
    left join public.planos p on p.codigo = r.plano_codigo
    where p.codigo is null
  ) then
    raise exception 'Preflight 05: restaurante existente com plano invalido.';
  end if;
end;
$preflight_estrutura$;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  (select id::text from public.admins_plataforma order by criado_em limit 1),
  true
);

do $preflight_funcional$
declare
  v_resultado record;
  v_restaurante_id uuid;
  v_dono_id uuid;
  v_restaurante_base uuid;
  v_plano_base text;
  v_pausado_base boolean;
  v_modulo_base boolean;
  v_rejeitado boolean;
  v_total_antes bigint;
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception 'Preflight 06: contexto de Super Admin nao foi estabelecido.';
  end if;

  select count(*) into v_total_antes from public.restaurantes;

  -- 07: a assinatura legada continua funcional e usa Premium.
  select criado.restaurante_id, criado.dono_id
    into v_restaurante_id, v_dono_id
  from public.criar_restaurante_com_dono(
    'Preflight Legado', 'Dono Legado', '5511999999001',
    'preflight-legado@eaf.invalid', 'SenhaTeste123'
  ) criado;

  if not exists (
    select 1 from public.restaurantes r
    where r.id = v_restaurante_id and r.plano_codigo = 'premium'
      and not r.pausado and not r.modulo_motoboy_ativo
  ) or not exists (
    select 1 from public.usuarios u
    where u.id = v_dono_id and u.restaurante_id = v_restaurante_id and u.role = 'dono'
  ) then
    raise exception 'Preflight 07: criacao legada/default Premium divergiu.';
  end if;

  -- 08: a nova assinatura cria uma loja em cada plano ativo e devolve o plano efetivo.
  for v_resultado in
    select * from public.criar_restaurante_com_dono(
      'Preflight Essencial', 'Dono Essencial', '5511999999002',
      'preflight-essencial@eaf.invalid', 'SenhaTeste123', 'essencial'
    )
  loop
    if v_resultado.plano_codigo <> 'essencial' then
      raise exception 'Preflight 08: retorno Essencial incorreto.';
    end if;
  end loop;

  for v_resultado in
    select * from public.criar_restaurante_com_dono(
      'Preflight Profissional', 'Dono Profissional', '5511999999003',
      'preflight-profissional@eaf.invalid', 'SenhaTeste123', 'profissional'
    )
  loop
    if v_resultado.plano_codigo <> 'profissional' then
      raise exception 'Preflight 08: retorno Profissional incorreto.';
    end if;
  end loop;

  for v_resultado in
    select * from public.criar_restaurante_com_dono(
      'Preflight Premium', 'Dono Premium', '5511999999004',
      'preflight-premium@eaf.invalid', 'SenhaTeste123', 'premium'
    )
  loop
    if v_resultado.plano_codigo <> 'premium' then
      raise exception 'Preflight 08: retorno Premium incorreto.';
    end if;
  end loop;

  if (select count(*) from public.restaurantes where nome like 'Preflight %') <> 4 then
    raise exception 'Preflight 08: quantidade de lojas de teste inesperada.';
  end if;

  -- 09: plano inexistente e plano inativo falham antes de criar a loja.
  v_rejeitado := false;
  begin
    perform * from public.criar_restaurante_com_dono(
      'Preflight Inexistente', 'Dono Inexistente', '5511999999005',
      'preflight-inexistente@eaf.invalid', 'SenhaTeste123', 'nao-existe'
    );
  exception when sqlstate '22023' then
    v_rejeitado := true;
  end;
  if not v_rejeitado or exists (select 1 from public.restaurantes where nome = 'Preflight Inexistente') then
    raise exception 'Preflight 09: plano inexistente nao foi rejeitado atomicamente.';
  end if;

  update public.planos set ativo = false where codigo = 'essencial';
  v_rejeitado := false;
  begin
    perform * from public.criar_restaurante_com_dono(
      'Preflight Inativo', 'Dono Inativo', '5511999999006',
      'preflight-inativo@eaf.invalid', 'SenhaTeste123', 'essencial'
    );
  exception when sqlstate '22023' then
    v_rejeitado := true;
  end;
  update public.planos set ativo = true where codigo = 'essencial';
  if not v_rejeitado or exists (select 1 from public.restaurantes where nome = 'Preflight Inativo') then
    raise exception 'Preflight 09: plano inativo nao foi rejeitado antes da criacao.';
  end if;

  -- 10: mudar o plano de uma loja existente preserva pausa e modulo.
  select r.id, r.plano_codigo, r.pausado, r.modulo_motoboy_ativo
    into v_restaurante_base, v_plano_base, v_pausado_base, v_modulo_base
  from public.restaurantes r
  where r.nome not like 'Preflight %'
  order by r.criado_em
  limit 1;

  perform * from public.super_admin_definir_plano_restaurante(v_restaurante_base, 'profissional');
  if exists (
    select 1 from public.restaurantes r
    where r.id = v_restaurante_base
      and (r.pausado is distinct from v_pausado_base
        or r.modulo_motoboy_ativo is distinct from v_modulo_base)
  ) then
    raise exception 'Preflight 10: pausa ou modulo foram alterados junto com o plano.';
  end if;
  perform * from public.super_admin_definir_plano_restaurante(v_restaurante_base, v_plano_base);

  -- 11: uma falha na atribuicao reverte restaurante, dono e conta Auth.
  execute $ddl$
    create function pg_temp.bloquear_atribuicao_preflight()
    returns trigger language plpgsql as $trigger$
    begin
      if new.nome = 'Preflight Atomico' and new.plano_codigo is distinct from old.plano_codigo then
        raise exception using message = 'Falha de atribuicao simulada.', errcode = 'P0001';
      end if;
      return new;
    end
    $trigger$
  $ddl$;
  execute $ddl$
    create trigger bloquear_atribuicao_preflight
      before update of plano_codigo on public.restaurantes
      for each row execute function pg_temp.bloquear_atribuicao_preflight()
  $ddl$;

  v_rejeitado := false;
  begin
    perform * from public.criar_restaurante_com_dono(
      'Preflight Atomico', 'Dono Atomico', '5511999999007',
      'preflight-atomico@eaf.invalid', 'SenhaTeste123', 'essencial'
    );
  exception when sqlstate 'P0001' then
    v_rejeitado := true;
  end;

  execute 'drop trigger bloquear_atribuicao_preflight on public.restaurantes';
  if not v_rejeitado
     or exists (select 1 from public.restaurantes where nome = 'Preflight Atomico')
     or exists (select 1 from public.usuarios where telefone = '5511999999007')
     or exists (select 1 from auth.users where email = 'preflight-atomico@eaf.invalid') then
    raise exception 'Preflight 11: rollback atomico da criacao falhou.';
  end if;

  -- 12: um usuario autenticado comum nao pode criar restaurante.
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    (select u.id::text
     from public.usuarios u
     where u.ativo
       and not exists (select 1 from public.admins_plataforma a where a.id = u.id)
     order by u.criado_em
     limit 1),
    true
  );
  v_rejeitado := false;
  begin
    perform * from public.criar_restaurante_com_dono(
      'Preflight Sem Permissao', 'Dono Sem Permissao', '5511999999008',
      'preflight-sem-permissao@eaf.invalid', 'SenhaTeste123', 'premium'
    );
  exception when sqlstate '42501' then
    v_rejeitado := true;
  end;
  if not v_rejeitado or exists (select 1 from public.restaurantes where nome = 'Preflight Sem Permissao') then
    raise exception 'Preflight 12: usuario comum nao foi rejeitado.';
  end if;

  if (select count(*) from public.restaurantes) <> v_total_antes + 4 then
    raise exception 'Preflight 13: houve efeito colateral inesperado nas criacoes.';
  end if;
end;
$preflight_funcional$;

select
  (select count(*) from public.restaurantes where nome like 'Preflight %') as lojas_transacionais,
  (select count(*) from public.planos where ativo) as planos_ativos,
  (select count(*) from public.restaurantes r
    left join public.planos p on p.codigo = r.plano_codigo
    where p.codigo is null) as restaurantes_sem_plano_valido;
