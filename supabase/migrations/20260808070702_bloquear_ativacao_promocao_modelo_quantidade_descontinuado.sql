-- =========================================================
-- Fecha o risco encontrado na revisão pós-fix da migration anterior
-- (20260808064940_desativar_motor_campanha_antiga_condicao_beneficio):
-- o admin ainda oferecia criar/ativar uma campanha "Quantidade (clássico:
-- condição + benefício)" (modelo = 'quantidade'). ativar_promocao()
-- continuava validando e ativando esse modelo normalmente, mas a única
-- engrenagem que algum dia aplicou esse tipo de desconto em um pedido
-- (trg_recalcular_campanha_pedido / _aplicar_melhor_campanha_pedido) foi
-- desligada na migration anterior. Sem essa trava, uma campanha desse
-- tipo ativaria "com sucesso" e nunca aplicaria desconto em nenhum
-- pedido — silenciosamente, sem erro em lugar nenhum.
--
-- Não existe hoje nenhuma campanha com modelo <> 'etapas' em nenhum
-- restaurante, então isso é preventivo. ativar_promocao() agora recusa
-- ativar modelo='quantidade' com mensagem clara. O ramo de validação de
-- escopo condição/benefício do modelo antigo foi removido por ficar
-- inalcançável.
-- =========================================================

CREATE OR REPLACE FUNCTION public.ativar_promocao(p_promocao_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_promo promocoes%rowtype;
  v_chamador usuarios%rowtype;
  v_qtd_etapas int;
  v_qtd_etapas_beneficio int;
  v_qtd_etapas_sem_item int;
begin
  select * into v_chamador from usuarios where id = auth.uid();
  if not found or v_chamador.role not in ('dono','gerente') then raise exception 'Sem permissao para ativar campanha.'; end if;

  select * into v_promo from promocoes where id = p_promocao_id for update;
  if not found or v_promo.restaurante_id <> v_chamador.restaurante_id then raise exception 'Campanha nao encontrada neste restaurante.'; end if;
  if v_promo.arquivado_em is not null then raise exception 'Campanha arquivada nao pode ser ativada.'; end if;

  if v_promo.modelo <> 'etapas' then
    raise exception 'Modelo de campanha "quantidade" (classico: condicao + beneficio) foi descontinuado. Recadastre esta campanha usando o modelo "Etapas".';
  end if;

  select count(*) into v_qtd_etapas from promocao_etapas where promocao_id = p_promocao_id;
  if v_qtd_etapas < 2 then raise exception 'Campanha por etapas precisa de pelo menos 2 etapas.'; end if;

  select count(*) into v_qtd_etapas_beneficio from promocao_etapas where promocao_id = p_promocao_id and eh_beneficio = true;
  if v_qtd_etapas_beneficio < 1 then raise exception 'Campanha por etapas precisa de pelo menos uma etapa marcada como beneficio.'; end if;

  select count(*) into v_qtd_etapas_sem_item
  from promocao_etapas e
  where e.promocao_id = p_promocao_id
    and not exists (select 1 from promocao_etapa_itens i where i.etapa_id = e.id);
  if v_qtd_etapas_sem_item > 0 then raise exception 'Todas as etapas precisam ter pelo menos um produto ou categoria definido.'; end if;

  perform set_config('eafmenu.via_rpc_gestao_promocao', 'true', true);
  update promocoes set ativo = true where id = p_promocao_id;
end;
$function$;
