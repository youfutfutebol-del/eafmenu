// /assets/js/financeiro-caixa.js
// Logica de Caixa, movimentacoes financeiras, abertura/fechamento e historico, extraida do index.html (Etapa 8).
// Dependem de globais do script principal: sb, restauranteId, currentUser, periodo, movimentacoes, caixaAtual,
// e das funcoes showToast/formatMoeda/formatData. So chamadas apos o script principal rodar.
// Continuam globais (sem type=module). Nao inclui relatorio_financeiro_v1 (fica no script principal).

  function periodoInicio() {
    const agora = new Date();
    if (periodo === 'hoje') {
      const inicio = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
      return inicio.toISOString();
    }
    if (periodo === '7dias') return new Date(agora.getTime() - 7 * 86400000).toISOString();
    if (periodo === '30dias') return new Date(agora.getTime() - 30 * 86400000).toISOString();
    return null;
  }

  async function loadMovimentacoes() {
    let query = sb.from('movimentacoes_financeiras')
      .select('id, tipo, descricao, valor, pedido_id, criado_em, forma_pagamento')
      .eq('restaurante_id', restauranteId)
      .order('criado_em', { ascending: false });

    const inicio = periodoInicio();
    if (inicio) query = query.gte('criado_em', inicio);

    const { data, error } = await query;
    if (error) { showToast('Erro ao carregar', error.message); return; }
    movimentacoes = data || [];
    renderExtrato();
  }

  function setPeriodo(p) {
    periodo = p;
    document.querySelectorAll('#filterTabsFinanceiro .tab').forEach(t => t.classList.toggle('active', t.dataset.p === p));
    loadMovimentacoes();
  }

  function renderExtrato() {
    const totalEntradas = movimentacoes.filter(m => m.tipo === 'receita').reduce((s, m) => s + Number(m.valor), 0);
    const totalSaidas = movimentacoes.filter(m => m.tipo === 'despesa').reduce((s, m) => s + Number(m.valor), 0);

    document.getElementById('totalEntradas').textContent = formatMoeda(totalEntradas);
    document.getElementById('totalSaidas').textContent = formatMoeda(totalSaidas);
    document.getElementById('filterCountFinanceiro').textContent = `Mostrando ${movimentacoes.length} lançamento(s)`;

    const list = document.getElementById('extratoList');
    if (movimentacoes.length === 0) {
      list.innerHTML = `<div class="empty-state"><div class="ic">💲</div><h4>Nenhum lançamento nesse período</h4><p>Entradas de pedidos pagos aparecem aqui automaticamente.</p></div>`;
      return;
    }

    const FORMA_ICONE = { dinheiro: '💵', pix: '📱', cartao: '💳' };
    list.innerHTML = movimentacoes.map(m => {
      const isEntrada = m.tipo === 'receita';
      const classeVisual = isEntrada ? 'entrada' : 'saida';
      return `
        <div class="mov-row">
          <div class="mov-icon ${classeVisual}">${isEntrada ? '⬆️' : '⬇️'}</div>
          <div class="mov-main">
            <p class="mov-desc">${m.descricao} ${FORMA_ICONE[m.forma_pagamento] || ''}</p>
            <div class="mov-meta">${formatData(m.criado_em)}${m.pedido_id ? ' · gerado automaticamente' : ' · lançamento manual'}</div>
          </div>
          <div class="mov-valor ${classeVisual}">${isEntrada ? '+' : '-'} ${formatMoeda(m.valor)}</div>
        </div>`;
    }).join('');
  }

  function openDespesa() {
    document.getElementById('dDescricao').value = '';
    document.getElementById('dValor').value = '';
    document.getElementById('dFormaPagamento').value = 'dinheiro';
    document.getElementById('despesaModalBg').classList.add('show');
  }

  function closeDespesa() { document.getElementById('despesaModalBg').classList.remove('show'); }

  async function submitDespesa() {
    const descricao = document.getElementById('dDescricao').value.trim();
    const valor = parseFloat(document.getElementById('dValor').value);
    const formaPagamento = document.getElementById('dFormaPagamento').value;
    if (!descricao) { showToast('Faltou a descrição', 'Informe do que se trata a despesa.'); return; }
    if (!valor || valor <= 0) { showToast('Valor inválido', 'Informe um valor maior que zero.'); return; }

    const { error } = await sb.from('movimentacoes_financeiras').insert({
      restaurante_id: restauranteId,
      tipo: 'despesa',
      descricao,
      valor,
      criado_por: currentUser.id,
      forma_pagamento: formaPagamento
    });
    if (error) { showToast('Erro ao lançar', error.message); return; }

    closeDespesa();
    showToast('Despesa lançada', descricao + ' · ' + formatMoeda(valor));
    await loadMovimentacoes();
    await loadCaixaAtual();
  }

  async function loadCaixaAtual() {
    const { data, error } = await sb.from('fechamentos_caixa')
      .select('*')
      .eq('restaurante_id', restauranteId)
      .eq('status', 'aberto')
      .order('aberto_em', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) { console.error(error); return; }
    caixaAtual = data;
    await renderCaixaStatus();
    await loadFechamentosHistorico();
  }

  async function calcularMovimentoDinheiro(desde) {
    const [{ data: entradasData }, { data: saidasData }] = await Promise.all([
      sb.from('movimentacoes_financeiras').select('valor').eq('restaurante_id', restauranteId).eq('tipo', 'receita').eq('forma_pagamento', 'dinheiro').gte('criado_em', desde),
      sb.from('movimentacoes_financeiras').select('valor').eq('restaurante_id', restauranteId).eq('tipo', 'despesa').eq('forma_pagamento', 'dinheiro').gte('criado_em', desde)
    ]);
    const entradas = (entradasData || []).reduce((s, m) => s + Number(m.valor), 0);
    const saidas = (saidasData || []).reduce((s, m) => s + Number(m.valor), 0);
    return { entradas, saidas };
  }

  async function renderCaixaStatus() {
    const dot = document.getElementById('caixaStatusDot');
    const texto = document.getElementById('caixaStatusTexto');
    const sub = document.getElementById('caixaStatusSub');
    const btnAbrir = document.getElementById('btnAbrirCaixa');
    const btnFechar = document.getElementById('btnFecharCaixa');

    if (!caixaAtual) {
      dot.style.background = '#A1A1AA';
      texto.textContent = 'Caixa fechado';
      sub.textContent = 'Abra o caixa informando o fundo de troco pra começar a operar.';
      btnAbrir.style.display = 'inline-flex';
      btnFechar.style.display = 'none';
      document.getElementById('caixaDinheiroEsperado').textContent = formatMoeda(0);
      return;
    }

    dot.style.background = 'var(--green)';
    texto.textContent = 'Caixa aberto';
    sub.textContent = 'Aberto às ' + formatData(caixaAtual.aberto_em) + ' · fundo de R$ ' + Number(caixaAtual.valor_abertura).toFixed(2).replace('.', ',');
    btnAbrir.style.display = 'none';
    btnFechar.style.display = 'inline-flex';

    const { entradas, saidas } = await calcularMovimentoDinheiro(caixaAtual.aberto_em);
    const esperado = Number(caixaAtual.valor_abertura) + entradas - saidas;
    document.getElementById('caixaDinheiroEsperado').textContent = formatMoeda(esperado);
  }

  function openAbrirCaixa() {
    document.getElementById('acValorAbertura').value = '';
    document.getElementById('abrirCaixaModalBg').classList.add('show');
  }

  function closeAbrirCaixa() { document.getElementById('abrirCaixaModalBg').classList.remove('show'); }

  async function submitAbrirCaixa() {
    const valorAbertura = parseFloat(document.getElementById('acValorAbertura').value);
    if (isNaN(valorAbertura) || valorAbertura < 0) { showToast('Valor inválido', 'Informe o valor do fundo de troco (pode ser 0).'); return; }

    const { error } = await sb.from('fechamentos_caixa').insert({
      restaurante_id: restauranteId,
      valor_abertura: valorAbertura,
      aberto_por: currentUser.id
    });
    if (error) { showToast('Erro ao abrir caixa', error.message); return; }

    closeAbrirCaixa();
    showToast('Caixa aberto', 'Fundo de troco: ' + formatMoeda(valorAbertura));
    await loadCaixaAtual();
  }

  async function openFecharCaixa() {
    if (!caixaAtual) return;
    const { entradas, saidas } = await calcularMovimentoDinheiro(caixaAtual.aberto_em);
    const esperado = Number(caixaAtual.valor_abertura) + entradas - saidas;

    document.getElementById('fcValorAbertura').textContent = formatMoeda(caixaAtual.valor_abertura);
    document.getElementById('fcEntradasDinheiro').textContent = formatMoeda(entradas);
    document.getElementById('fcSaidasDinheiro').textContent = formatMoeda(saidas);
    document.getElementById('fcEsperado').textContent = formatMoeda(esperado);
    document.getElementById('fcEsperado').dataset.valor = esperado;
    document.getElementById('fcValorContado').value = '';
    document.getElementById('fcObservacoes').value = '';
    document.getElementById('fcDiferencaTexto').textContent = '';
    document.getElementById('fecharCaixaModalBg').classList.add('show');
  }

  function closeFecharCaixa() { document.getElementById('fecharCaixaModalBg').classList.remove('show'); }

  function atualizarDiferencaFechamento() {
    const esperado = Number(document.getElementById('fcEsperado').dataset.valor || 0);
    const contado = parseFloat(document.getElementById('fcValorContado').value);
    const texto = document.getElementById('fcDiferencaTexto');
    if (isNaN(contado)) { texto.textContent = ''; return; }
    const diferenca = contado - esperado;
    if (Math.abs(diferenca) < 0.005) {
      texto.textContent = '✓ Caixa bateu certinho.';
      texto.style.color = 'var(--green)';
    } else if (diferenca > 0) {
      texto.textContent = `Sobrou ${formatMoeda(diferenca)} na gaveta.`;
      texto.style.color = 'var(--amber)';
    } else {
      texto.textContent = `Faltou ${formatMoeda(Math.abs(diferenca))} na gaveta.`;
      texto.style.color = 'var(--red)';
    }
  }

  async function submitFecharCaixa() {
    const esperado = Number(document.getElementById('fcEsperado').dataset.valor || 0);
    const contado = parseFloat(document.getElementById('fcValorContado').value);
    if (isNaN(contado) || contado < 0) { showToast('Valor inválido', 'Informe o valor contado na gaveta.'); return; }

    const diferenca = contado - esperado;
    const observacoes = document.getElementById('fcObservacoes').value.trim() || null;

    const { error } = await sb.from('fechamentos_caixa').update({
      status: 'fechado',
      valor_dinheiro_esperado: esperado,
      valor_dinheiro_informado: contado,
      diferenca,
      observacoes,
      fechado_por: currentUser.id,
      fechado_em: new Date().toISOString()
    }).eq('id', caixaAtual.id);

    if (error) { showToast('Erro ao fechar caixa', error.message); return; }

    closeFecharCaixa();
    showToast('Caixa fechado', Math.abs(diferenca) < 0.005 ? 'Bateu certinho!' : 'Diferença: ' + formatMoeda(diferenca));
    await loadCaixaAtual();
  }

  async function loadFechamentosHistorico() {
    const { data, error } = await sb.from('fechamentos_caixa')
      .select('id, aberto_em, fechado_em, valor_dinheiro_esperado, valor_dinheiro_informado, diferenca, status')
      .eq('restaurante_id', restauranteId)
      .eq('status', 'fechado')
      .order('fechado_em', { ascending: false })
      .limit(15);

    const tbody = document.getElementById('fechamentosTableBody');
    if (error || !data || data.length === 0) {
      tbody.innerHTML = `<tr><td colspan="5"><div class="empty-state"><div class="ic">📒</div><h4>Nenhum fechamento registrado ainda</h4></div></td></tr>`;
      return;
    }

    tbody.innerHTML = data.map(f => {
      const diferencaCor = Math.abs(f.diferenca) < 0.005 ? 'var(--green)' : (f.diferenca > 0 ? 'var(--amber)' : 'var(--red)');
      return `
        <tr>
          <td data-label="Aberto em">${formatData(f.aberto_em)}</td>
          <td data-label="Fechado em">${formatData(f.fechado_em)}</td>
          <td data-label="Esperado">${formatMoeda(f.valor_dinheiro_esperado)}</td>
          <td data-label="Informado">${formatMoeda(f.valor_dinheiro_informado)}</td>
          <td data-label="Diferença"><b style="color:${diferencaCor};">${formatMoeda(f.diferenca)}</b></td>
        </tr>`;
    }).join('');
  }
