// /assets/js/relatorio-financeiro.js
// Logica da aba Relatorio Financeiro, extraida do index.html (Etapa 9).
// Dependem de globais/funcoes: sb, showToast, formatMoedaRel (utils.js).
// So chamadas apos o script principal rodar. Continuam globais (sem type=module).

  async function loadRelatorioFinanceiro() {
    document.getElementById('relPeriodoResultado').classList.add('hidden');
    document.getElementById('relErro').classList.add('hidden');
    document.getElementById('relDataInicio').value = '';
    document.getElementById('relDataFim').value = '';
    await buscarRelatorioFinanceiro();
  }

  async function buscarRelatorioFinanceiro(dataInicio, dataFim) {
    const { data, error } = await sb.rpc('relatorio_financeiro_v1', {
      p_data_inicio: dataInicio || null,
      p_data_fim: dataFim || null
    });
    if (error) { showToast('Não foi possível carregar o relatório', error.message); return; }
    renderRelatorioFinanceiro(data);
  }

  function renderBlocoRel(prefixo, bloco) {
    document.getElementById(`rel${prefixo}Valor`).textContent = formatMoedaRel(bloco.faturamento);
    document.getElementById(`rel${prefixo}Sub`).textContent =
      `${bloco.pedidos} pedido${bloco.pedidos === 1 ? '' : 's'} · ticket médio ${formatMoedaRel(bloco.ticket_medio)}`;

    const cancelados = bloco.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
    const elCancelados = document.getElementById(`rel${prefixo}Cancelados`);
    if (elCancelados) {
      elCancelados.textContent = cancelados.pedidos > 0
        ? `Cancelados: ${cancelados.pedidos} · Valor cancelado: ${formatMoedaRel(cancelados.valor)} (${cancelados.percentual}%)`
        : 'Cancelados: 0';
    }
  }

  function renderTabelaChaveValorRel(tbodyId, obj) {
    const tbody = document.getElementById(tbodyId);
    const chaves = Object.keys(obj || {});
    if (chaves.length === 0) {
      tbody.innerHTML = `<tr><td colspan="2"><div class="empty-state"><div class="ic">💲</div><h4>Nenhum dado no período</h4></div></td></tr>`;
      return;
    }
    tbody.innerHTML = chaves.map(k => `
      <tr>
        <td data-label="Item">${k.charAt(0).toUpperCase() + k.slice(1)}</td>
        <td data-label="Faturamento">${formatMoedaRel(obj[k])}</td>
      </tr>`).join('');
  }

  function renderTabelaTopProdutosRel(tbodyId, lista) {
    const tbody = document.getElementById(tbodyId);
    if (!lista || lista.length === 0) {
      tbody.innerHTML = `<tr><td colspan="2"><div class="empty-state"><div class="ic">🍽️</div><h4>Nenhuma venda no período</h4></div></td></tr>`;
      return;
    }
    tbody.innerHTML = lista.map((p, i) => `
      <tr>
        <td data-label="Produto">${i + 1}. ${p.nome}</td>
        <td data-label="Quantidade">${p.quantidade}x</td>
      </tr>`).join('');
  }

  function renderRelatorioFinanceiro(data) {
    renderBlocoRel('Hoje', data.hoje);
    renderBlocoRel('Semana', data.semana);
    renderBlocoRel('Mes', data.mes);

    renderTabelaChaveValorRel('relFormaPagamentoBody', data.por_forma_pagamento);
    renderTabelaChaveValorRel('relTipoBody', data.por_tipo);
    renderTabelaTopProdutosRel('relTopProdutosBody', data.top_produtos_mes);

    const bloco = document.getElementById('relPeriodoResultado');
    if (data.periodo_personalizado) {
      bloco.classList.remove('hidden');
      const p = data.periodo_personalizado;
      document.getElementById('relPeriodoLabel').textContent = `Período: ${p.data_inicio} até ${p.data_fim}`;
      document.getElementById('relPeriodoValor').textContent = formatMoedaRel(p.faturamento);
      document.getElementById('relPeriodoSub').textContent =
        `${p.pedidos} pedido${p.pedidos === 1 ? '' : 's'} · ticket médio ${formatMoedaRel(p.ticket_medio)}`;

      const canceladosPeriodo = p.cancelados || { pedidos: 0, valor: 0, percentual: 0 };
      const elPeriodoCancelados = document.getElementById('relPeriodoCancelados');
      if (elPeriodoCancelados) {
        elPeriodoCancelados.textContent = canceladosPeriodo.pedidos > 0
          ? `Cancelados: ${canceladosPeriodo.pedidos} · Valor cancelado: ${formatMoedaRel(canceladosPeriodo.valor)} (${canceladosPeriodo.percentual}%)`
          : 'Cancelados: 0';
      }

      renderTabelaChaveValorRel('relPeriodoFormaPagamentoBody', p.por_forma_pagamento);
      renderTabelaChaveValorRel('relPeriodoTipoBody', p.por_tipo);
      renderTabelaTopProdutosRel('relPeriodoTopProdutosBody', p.top_produtos);
    } else {
      bloco.classList.add('hidden');
    }
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
    await buscarRelatorioFinanceiro(inicio, fim);
  }

  // =====================================================================
  // AUDITORIA DE CANCELAMENTOS (clique no "Cancelados" de cada card)
  // =====================================================================
  async function abrirCancelamentosPeriodo(periodo) {
    let dataInicio = null;
    let dataFim = null;

    if (periodo === 'personalizado') {
      dataInicio = document.getElementById('relDataInicio').value;
      dataFim = document.getElementById('relDataFim').value;
      if (!dataInicio || !dataFim) {
        showToast('Escolha o período primeiro', 'Preencha e aplique as datas antes de ver os cancelamentos.');
        return;
      }
    }

    document.getElementById('cancelamentosPeriodoLabel').textContent = 'Carregando...';
    document.getElementById('cancelamentosPeriodoLista').innerHTML = '';
    document.getElementById('cancelamentosPeriodoModalBg').classList.add('show');

    const { data, error } = await sb.rpc('relatorio_cancelamentos_v1', {
      p_periodo: periodo,
      p_data_inicio: dataInicio,
      p_data_fim: dataFim
    });

    if (error) {
      document.getElementById('cancelamentosPeriodoLabel').textContent = 'Erro ao carregar';
      document.getElementById('cancelamentosPeriodoLista').innerHTML =
        `<p class="main__subtitle" style="color:var(--red);">${error.message}</p>`;
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
    labelEl.textContent = `${data.data_inicio} até ${data.data_fim} · ${data.total_cancelamentos} cancelamento${data.total_cancelamentos === 1 ? '' : 's'} · ${formatMoedaRel(data.valor_total_cancelado)}`;

    const lista = data.cancelamentos || [];
    if (lista.length === 0) {
      listaEl.innerHTML = `<div class="empty-state"><div class="ic">✕</div><h4>Nenhum cancelamento nesse período</h4></div>`;
      return;
    }

    listaEl.innerHTML = lista.map(c => {
      const codigo = c.numero_diario != null ? ('#' + c.numero_diario) : ('#' + c.pedido_id.slice(0, 8).toUpperCase());
      const dataCancel = c.cancelado_em ? new Date(c.cancelado_em).toLocaleString('pt-BR') : '—';
      const autorizadoLinha = (c.autorizado_por_nome && c.autorizado_por_nome !== c.cancelado_por_nome)
        ? ` · autorizado por ${c.autorizado_por_nome}`
        : '';
      return `
        <div class="cancel-item-row">
          <div class="cancel-item-top">
            <span class="cancel-item-codigo">${codigo} · ${c.cliente_nome || 'Cliente'}</span>
            <span class="cancel-item-valor">${formatMoedaRel(c.total)}</span>
          </div>
          <div class="cancel-item-meta">Estava: ${c.status_anterior || '—'} · ${c.tipo || '—'} · cancelado em ${dataCancel}</div>
          <div class="cancel-item-meta">Por ${c.cancelado_por_nome || '—'}${autorizadoLinha}</div>
          <div class="cancel-item-motivo">${c.motivo_cancelamento || 'Sem motivo informado'}</div>
        </div>`;
    }).join('');
  }
