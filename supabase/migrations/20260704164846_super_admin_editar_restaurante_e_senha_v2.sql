drop function if exists public.listar_restaurantes_plataforma();

create or replace function public.listar_restaurantes_plataforma()
returns table(id uuid, nome text, slug text, criado_em timestamptz, total_usuarios bigint, dono_id uuid, dono_nome text, dono_telefone text)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not eh_super_admin() then
    raise exception 'Só administradores da plataforma podem ver essa lista.';
  end if;

  return query
  select r.id, r.nome, r.slug, r.criado_em, count(u.id),
    (select u2.id from usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em asc limit 1),
    (select u2.nome from usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em asc limit 1),
    (select u2.telefone from usuarios u2 where u2.restaurante_id = r.id and u2.role = 'dono' order by u2.criado_em asc limit 1)
  from restaurantes r
  left join usuarios u on u.restaurante_id = r.id
  group by r.id, r.nome, r.slug, r.criado_em
  order by r.criado_em desc;
end;
$$;
grant execute on function listar_restaurantes_plataforma() to authenticated;
