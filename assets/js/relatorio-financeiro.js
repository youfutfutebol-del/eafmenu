// /assets/js/relatorio-financeiro.js
// Logica da aba Relatorio Financeiro. Usa apenas a RPC existente relatorio_financeiro_v1.
// Dependem de globais/funcoes: sb, showToast, formatMoedaRel (utils.js).

let relatorioFinanceiroCache = null;
let relatorioPeriodoAtual = 'hoje';
let relatorioPeriodoAtualDatas = null;

const REL_PERIODO_LABELS = {
  hoje: 'Hoje',
  semana: 'Ultimos 7 dias',
  mes: 'Este mes',
  personalizado: 'Periodo personalizado'
};

async function loadRelatorioFinanceiro() {
  document.getElementById('relErro').classList.add('hidden');
  relatorioPeriodoAtual = 'hoje';
  await buscarPeriodoRelatorio('hoje');
}

function dataLocalRel(date) {
  const ano = date.getFullYear();
  const mes = String(date.getMonth() + 1).padStart(2, '0');
  const dia = String(date.getDate()).padStart(2, '0');
  return `${ano}-${mes}-${dia}`;
}

function somarDiasRel(date, dias) {
  const d = new Date(date);
  d.setDate(d.getDate() + dias);
  return d;
}

function periodoDatasRel(periodo) {
  const hoje = new Date();
  const hojeStr = dataLocalRel(hoje);

  if (periodo === 'semana') {
    return { inicio: dataLocalRel(somarDiasRel(hoje, -6)), fim: hojeStr };
  }
  if (periodo === 'mes') {
    return { inicio: dataLocalRel(new Date(hoje.getFullYear(), hoje.getMonth(), 1)), fim: hojeStr };
  }
  if (periodo === 'personalizado') {
    const inicio = document.getElementById('relDataInicio').value || hojeStr;
    const fim = document.getElementById('relDataFim').value || hojeStr;
    return { inicio, fim };
  }
  return { inicio: hojeStr, fim: hojeStr };
}

function preencherDatasRelatorio(datas) {
  document.getElementById('relDataInicio').value = datas.inicio;
  document.getElementById('relDataFim').value = datas.fim;
}

async function buscarPeriodoRelatorio(periodo) {
  relatorioPeriodoAtual = periodo;
  const datas = periodoDatasRel(periodo);
  preencherDatasRelatorio(datas);
  await buscarRelatorioFinanceiro(datas.inicio, datas.fim);
}

async function buscarRelatorioFinanceiro(dataInicio, dataFim) {
  const { data, error } = await sb.rpc('relatorio_financeiro_v1', {
    p_data_inicio: dataInicio,
    p_data_fim: dataFim
  });
  if (error) { showToast('Nao foi possivel carregar o relatorio', error.message); return; }

  relatorioFinanceiroCache = data || {};
  relatorioPeriodoAtualDatas = { inicio: dataInicio, fim: dataFim };
  renderRelatorioFinanceiro(relatorioFinanceiroCache);
}

async function selecionarPeriodoRelatorio(periodo) {
  document.getElementById('relErro').classList.add('hidden');
  await buscarPeriodoRelatorio(periodo);
}

function atualizarTabsPeriodoRelatorio() {
  document.querySelectorAll('#relPeriodoTabs button').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.periodo === relatorioPeriodoAtual);
  });
}

function blocoPeriodoRelatorio(data) {
  return data?.periodo_personalizado || {};
}

function detalhesPeriodoRelatorio(data) {
  const p = data?.periodo_personalizado || {};
  const formas = p.por_forma_pagamento || {};
  const tipos = p.por_tipo || {};
  const topProdutos = p.top_produtos || [];
  const temDetalhes = !!data?.periodo_personalizado
    && typeof p.por_forma_pagamento === 'object'
    && typeof p.por_tipo === 'object'
    && Array.isArray(p.top_produtos);

  return { formas, tipos, topProdutos, disponivel: temDetalhes };
}

function taxaCancelamentoRel(bloco) {
  const cancelados = bloco.cancelados || {};
  if (typeof cancelados.percentual === 'number') return cancelados.percentual;
  const pedidos = Number(bloco.pedidos || 0);
  const qtdCancelados = Number(cancelados.pedidos || 0);
  const total = pedidos + qtdCancelados;
  return total > 0 ? Number(((qtdCancelados / total) * 100).toFixed(1)) : 0;
}

