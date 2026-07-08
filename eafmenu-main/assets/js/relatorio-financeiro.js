// /assets/js/relatorio-financeiro.js
// Recriado do zero (redesign do dashboard financeiro).
// Único ponto de entrada externo: loadRelatorioFinanceiro(), chamada por switchView('relatorio')
// no script principal do index.html — esse nome precisa continuar existindo com essa assinatura.
//
// Estratégia: a RPC relatorio_financeiro_v1 só devolve formas de pagamento / entrega x retirada /
// top produtos completos dentro do bloco `periodo_personalizado` (os blocos hoje/semana/mes trazem
// só faturamento/pedidos/ticket_medio/cancelados). Por isso, para QUALQUER filtro (Hoje, Últimos 7
// dias, Este mês ou Personalizado), sempre chamamos a RPC com datas explícitas e usamos só o bloco
// periodo_personalizado como fonte de dados — um único caminho de renderização pros 4 filtros.
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
        const { data, error } = await sb.rpc('relatorio_financeiro_v1', { p_data_inicio: null, p_data_fim: null });
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

      const { data, error } = await sb.rpc('relatorio_financeiro_v1', { p_data_inicio: dataInicio, p_data_fim: dataFim });
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
    relRenderTabela('relFormaPagamentoBody', p.por_forma_pagamento);
    relRenderTabela('relTipoBody', p.por_tipo);
    relRenderTopProdutos(p.top_produtos);
    relRenderInsights(p);
  }

  function relRenderKpis(p) {
    const cancelados = p.cancelados || { pedidos: 0, valor: 0, percentual: 0 };

    document.getElementById('relKpiFaturamento').textContent = formatMoedaRel(p.faturamento);
    document.getElementById('relKpiFaturamentoSub').textContent =
      `${p.pedidos} pedido${p.pedidos === 1 ? '' : 's'} concluído${p.pedidos === 1 ? '' : 's'}`;
    document.getElementById('relKpiPedidos').textContent = p.pedidos;
    document.getElementById('relKpiTicket').textContent = formatMoedaRel(p.ticket_medio);
    document.getElementById('relKpiCancelados').textContent = cancelados.pedidos;
    document.getElementById('relKpiValorCancelado').textContent = formatMoedaRel(cancelados.valor);
    document.getElementById('relKpiTaxa').textContent = `${cancelados.percentual}%`;
  }

  function relRenderResumo(p) {
    const cancelados = p.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
    document.getElementById('relResumoData').textContent = relFormatarPeriodoBR(p.data_inicio, p.data_fim);

    const stats = [
      { lbl: 'Faturamento', val: formatMoedaRel(p.faturamento) },
      { lbl: 'Pedidos concluídos', val: String(p.pedidos) },
      { lbl: 'Ticket médio', val: formatMoedaRel(p.ticket_medio) },
      { lbl: 'Cancelados', val: String(cancelados.pedidos), destaque: true },
      { lbl: 'Valor cancelado', val: formatMoedaRel(cancelados.valor), destaque: true },
      { lbl: 'Taxa de cancelamento', val: `${cancelados.percentual}%`, destaque: true }
    ];

    document.getElementById('relResumoStats').innerHTML = stats.map(s => `
      <div class="rel-resumo__stat ${s.destaque ? 'destaque' : ''}">
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

  function relRenderTabela(tbodyId, objValores) {
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
            <td data-label="Faturamento">${formatMoedaRel(valor)}</td>
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
    const insights = [];

    insights.push(`Faturamento do período: <b>${formatMoedaRel(p.faturamento)}</b>, com <b>${p.pedidos}</b> pedido${p.pedidos === 1 ? '' : 's'} concluído${p.pedidos === 1 ? '' : 's'}.`);

    if (cancelados.pedidos > 0) {
      insights.push(`<b>${cancelados.pedidos}</b> pedido${cancelados.pedidos === 1 ? '' : 's'} cancelado${cancelados.pedidos === 1 ? '' : 's'}, totalizando <b>${formatMoedaRel(cancelados.valor)}</b> (${cancelados.percentual}% dos pedidos do período).`);
    } else {
      insights.push(`Nenhum cancelamento nesse período.`);
    }

    const formas = Object.entries(p.por_forma_pagamento || {});
    if (formas.length > 0) {
      const [nomeForma] = formas.sort((a, b) => Number(b[1]) - Number(a[1]))[0];
      insights.push(`Forma de pagamento mais usada: <b>${escapeHtml(nomeForma.charAt(0).toUpperCase() + nomeForma.slice(1))}</b>.`);
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

    renderCancelamentosPeriodo(data);
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
      return `
        <div class="cancel-item-row">
          <div class="cancel-item-top">
            <span class="cancel-item-codigo">${escapeHtml(codigo)} · ${escapeHtml(c.cliente_nome || 'Cliente')}</span>
            <span class="cancel-item-valor">${formatMoedaRel(c.total)}</span>
          </div>
          <div class="cancel-item-meta">Estava: ${escapeHtml(c.status_anterior || '—')} · ${escapeHtml(c.tipo || '—')} · cancelado em ${escapeHtml(dataCancel)}</div>
          <div class="cancel-item-meta">Por ${escapeHtml(c.cancelado_por_nome || '—')}${autorizadoLinha}</div>
          <div class="cancel-item-motivo">${escapeHtml(c.motivo_cancelamento || 'Sem motivo informado')}</div>
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
    const linhas = [];

    linhas.push('Relatório Financeiro');
    linhas.push(`Período;${relFormatarPeriodoBR(p.data_inicio, p.data_fim)}`);
    linhas.push('');
    linhas.push(`Faturamento;${relNumeroCSV(p.faturamento)}`);
    linhas.push(`Pedidos concluídos;${p.pedidos}`);
    linhas.push(`Ticket médio;${relNumeroCSV(p.ticket_medio)}`);
    linhas.push(`Cancelados;${cancelados.pedidos}`);
    linhas.push(`Valor cancelado;${relNumeroCSV(cancelados.valor)}`);
    linhas.push(`Taxa de cancelamento;${relNumeroCSV(cancelados.percentual)}%`);
    linhas.push('');

    linhas.push('Formas de pagamento');
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
