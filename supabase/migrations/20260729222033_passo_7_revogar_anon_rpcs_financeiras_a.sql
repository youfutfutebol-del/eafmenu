begin;

revoke all on function public.abrir_caixa_v2(numeric)
from public, anon;

revoke all on function public.fechar_caixa_v2(numeric, text)
from public, anon;

revoke all on function public.registrar_despesa_v2(text, numeric, text)
from public, anon;

revoke all on function public.registrar_ajuste_financeiro_v1(uuid, text)
from public, anon;

revoke all on function public.listar_movimentacoes_financeiras_v2(text)
from public, anon;

revoke all on function public.listar_movimentos_dinheiro_sem_caixa_v1(date, date)
from public, anon;

grant execute on function public.abrir_caixa_v2(numeric)
to authenticated, service_role;

grant execute on function public.fechar_caixa_v2(numeric, text)
to authenticated, service_role;

grant execute on function public.registrar_despesa_v2(text, numeric, text)
to authenticated, service_role;

grant execute on function public.registrar_ajuste_financeiro_v1(uuid, text)
to authenticated, service_role;

grant execute on function public.listar_movimentacoes_financeiras_v2(text)
to authenticated, service_role;

grant execute on function public.listar_movimentos_dinheiro_sem_caixa_v1(date, date)
to authenticated, service_role;

commit;