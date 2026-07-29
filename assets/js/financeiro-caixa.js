// /assets/js/financeiro-caixa.js
// Logica de Caixa, movimentacoes financeiras, abertura/fechamento e historico, extraida do index.html (Etapa 8).
// Dependem de globais do script principal: sb, restauranteId, currentUser, periodo, movimentacoes, caixaAtual,
// e das funcoes showToast/formatMoeda/formatData. So chamadas apos o script principal rodar.
// Continuam globais (sem type=module). Nao inclui relatorio_financeiro_v1 (fica no script principal).

  let despesaEmAndamento = false;
  let aberturaCaixaEmAndamento = false;
  let fechamentoCaixaEmAndamento = false;

  function normalizarRegistroRpc(data, nomeRpc) {
    if (Array.isArray(data)) {
      if (data.length !== 1 || !data[0] || typeof data[0] !== 'object') {
        throw new Error(`Resposta inválida de ${nomeRpc}.`);
      }
      return data[0];
    }
    if (!data || typeof data !== 'object') {
      throw new Error(`Resposta inválida de ${nomeRpc}.`);
    }
    return data;
  }

  function normalizarListaRpc(data, nomeRpc) {
    if (!Array.isArray(data)) {
      throw new Error(`Resposta inválida de ${nomeRpc}.`);
    }
    return data;
  }

  function mensagemRpcConhecida(erro, operacao) {
    const mensagem = String(erro?.message || '');
    const mensagensConhecidas = [
      'Já existe um caixa aberto para este restaurante.',
      'Não existe caixa aberto para este restaurante.',
      'Você não tem permissão para abrir o caixa.',
      'Você não tem permissão para fechar o caixa.',
      'Você não tem permissão para lançar despesas.',
      'Seu usuário não possui restaurante.',
      'Informe um valor de abertura válido.',
      'Informe um valor contado válido.',
      'Informe um valor válido.',
      'Informe a descrição da despesa.',
      'Informe uma forma de pagamento válida.'
    ];
    const conhecida = mensagensConhecidas.find(item => mensagem.includes(item));
    if (conhecida) return conhecida;
    console.warn(`Falha técnica ao ${operacao}:`, erro);
    return 'Não foi possível concluir a operação. Tente novamente.';
  }

  function definirBotaoCarregando(botao, carregando, textoCarregando) {
    if (!botao) return;
    if (carregando) {
      botao.dataset.textoOriginal = botao.textContent;
      botao.textContent = textoCarregando;
      botao.disabled = true;
      return;
    }
    botao.textContent = botao.dataset.textoOriginal || botao.textContent;
    delete botao.dataset.textoOriginal;
    botao.disabled = false;
  }

  async function loadMovimentacoes() {
    try {
      const { data, error } = await sb.rpc('listar_movimentacoes_financeiras_v2', {
        p_periodo: periodo
      });
      if (error) throw error;
      movimentacoes = normalizarListaRpc(data, 'listar_movimentacoes_financeiras_v2');
      renderExtrato();
    } catch (erro) {
      console.warn('Falha técnica ao carregar o extrato financeiro:', erro);
      movimentacoes = [];
      document.getElementById('totalEntradas').textContent = formatMoeda(0);
      document.getElementById('totalSaidas').textContent = formatMoeda(0);
      document.getElementById('filterCountFinanceiro').textContent = 'Extrato não carregado';
      document.getElementById('extratoList').innerHTML = `
        <div class="empty-state">
          <div class="ic">⚠️</div>
          <h4>Não foi possível carregar o extrato</h4>
          <p>Tente novamente para consultar os lançamentos deste período.</p>
          <button class="btn" type="button" onclick="loadMovimentacoes()">Tentar novamente</button>
        </div>`;
      showToast('Extrato indisponível', 'Não foi possível carregar o extrato. Tente novamente.');
    }
  }

  function setPeriodo(p) {
    if (!['hoje', '7dias', '30dias', 'tudo'].includes(p)) return;
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
      const estornoPedido = m.origem === 'estorno_pedido';
      const descricao = estornoPedido ? 'Estorno de pedido' : m.descricao;
      const origemMeta = estornoPedido
        ? ' · estorno automático · não editável'
        : (m.pedido_id ? ' · gerado automaticamente' : ' · lançamento manual');
      return `
        <div class="mov-row">
          <div class="mov-icon ${classeVisual}">${isEntrada ? '⬆️' : '⬇️'}</div>
          <div class="mov-main">
            <p class="mov-desc">${escapeHtml(descricao || 'Movimentação financeira')} ${FORMA_ICONE[m.forma_pagamento] || ''}</p>
            <div class="mov-meta">${formatData(m.criado_em)}${origemMeta}${m.pedido_id ? ' · vinculado ao pedido' : ''}</div>
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

  function closeDespesa(forcar = false) {
    if (despesaEmAndamento && !forcar) return;
    document.getElementById('despesaModalBg').classList.remove('show');
  }

  async function submitDespesa() {
    if (despesaEmAndamento) return;
    const descricao = document.getElementById('dDescricao').value.trim();
    const valor = parseFloat(document.getElementById('dValor').value);
    const formaPagamento = document.getElementById('dFormaPagamento').value;
    if (!descricao) { showToast('Faltou a descrição', 'Informe do que se trata a despesa.'); return; }
    if (!valor || valor <= 0) { showToast('Valor inválido', 'Informe um valor maior que zero.'); return; }

    const botao = document.getElementById('btnSubmitDespesa');
    despesaEmAndamento = true;
    definirBotaoCarregando(botao, true, 'Lançando...');
    try {
      const { data, error } = await sb.rpc('registrar_despesa_v2', {
        p_descricao: descricao,
        p_valor: valor,
        p_forma_pagamento: formaPagamento
      });
      if (error) throw error;
      normalizarRegistroRpc(data, 'registrar_despesa_v2');
      closeDespesa(true);
      showToast('Despesa lançada', descricao + ' · ' + formatMoeda(valor));
      await loadMovimentacoes();
      await loadCaixaAtual();
    } catch (erro) {
      showToast('Despesa não lançada', mensagemRpcConhecida(erro, 'lançar a despesa'));
    } finally {
      despesaEmAndamento = false;
      definirBotaoCarregando(botao, false);
    }
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

  function closeAbrirCaixa(forcar = false) {
    if (aberturaCaixaEmAndamento && !forcar) return;
    document.getElementById('abrirCaixaModalBg').classList.remove('show');
  }

  async function submitAbrirCaixa() {
    if (aberturaCaixaEmAndamento) return;
    const valorAbertura = parseFloat(document.getElementById('acValorAbertura').value);
    if (isNaN(valorAbertura) || valorAbertura < 0) { showToast('Valor inválido', 'Informe o valor do fundo de troco (pode ser 0).'); return; }

    const botao = document.getElementById('btnSubmitAbrirCaixa');
    aberturaCaixaEmAndamento = true;
    definirBotaoCarregando(botao, true, 'Abrindo...');
    try {
      const { data, error } = await sb.rpc('abrir_caixa_v2', {
        p_valor_abertura: valorAbertura
      });
      if (error) throw error;
      caixaAtual = normalizarRegistroRpc(data, 'abrir_caixa_v2');
      closeAbrirCaixa(true);
      showToast('Caixa aberto', 'Fundo de troco: ' + formatMoeda(caixaAtual.valor_abertura));
      await renderCaixaStatus();
      await loadMovimentacoes();
      await loadCaixaAtual();
    } catch (erro) {
      showToast('Caixa não aberto', mensagemRpcConhecida(erro, 'abrir o caixa'));
    } finally {
      aberturaCaixaEmAndamento = false;
      definirBotaoCarregando(botao, false);
    }
  }

  async function openFecharCaixa() {
    if (!caixaAtual) return;
    const { entradas, saidas } = await calcularMovimentoDinheiro(caixaAtual.aberto_em);
    const esperado = Number(caixaAtual.valor_abertura) + entradas - saidas;

    document.getElementById('fcValorAbertura').textContent = formatMoeda(caixaAtual.valor_abertura);
    document.getElementById('fcEntradasDinheiro').textContent = formatMoeda(entradas);
    document.getElementById('fcSaidasDinheiro').textContent = formatMoeda(saidas);
    document.getElementById('fcEsperado').textContent = formatMoeda(esperado) + ' (estimativa)';
    document.getElementById('fcEsperado').dataset.valor = esperado;
    document.getElementById('fcValorContado').value = '';
    document.getElementById('fcObservacoes').value = '';
    document.getElementById('fcDiferencaTexto').textContent = '';
    document.getElementById('fecharCaixaModalBg').classList.add('show');
  }

  function closeFecharCaixa(forcar = false) {
    if (fechamentoCaixaEmAndamento && !forcar) return;
    document.getElementById('fecharCaixaModalBg').classList.remove('show');
  }

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
    if (fechamentoCaixaEmAndamento) return;
    const contado = parseFloat(document.getElementById('fcValorContado').value);
    if (isNaN(contado) || contado < 0) { showToast('Valor inválido', 'Informe o valor contado na gaveta.'); return; }

    const observacoes = document.getElementById('fcObservacoes').value.trim() || null;
    const botao = document.getElementById('btnSubmitFecharCaixa');
    fechamentoCaixaEmAndamento = true;
    definirBotaoCarregando(botao, true, 'Fechando...');
    try {
      const { data, error } = await sb.rpc('fechar_caixa_v2', {
        p_valor_contado: contado,
        p_observacoes: observacoes
      });
      if (error) throw error;
      const fechamento = normalizarRegistroRpc(data, 'fechar_caixa_v2');
      const esperadoOficial = Number(fechamento.valor_dinheiro_esperado);
      const informadoOficial = Number(fechamento.valor_dinheiro_informado);
      const diferencaOficial = Number(fechamento.diferenca);
      if (![esperadoOficial, informadoOficial, diferencaOficial].every(Number.isFinite)
        || !fechamento.fechado_em || !fechamento.fechado_por) {
        throw new Error('Resposta inválida de fechar_caixa_v2.');
      }
      caixaAtual = null;
      closeFecharCaixa(true);
      showToast(
        'Caixa fechado',
        Math.abs(diferencaOficial) < 0.005
          ? 'Bateu certinho!'
          : 'Diferença confirmada: ' + formatMoeda(diferencaOficial)
      );
      await loadMovimentacoes();
      await loadCaixaAtual();
    } catch (erro) {
      showToast('Caixa não fechado', mensagemRpcConhecida(erro, 'fechar o caixa'));
    } finally {
      fechamentoCaixaEmAndamento = false;
      definirBotaoCarregando(botao, false);
    }
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
