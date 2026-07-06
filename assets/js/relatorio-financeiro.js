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