function formatarDataBRRel(valor) {
  if (!valor) return '';

  const data = String(valor).slice(0, 10);
  const partes = data.split('-');

  if (partes.length === 3) {
    const [ano, mes, dia] = partes;
    return `${dia}/${mes}/${ano}`;
  }

  return String(valor);
}

function tituloPeriodoRelatorio(bloco) {
  const inicio = bloco.data_inicio || relatorioPeriodoAtualDatas?.inicio || '';
  const fim = bloco.data_fim || relatorioPeriodoAtualDatas?.fim || '';

  if (inicio && fim) {
    const inicioFormatado = formatarDataBRRel(inicio);
    const fimFormatado = formatarDataBRRel(fim);

    if (String(inicio).slice(0, 10) === String(fim).slice(0, 10)) {
      return `Período: ${inicioFormatado}`;
    }

    return `Período: ${inicioFormatado} até ${fimFormatado}`;
  }

  return REL_PERIODO_LABELS[relatorioPeriodoAtual] || 'Período';
}
function renderTabelaChaveValorRel(tbodyId, obj) {
  const tbody = document.getElementById(tbodyId);
  const chaves = Object.keys(obj || {});
  if (chaves.length === 0) {
    tbody.innerHTML = `<tr><td colspan="2"><div class="relatorio-empty-mini">Nenhum dado disponivel para este periodo.</div></td></tr>`;
    return;
  }
  tbody.innerHTML = chaves.map(k => `
    <tr>
      <td data-label="Item">${k.charAt(0).toUpperCase() + k.slice(1)}</td>
      <td data-label="Faturamento">${formatMoedaRel(obj[k])}</td>
    </tr>`).join('');
}

function renderKpisRel(bloco) {
  const cancelados = bloco.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
  const taxa = taxaCancelamentoRel(bloco);
  document.getElementById('relKpiFaturamento').textContent = formatMoedaRel(bloco.faturamento || 0);
  document.getElementById('relKpiPedidos').textContent = bloco.pedidos || 0;
  document.getElementById('relKpiTicket').textContent = formatMoedaRel(bloco.ticket_medio || 0);
  document.getElementById('relKpiCancelados').textContent = cancelados.pedidos || 0;
  document.getElementById('relKpiValorCancelado').textContent = formatMoedaRel(cancelados.valor || 0);
  document.getElementById('relKpiTaxaCancelamento').textContent = `${taxa}%`;
}

function renderResumoRel(bloco) {
  const cancelados = bloco.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
  const pedidos = Number(bloco.pedidos || 0);
  const taxa = taxaCancelamentoRel(bloco);

  document.getElementById('relResumoTitulo').textContent = tituloPeriodoRelatorio(bloco);
  document.getElementById('relResumoDescricao').textContent =
    `${pedidos} pedido${pedidos === 1 ? '' : 's'} concluido${pedidos === 1 ? '' : 's'} no periodo selecionado.`;
  document.getElementById('relResumoFaturamento').textContent = formatMoedaRel(bloco.faturamento || 0);
  document.getElementById('relResumoPedidos').textContent = pedidos;
  document.getElementById('relResumoTicket').textContent = formatMoedaRel(bloco.ticket_medio || 0);
  document.getElementById('relResumoCancelados').textContent = cancelados.pedidos || 0;
  document.getElementById('relResumoValorCancelado').textContent = formatMoedaRel(cancelados.valor || 0);
  document.getElementById('relResumoTaxaCancelamento').textContent = `${taxa}%`;
}

function renderBarrasRel(containerId, obj, disponivel) {
  const wrap = document.getElementById(containerId);
  const entries = Object.entries(obj || {});
  if (!disponivel) {
    wrap.innerHTML = `<div class="relatorio-empty-mini">A RPC nao retornou detalhamento para este intervalo.</div>`;
    return;
  }
  if (entries.length === 0) {
    wrap.innerHTML = `<div class="relatorio-empty-mini">Nenhum dado disponivel para este periodo.</div>`;
    return;
  }

  const total = entries.reduce((s, [, valor]) => s + Number(valor || 0), 0);
  wrap.innerHTML = entries.map(([nome, valor]) => {
    const percentual = total > 0 ? Math.round((Number(valor || 0) / total) * 100) : 0;
    return `
      <div class="relatorio-bar-row">
        <div class="relatorio-bar-top"><span>${nome.charAt(0).toUpperCase() + nome.slice(1)}</span><b>${formatMoedaRel(valor)}</b></div>
        <div class="relatorio-bar-track"><span style="width:${percentual}%"></span></div>
      </div>`;
  }).join('');
}

