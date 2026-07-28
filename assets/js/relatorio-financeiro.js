// /assets/js/relatorio-financeiro.js
// Recriado do zero (redesign do dashboard financeiro).
// Único ponto de entrada externo: loadRelatorioFinanceiro(), chamada por switchView('relatorio')
// no script principal do index.html — esse nome precisa continuar existindo com essa assinatura.
//
// Estratégia: para QUALQUER filtro (Hoje, Últimos 7 dias, Este mês ou Personalizado),
// sempre chamamos a RPC com datas explícitas e usamos só o bloco `periodo_personalizado`
// como fonte de dados — um único caminho de renderização pros 4 filtros.
//
// Depende de: sb, showToast, formatMoedaRel (utils.js). Continua global (sem type=module).

  let relFiltroAtivo = 'hoje';       // 'hoje' | 'semana' | 'mes' | 'personalizado'
  let relDiaComercialRef = null;     // 'YYYY-MM-DD', vem do servidor (respeita o corte às 7h)
  let relDadosAtuais = null;         // último periodo_personalizado retornado — usado pela auditoria

  // =====================================================================
  // HELPERS DE DATA (strings 'YYYY-MM-DD', sem depender de fuso do navegador)
  // =====================================================================
  function relParseISO(iso) {
    return new Date(iso + 'T00:00:00');
  }

  function relParaISO(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  function relSomarDias(iso, n) {
    const d = relParseISO(iso);
    d.setDate(d.getDate() + n);
    return relParaISO(d);
  }

  function relInicioDoMes(iso) {
    const d = relParseISO(iso);
    return relParaISO(new Date(d.getFullYear(), d.getMonth(), 1));
  }

  function relFormatarDataBR(iso) {
    if (!iso) return '—';
    const [y, m, d] = iso.split('-');
    return `${d}/${m}/${y}`;
  }

  function relFormatarPeriodoBR(inicio, fim) {
    if (!inicio || !fim) return '—';
    return inicio === fim ? relFormatarDataBR(inicio) : `${relFormatarDataBR(inicio)} até ${relFormatarDataBR(fim)}`;
  }

  // =====================================================================
  // ENTRADA PRINCIPAL
  // =====================================================================
  async function loadRelatorioFinanceiro() {
    document.getElementById('relDataInicio').value = '';
    document.getElementById('relDataFim').value = '';
    document.getElementById('relErro').classList.add('hidden');
    relDiaComercialRef = null;
    await setRelFiltro('hoje');
  }

  async function setRelFiltro(filtro) {
    relFiltroAtivo = filtro;
    document.querySelectorAll('.rel-chip').forEach(el => el.classList.toggle('active', el.dataset.filtro === filtro));
    document.getElementById('relPersonalizadoBox').classList.toggle('show', filtro === 'personalizado');

    // No modo personalizado, só busca quando a pessoa clicar em "Aplicar período".
    if (filtro === 'personalizado') return;

    await relBuscarPeriodo();
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
      erroEl.textContent = 'A data de início não pode ser depois da data de fim.';
      erroEl.classList.remove('hidden');
      return;
    }
    await relBuscarPeriodo(inicio, fim);
  }

  async function relBuscarPeriodo(dataInicioForcada, dataFimForcada) {
    const erroEl = document.getElementById('relErro');
    erroEl.classList.add('hidden');

    try {
      // Primeira carga: descobre o "dia comercial" oficial do servidor (corte às 7h),
      // pra Hoje/Semana/Mês sempre baterem com o resto do painel.
      if (!relDiaComercialRef) {
        const { data, error } = await sb.rpc('relatorio_financeiro_v2', { p_data_inicio: null, p_data_fim: null });
        if (error) throw error;
        relDiaComercialRef = data.dia_comercial_referencia;
      }

      let dataInicio, dataFim;
      if (dataInicioForcada) {
        dataInicio = dataInicioForcada;
        dataFim = dataFimForcada;
      } else if (relFiltroAtivo === 'semana') {
        dataInicio = relSomarDias(relDiaComercialRef, -6);
        dataFim = relDiaComercialRef;
      } else if (relFiltroAtivo === 'mes') {
        dataInicio = relInicioDoMes(relDiaComercialRef);
        dataFim = relDiaComercialRef;
      } else {
        dataInicio = relDiaComercialRef;
        dataFim = relDiaComercialRef;
      }

      const { data, error } = await sb.rpc('relatorio_financeiro_v2', { p_data_inicio: dataInicio, p_data_fim: dataFim });
      if (error) throw error;

      relDadosAtuais = data.periodo_personalizado;
      relRenderTudo(relDadosAtuais);
    } catch (e) {
      showToast('Erro ao carregar relatório', e.message);
    }
  }

  // =====================================================================
  // RENDERIZAÇÃO
  // =====================================================================
  function relRenderTudo(p) {
    if (!p) return;
    relRenderKpis(p);
    relRenderResumo(p);
    relRenderBarras('relFormaPagamentoBars', p.por_forma_pagamento);
    relRenderBarras('relTipoBars', p.por_tipo);
    relRenderTabela('relFormaPagamentoBody', p.por_forma_pagamento, 'Recebido');
    relRenderTabela('relTipoBody', p.por_tipo);
    relRenderTopProdutos(p.top_produtos);
    relRenderInsights(p);
  }

  function relRenderKpis(p) {
    const cancelados = p.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
    const vendido = p.vendido || { pedidos: 0, valor: 0 };
    const recebido = p.recebido || { pedidos: 0, valor: 0 };
    const recebidoBruto = p.recebido_bruto || { pedidos: recebido.pedidos || 0, valor: recebido.valor || 0 };
    const estornado = p.estornado || { pedidos: 0, valor: 0 };
    const cancelamentosPendentes = p.cancelamentos_pagos_pendentes || { pedidos: 0, valor: 0 };
    const pendente = p.pendente || { pedidos: 0, valor: 0 };

    document.getElementById('relKpiVendido').textContent = formatMoedaRel(vendido.valor);
    document.getElementById('relKpiVendidoSub').textContent =
      `${vendido.pedidos} pedido${vendido.pedidos === 1 ? '' : 's'} vendido${vendido.pedidos === 1 ? '' : 's'}`;
    document.getElementById('relKpiRecebido').textContent = formatMoedaRel(recebido.valor);
    document.getElementById('relKpiRecebidoSub').textContent =
      `${recebido.pedidos} pedido${recebido.pedidos === 1 ? '' : 's'} recebido${recebido.pedidos === 1 ? '' : 's'}`;
    document.getElementById('relKpiRecebidoBruto').textContent = formatMoedaRel(recebidoBruto.valor);
    document.getElementById('relKpiEstornado').textContent = formatMoedaRel(estornado.valor);
    document.getElementById('relKpiEstornadoSub').textContent =
      `${estornado.pedidos} pedido${estornado.pedidos === 1 ? '' : 's'} estornado${estornado.pedidos === 1 ? '' : 's'}`;
    document.getElementById('relKpiCancelamentosPendentes').textContent = formatMoedaRel(cancelamentosPendentes.valor);
    document.getElementById('relKpiCancelamentosPendentesSub').textContent =
      `${cancelamentosPendentes.pedidos} aguardando decisão`;
    document.getElementById('relKpiPendente').textContent = formatMoedaRel(pendente.valor);
    document.getElementById('relKpiPendenteSub').textContent =
      `${pendente.pedidos} pedido${pendente.pedidos === 1 ? '' : 's'} pendente${pendente.pedidos === 1 ? '' : 's'}`;
    document.getElementById('relKpiTicket').textContent = formatMoedaRel(p.ticket_medio);
    document.getElementById('relKpiCancelados').textContent = cancelados.pedidos;
    document.getElementById('relKpiValorCancelado').textContent = formatMoedaRel(cancelados.valor);
    document.getElementById('relKpiTaxa').textContent = `${cancelados.percentual}%`;
    const alertaEl = document.getElementById('relAlertaCancelamentosPendentes');
    alertaEl.classList.toggle('hidden', cancelamentosPendentes.pedidos <= 0);
    alertaEl.textContent = cancelamentosPendentes.pedidos > 0
      ? `Existem ${cancelamentosPendentes.pedidos} cancelamentos pagos, totalizando ${formatMoedaRel(cancelamentosPendentes.valor)}, aguardando decisão financeira.`
      : '';
  }

  function relRenderResumo(p) {
    const cancelados = p.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
    const vendido = p.vendido || { pedidos: 0, valor: 0 };
    const recebido = p.recebido || { pedidos: 0, valor: 0 };
    const recebidoBruto = p.recebido_bruto || { pedidos: recebido.pedidos || 0, valor: recebido.valor || 0 };
    const estornado = p.estornado || { pedidos: 0, valor: 0 };
    const cancelamentosPendentes = p.cancelamentos_pagos_pendentes || { pedidos: 0, valor: 0 };
    const pendente = p.pendente || { pedidos: 0, valor: 0 };
    document.getElementById('relResumoData').textContent = relFormatarPeriodoBR(p.data_inicio, p.data_fim);

    const stats = [
      { lbl: 'Vendido', val: formatMoedaRel(vendido.valor) },
      { lbl: 'Recebido líquido', val: formatMoedaRel(recebido.valor) },
      { lbl: 'Recebido bruto', val: formatMoedaRel(recebidoBruto.valor) },
      { lbl: 'Estornado', val: formatMoedaRel(estornado.valor), destaque: true },
      { lbl: 'Decisão pendente', val: formatMoedaRel(cancelamentosPendentes.valor), pendente: true },
      { lbl: 'Pendente', val: formatMoedaRel(pendente.valor), pendente: true },
      { lbl: 'Ticket médio', val: formatMoedaRel(p.ticket_medio) },
      { lbl: 'Cancelados', val: String(cancelados.pedidos), destaque: true },
      { lbl: 'Taxa de cancelamento', val: `${cancelados.percentual}%`, destaque: true }
    ];

    document.getElementById('relResumoStats').innerHTML = stats.map(s => `
      <div class="rel-resumo__stat ${s.destaque ? 'destaque' : ''} ${s.pendente ? 'pendente' : ''}">
        <span class="lbl">${s.lbl}</span>
        <span class="val">${s.val}</span>
      </div>`).join('');
  }

  function relRenderBarras(containerId, objValores) {
    const el = document.getElementById(containerId);
    const entradas = Object.entries(objValores || {});
    if (entradas.length === 0) {
      el.innerHTML = `<div class="empty-state"><div class="ic">📊</div><h4>Sem dados no período</h4></div>`;
      return;
    }
    const total = entradas.reduce((s, [, v]) => s + Number(v), 0);
    el.innerHTML = entradas
      .sort((a, b) => Number(b[1]) - Number(a[1]))
      .map(([chave, valor]) => {
        const pct = total > 0 ? (Number(valor) / total) * 100 : 0;
        const nome = escapeHtml(chave.charAt(0).toUpperCase() + chave.slice(1));
        return `
          <div class="rel-bar-row">
            <div class="rel-bar-row__top">
              <span>${nome}</span>
              <span class="valor">${formatMoedaRel(valor)} · ${pct.toFixed(1)}%</span>
            </div>
            <div class="rel-bar-track"><div class="rel-bar-fill" style="width:${pct.toFixed(1)}%"></div></div>
          </div>`;
      }).join('');
  }

  function relRenderTabela(tbodyId, objValores, valorLabel = 'Faturamento') {
    const tbody = document.getElementById(tbodyId);
    const entradas = Object.entries(objValores || {});
    if (entradas.length === 0) {
      tbody.innerHTML = `<tr><td colspan="3"><div class="empty-state"><div class="ic">💲</div><h4>Nenhum dado no período</h4></div></td></tr>`;
      return;
    }
    const total = entradas.reduce((s, [, v]) => s + Number(v), 0);
    tbody.innerHTML = entradas
      .sort((a, b) => Number(b[1]) - Number(a[1]))
      .map(([chave, valor]) => {
        const pct = total > 0 ? (Number(valor) / total) * 100 : 0;
        const nome = escapeHtml(chave.charAt(0).toUpperCase() + chave.slice(1));
        return `
          <tr>
            <td data-label="Item">${nome}</td>
            <td data-label="${valorLabel}">${formatMoedaRel(valor)}</td>
            <td data-label="%">${pct.toFixed(1)}%</td>
          </tr>`;
      }).join('');
  }

  function relRenderTopProdutos(lista) {
    const el = document.getElementById('relTopProdutosLista');
    if (!lista || lista.length === 0) {
      el.innerHTML = `<div class="empty-state"><div class="ic">🍽️</div><h4>Nenhuma venda no período</h4></div>`;
      return;
    }
    const maiorQtd = Math.max(...lista.map(p => Number(p.quantidade)));
    el.innerHTML = lista.map((p, i) => {
      const pct = maiorQtd > 0 ? (Number(p.quantidade) / maiorQtd) * 100 : 0;
      return `
        <div class="rel-top-item">
          <span class="rel-top-item__pos">${i + 1}</span>
          <span class="rel-top-item__nome">${escapeHtml(p.nome)}</span>
          <span class="rel-top-item__qtd">${Number(p.quantidade || 0)}x</span>
          <div class="rel-top-item__barra"><div class="rel-top-item__barra-fill" style="width:${pct.toFixed(1)}%"></div></div>
        </div>`;
    }).join('');
  }

  function relRenderInsights(p) {
    const el = document.getElementById('relInsights');
    const cancelados = p.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
    const vendido = p.vendido || { pedidos: 0, valor: 0 };
    const recebido = p.recebido || { pedidos: 0, valor: 0 };
    const recebidoBruto = p.recebido_bruto || { pedidos: recebido.pedidos || 0, valor: recebido.valor || 0 };
    const estornado = p.estornado || { pedidos: 0, valor: 0 };
    const cancelamentosPendentes = p.cancelamentos_pagos_pendentes || { pedidos: 0, valor: 0 };
    const pendente = p.pendente || { pedidos: 0, valor: 0 };
    const insights = [];

    insights.push(`Vendido no período: <b>${formatMoedaRel(vendido.valor)}</b>, em <b>${vendido.pedidos}</b> pedido${vendido.pedidos === 1 ? '' : 's'}.`);
    insights.push(`Recebido líquido: <b>${formatMoedaRel(recebido.valor)}</b> (${formatMoedaRel(recebidoBruto.valor)} bruto menos ${formatMoedaRel(estornado.valor)} estornado).`);
    insights.push(`Pendente de recebimento: <b>${formatMoedaRel(pendente.valor)}</b>, em <b>${pendente.pedidos}</b> pedido${pendente.pedidos === 1 ? '' : 's'}.`);
    if (cancelamentosPendentes.pedidos > 0) {
      insights.push(`<b>${cancelamentosPendentes.pedidos}</b> cancelamento${cancelamentosPendentes.pedidos === 1 ? '' : 's'} pago${cancelamentosPendentes.pedidos === 1 ? '' : 's'}, totalizando <b>${formatMoedaRel(cancelamentosPendentes.valor)}</b>, aguardando decisão financeira.`);
    }

    if (cancelados.pedidos > 0) {
      insights.push(`<b>${cancelados.pedidos}</b> pedido${cancelados.pedidos === 1 ? '' : 's'} cancelado${cancelados.pedidos === 1 ? '' : 's'}, totalizando <b>${formatMoedaRel(cancelados.valor)}</b> (${cancelados.percentual}% dos pedidos do período).`);
    } else {
      insights.push(`Nenhum cancelamento nesse período.`);
    }

    const formas = Object.entries(p.por_forma_pagamento || {});
    if (formas.length > 0) {
      const [nomeForma] = formas.sort((a, b) => Number(b[1]) - Number(a[1]))[0];
      insights.push(`Forma com maior valor recebido: <b>${escapeHtml(nomeForma.charAt(0).toUpperCase() + nomeForma.slice(1))}</b>.`);
    }

    const tipos = Object.entries(p.por_tipo || {});
    if (tipos.length > 0) {
      const [nomeTipo] = tipos.sort((a, b) => Number(b[1]) - Number(a[1]))[0];
      insights.push(`Canal com maior faturamento: <b>${escapeHtml(nomeTipo.charAt(0).toUpperCase() + nomeTipo.slice(1))}</b>.`);
    }

    el.innerHTML = insights.map(txt => `<div class="rel-insight-card">${txt}</div>`).join('');
  }

  // =====================================================================
  // AUDITORIA DE CANCELAMENTOS (clique nos cards Cancelados / Valor cancelado)
  // =====================================================================
  async function abrirCancelamentosPeriodo() {
    if (!relDadosAtuais) return;

    document.getElementById('cancelamentosPeriodoLabel').textContent = 'Carregando...';
    document.getElementById('cancelamentosPeriodoLista').innerHTML = '';
    document.getElementById('cancelamentosPeriodoModalBg').classList.add('show');

    const { data, error } = await sb.rpc('relatorio_cancelamentos_v1', {
      p_periodo: 'personalizado',
      p_data_inicio: relDadosAtuais.data_inicio,
      p_data_fim: relDadosAtuais.data_fim
    });

    if (error) {
      document.getElementById('cancelamentosPeriodoLabel').textContent = 'Erro ao carregar';
      document.getElementById('cancelamentosPeriodoLista').innerHTML =
        `<p class="main__subtitle" style="color:var(--red);">${escapeHtml(error.message)}</p>`;
      return;
    }

    try {
      const dadosEnriquecidos = await enriquecerCancelamentosPeriodo(data);
      renderCancelamentosPeriodo(dadosEnriquecidos);
    } catch (e) {
      document.getElementById('cancelamentosPeriodoLabel').textContent = 'Erro ao carregar';
      document.getElementById('cancelamentosPeriodoLista').innerHTML =
        `<p class="main__subtitle" style="color:var(--red);">${escapeHtml(e.message || 'Não foi possível completar os dados financeiros dos cancelamentos.')}</p>`;
    }
  }

  async function enriquecerCancelamentosPeriodo(data) {
    const cancelamentos = data?.cancelamentos || [];
    const pedidoIds = [...new Set(cancelamentos.map(item => item.pedido_id).filter(Boolean))];
    if (pedidoIds.length === 0) return data;

    const TAMANHO_BLOCO = 100;
    const pedidosFinanceiros = [];
    for (let inicio = 0; inicio < pedidoIds.length; inicio += TAMANHO_BLOCO) {
      const blocoIds = pedidoIds.slice(inicio, inicio + TAMANHO_BLOCO);
      const { data: pedidosBloco, error } = await sb.from('pedidos')
        .select('id, pago, cancelamento_decisao_financeira, cancelamento_decisao_financeira_em')
        .eq('restaurante_id', restauranteId)
        .in('id', blocoIds);
      if (error) throw new Error(`Não foi possível completar os dados financeiros dos cancelamentos: ${error.message}`);
      pedidosFinanceiros.push(...(pedidosBloco || []));
    }

    const financeirosPorId = new Map(pedidosFinanceiros.map(pedido => [pedido.id, pedido]));
    const idsSemDados = pedidoIds.filter(id => !financeirosPorId.has(id));
    if (idsSemDados.length > 0) {
      throw new Error('Não foi possível completar os dados financeiros de todos os cancelamentos.');
    }

    return {
      ...data,
      cancelamentos: cancelamentos.map(cancelamento => ({
        ...cancelamento,
        ...financeirosPorId.get(cancelamento.pedido_id)
      }))
    };
  }

  function fecharCancelamentosPeriodo() {
    document.getElementById('cancelamentosPeriodoModalBg').classList.remove('show');
  }

  function renderCancelamentosPeriodo(data) {
    const labelEl = document.getElementById('cancelamentosPeriodoLabel');
    const listaEl = document.getElementById('cancelamentosPeriodoLista');
    labelEl.textContent =
      `${relFormatarPeriodoBR(data.data_inicio, data.data_fim)} · ${data.total_cancelamentos} cancelamento${data.total_cancelamentos === 1 ? '' : 's'} · ${formatMoedaRel(data.valor_total_cancelado)}`;

    const lista = data.cancelamentos || [];
    if (lista.length === 0) {
      listaEl.innerHTML = `<div class="empty-state"><div class="ic">✕</div><h4>Nenhum cancelamento nesse período.</h4></div>`;
      return;
    }

    listaEl.innerHTML = lista.map(c => {
      const codigo = c.numero_diario != null ? ('#' + c.numero_diario) : ('#' + c.pedido_id.slice(0, 8).toUpperCase());
      const dataCancel = c.cancelado_em ? new Date(c.cancelado_em).toLocaleString('pt-BR') : '—';
      const autorizadoLinha = (c.autorizado_por_nome && c.autorizado_por_nome !== c.cancelado_por_nome)
        ? ` · autorizado por ${escapeHtml(c.autorizado_por_nome)}`
        : '';
      const estadoFinanceiro = c.cancelamento_decisao_financeira;
      const financeiroLinha = estadoFinanceiro === 'estornado'
        ? '<div class="cancel-item-financeiro cancel-item-financeiro--estornado">Valor estornado</div>'
        : estadoFinanceiro === 'mantido'
          ? '<div class="cancel-item-financeiro cancel-item-financeiro--mantido">Valor mantido</div>'
          : estadoFinanceiro === 'pendente'
            ? '<div class="cancel-item-financeiro cancel-item-financeiro--pendente">Decisão financeira pendente</div>'
            : c.pago === false || estadoFinanceiro === 'nao_aplicavel'
              ? '<div class="cancel-item-financeiro cancel-item-financeiro--neutro">Sem impacto financeiro</div>'
              : '';
      return `
        <div class="cancel-item-row">
          <div class="cancel-item-top">
            <span class="cancel-item-codigo">${escapeHtml(codigo)} · ${escapeHtml(c.cliente_nome || 'Cliente')}</span>
            <span class="cancel-item-valor">${formatMoedaRel(c.total)}</span>
          </div>
          <div class="cancel-item-meta">Estava: ${escapeHtml(c.status_anterior || '—')} · ${escapeHtml(c.tipo || '—')} · cancelado em ${escapeHtml(dataCancel)}</div>
          <div class="cancel-item-meta">Por ${escapeHtml(c.cancelado_por_nome || '—')}${autorizadoLinha}</div>
          <div class="cancel-item-motivo">${escapeHtml(c.motivo_cancelamento || 'Sem motivo informado')}</div>
          ${financeiroLinha}
        </div>`;
    }).join('');
  }

  // =====================================================================
  // EXPORTAR CSV (período atualmente selecionado, mesma fonte da tela: relDadosAtuais)
  // =====================================================================
  function relNumeroCSV(n) {
    return Number(n || 0).toFixed(2).replace('.', ',');
  }

  function exportarRelatorioFinanceiro() {
    if (!relDadosAtuais) {
      showToast('Nada para exportar', 'Carregue um período primeiro.');
      return;
    }

    const p = relDadosAtuais;
    const cancelados = p.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
    const vendido = p.vendido || { pedidos: 0, valor: 0 };
    const recebido = p.recebido || { pedidos: 0, valor: 0 };
    const recebidoBruto = p.recebido_bruto || { pedidos: recebido.pedidos || 0, valor: recebido.valor || 0 };
    const estornado = p.estornado || { pedidos: 0, valor: 0 };
    const cancelamentosPendentes = p.cancelamentos_pagos_pendentes || { pedidos: 0, valor: 0 };
    const pendente = p.pendente || { pedidos: 0, valor: 0 };
    const linhas = [];

    linhas.push('Relatório Financeiro');
    linhas.push(`Período;${relFormatarPeriodoBR(p.data_inicio, p.data_fim)}`);
    linhas.push('');
    linhas.push(`Vendido;${relNumeroCSV(vendido.valor)}`);
    linhas.push(`Pedidos vendidos;${vendido.pedidos}`);
    linhas.push(`Recebido líquido;${relNumeroCSV(recebido.valor)}`);
    linhas.push(`Pedidos recebidos;${recebido.pedidos}`);
    linhas.push(`Recebido bruto;${relNumeroCSV(recebidoBruto.valor)}`);
    linhas.push(`Estornado;${relNumeroCSV(estornado.valor)}`);
    linhas.push(`Pedidos estornados;${estornado.pedidos}`);
    linhas.push(`Cancelamentos pagos pendentes;${cancelamentosPendentes.pedidos}`);
    linhas.push(`Valor pendente de decisão;${relNumeroCSV(cancelamentosPendentes.valor)}`);
    linhas.push(`Pendente;${relNumeroCSV(pendente.valor)}`);
    linhas.push(`Pedidos pendentes;${pendente.pedidos}`);
    linhas.push(`Ticket médio;${relNumeroCSV(p.ticket_medio)}`);
    linhas.push(`Cancelamentos;${cancelados.pedidos}`);
    linhas.push('');

    linhas.push('Valores recebidos por forma de pagamento');
    linhas.push('Forma;Valor');
    const formas = Object.entries(p.por_forma_pagamento || {});
    if (formas.length === 0) {
      linhas.push('Nenhum dado no período;');
    } else {
      formas.forEach(([nome, valor]) => {
        linhas.push(`${nome.charAt(0).toUpperCase() + nome.slice(1)};${relNumeroCSV(valor)}`);
      });
    }
    linhas.push('');

    linhas.push('Entrega x Retirada');
    linhas.push('Tipo;Valor');
    const tipos = Object.entries(p.por_tipo || {});
    if (tipos.length === 0) {
      linhas.push('Nenhum dado no período;');
    } else {
      tipos.forEach(([nome, valor]) => {
        linhas.push(`${nome.charAt(0).toUpperCase() + nome.slice(1)};${relNumeroCSV(valor)}`);
      });
    }
    linhas.push('');

    linhas.push('Top produtos');
    linhas.push('Produto;Quantidade');
    const produtos = p.top_produtos || [];
    if (produtos.length === 0) {
      linhas.push('Nenhuma venda no período;');
    } else {
      produtos.forEach(prod => {
        linhas.push(`${prod.nome};${prod.quantidade}`);
      });
    }

    // BOM (\uFEFF) garante acentuação correta ao abrir no Excel.
    const conteudoCsv = '\uFEFF' + linhas.join('\r\n');
    const blob = new Blob([conteudoCsv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = `relatorio-financeiro-${p.data_inicio}-a-${p.data_fim}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }
