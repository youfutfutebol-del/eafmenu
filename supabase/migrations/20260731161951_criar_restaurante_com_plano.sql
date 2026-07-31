-- Permite que novos cadastros do Super Admin escolham um plano ativo.
-- A assinatura legada com cinco parametros permanece inalterada e continua
-- usando o default temporario Premium definido em public.restaurantes.

create or replace function public.criar_restaurante_com_dono(
  p_nome_restaurante text,
  p_dono_nome text,
  p_dono_telefone text,
  p_dono_email text,
  p_dono_senha text,
  p_plano_codigo text
)
returns table (
  restaurante_id uuid,
  dono_id uuid,
  plano_codigo text,
  plano_nome text,
  plano_medalha text,
  plano_preco_mensal numeric(10,2)
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_restaurante_id uuid;
  v_dono_id uuid;
begin
  if auth.uid() is null or not public.eh_super_admin() then
    raise exception using
      message = 'Apenas administradores da plataforma podem criar restaurantes.',
      errcode = '42501';
  end if;

  if p_plano_codigo is null or btrim(p_plano_codigo) = '' then
    raise exception using message = 'Plano e obrigatorio.', errcode = '22023';
  end if;

  perform 1
  from public.planos p
  where p.codigo = p_plano_codigo
    and p.ativo
  for share;

  if not found then
    raise exception using
      message = 'Plano inexistente ou inativo.',
      errcode = '22023';
  end if;

  select criado.restaurante_id, criado.dono_id
    into v_restaurante_id, v_dono_id
  from public.criar_restaurante_com_dono(
    p_nome_restaurante,
    p_dono_nome,
    p_dono_telefone,
    p_dono_email,
    p_dono_senha
  ) criado;

  return query
  select atribuido.restaurante_id,
         v_dono_id,
         atribuido.plano_codigo,
         atribuido.plano_nome,
         atribuido.plano_medalha,
         atribuido.plano_preco_mensal
  from public.super_admin_definir_plano_restaurante(
    v_restaurante_id,
    p_plano_codigo
  ) atribuido;
end;
$function$;

revoke all on function public.criar_restaurante_com_dono(text, text, text, text, text, text)
  from public, anon;
grant execute on function public.criar_restaurante_com_dono(text, text, text, text, text, text)
  to authenticated, service_role;

comment on function public.criar_restaurante_com_dono(text, text, text, text, text, text) is
  'Cria restaurante e dono com plano ativo escolhido pelo Super Admin. A sobrecarga legada de cinco parametros permanece compativel.';