function renderTopProdutosRel(lista, disponivel) {
  const wrap = document.getElementById('relTopProdutosVisual');
  if (!disponivel) {
    wrap.innerHTML = `<div class="relatorio-empty-mini">A RPC nao retornou top produtos para este intervalo.</div>`;
    return;
  }
  if (!lista || lista.length === 0) {
    wrap.innerHTML = `<div class="relatorio-empty-mini">Nenhuma venda no periodo.</div>`;
    return;
  }
  wrap.innerHTML = lista.map((p, i) => `
    <div class="relatorio-top-item">
      <span>${i + 1}</span>
      <b>${p.nome}</b>
      <em>${p.quantidade}x</em>
    </div>`).join('');
}

function renderInsightsRel(bloco, detalhes) {
  const cancelados = bloco.cancelados || { pedidos: 0, valor: 0 };
  const pedidos = Number(bloco.pedidos || 0);
  const taxa = taxaCancelamentoRel(bloco);
  const formas = Object.entries(detalhes.formas || {}).sort((a, b) => Number(b[1]) - Number(a[1]));
  const tipos = Object.entries(detalhes.tipos || {}).sort((a, b) => Number(b[1]) - Number(a[1]));
  const insights = [
    `Faturamento do periodo: ${formatMoedaRel(bloco.faturamento || 0)} em ${pedidos} pedido${pedidos === 1 ? '' : 's'} concluido${pedidos === 1 ? '' : 's'}.`,
    `Cancelamentos: ${cancelados.pedidos || 0} pedido${Number(cancelados.pedidos || 0) === 1 ? '' : 's'} (${taxa}%) somando ${formatMoedaRel(cancelados.valor || 0)}.`
  ];

  if (detalhes.disponivel && formas.length > 0) insights.push(`Forma de pagamento mais forte: ${formas[0][0]} (${formatMoedaRel(formas[0][1])}).`);
  if (detalhes.disponivel && tipos.length > 0) insights.push(`Canal com maior faturamento: ${tipos[0][0]} (${formatMoedaRel(tipos[0][1])}).`);
  if (!detalhes.disponivel) insights.push('A RPC nao retornou por_forma_pagamento, por_tipo e top_produtos para este intervalo.');

  document.getElementById('relInsightsBody').innerHTML = insights.map(txt => `<div class="relatorio-insight">${txt}</div>`).join('');
}

function renderRelatorioFinanceiro(data) {
  relatorioFinanceiroCache = data || {};
  atualizarTabsPeriodoRelatorio();

  const bloco = blocoPeriodoRelatorio(data);
  const detalhes = detalhesPeriodoRelatorio(data);
  renderKpisRel(bloco);
  renderResumoRel(bloco);
  renderBarrasRel('relFormaPagamentoVisual', detalhes.formas, detalhes.disponivel);
  renderBarrasRel('relTipoVisual', detalhes.tipos, detalhes.disponivel);
  renderTopProdutosRel(detalhes.topProdutos, detalhes.disponivel);
  renderTabelaChaveValorRel('relFormaPagamentoBody', detalhes.disponivel ? detalhes.formas : {});
  renderTabelaChaveValorRel('relTipoBody', detalhes.disponivel ? detalhes.tipos : {});
  renderInsightsRel(bloco, detalhes);
}

async function aplicarPeriodoRelatorio() {
  const inicio = document.getElementById('relDataInicio').value;
  const fim = document.getElementById('relDataFim').value;
  const erroEl = document.getElementById('relErro');
  erroEl.classList.add('hidden');

  if (!inicio || !fim) {
    erroEl.textContent = 'Escolha as duas datas.';
    erroEl.classList.remove('hidden');
    return;
  }
  if (inicio > fim) {
    erroEl.textContent = 'A data de inicio nao pode ser depois da data de fim.';
    erroEl.classList.remove('hidden');
    return;
  }

  relatorioPeriodoAtual = 'personalizado';
  preencherDatasRelatorio({ inicio, fim });
  await buscarRelatorioFinanceiro(inicio, fim);
}
