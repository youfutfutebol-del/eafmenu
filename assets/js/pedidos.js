// /assets/js/pedidos.js
// Logica operacional de pedidos (query no Supabase, realtime, impressao, som), extraida do index.html (Etapa 5).
// Dependem de globais do script principal: sb, restauranteId, orders, restauranteInfo, currentView,
// soundOn, audioCtx, FLOW, e das funcoes loadMovimentacoes/loadCaixaAtual/atualizarSubtituloPedidos/
// showToast/renderOrders/codigoPedido. So chamadas apos o script principal rodar. Continuam globais.
// tocarNovoPedido() vem de /assets/js/sons.js (carregado antes deste arquivo).

  // Pedidos lancados via pedido manual entram aqui (por pedidos.js) e sao removidos quando
  // o Realtime avisar sobre eles — assim o som de "novo pedido" nao toca pra pedido manual.
  // Limitacao conhecida: so funciona na mesma aba que criou o pedido manual (sem coluna no banco
  // pra diferenciar a origem, nao da pra saber isso em outra aba/dispositivo).
  let pedidosCriadosManualmente = new Set();

  // Estado do Realtime de pedidos: canal ativo, status da assinatura e timers
  // de reconexao/polling de contingencia/resincronizacao. Tudo centralizado aqui
  // para nao criar canais ou timers duplicados (ver subscribeRealtime()).
  let canalPedidosRealtime = null;
  let statusRealtimePedidos = 'desconectado'; // 'conectado' | 'conectando' | 'desconectado'
  let inscricaoRealtimeEmAndamento = false;
  let timerReconexaoRealtime = null;
  let timerPollingContingenciaRealtime = null;
  let timerTimeoutConexaoRealtime = null;
  let resincronizandoRealtime = false;
  const RECONEXAO_REALTIME_MS = 3000;
  const POLLING_CONTINGENCIA_REALTIME_MS = 30000;
  const TIMEOUT_CONEXAO_REALTIME_MS = 12000;

  let pedidosHistorico = [];
  let erroHistoricoPedidos = null;
  let estadoHistoricoPedidos = 'inicial';
  let modoListaPedidos = 'andamento';
  let historicoPaginaAtual = 0;
  let historicoTotalResultados = 0;
  let historicoConsultaDiaAtual = false;
  const HISTORICO_TAMANHO_PAGINA = 200;
  const renderOrdersEmAndamento = window.renderOrders;
  const STATUS_HISTORICO_PEDIDOS = ['entregue', 'retirado', 'cancelado'];
  const PRAZO_CANCELAMENTO_FINALIZADO_MS = 24 * 60 * 60 * 1000;
  let cancelamentoPedidoEmAndamento = false;
  let resolucaoFinanceiraEmAndamento = false;
  const CAMPOS_PEDIDOS = `
    id, numero_diario, tipo, status, pago, forma_pagamento, subtotal, taxa_entrega, total, desconto_tipo, desconto_valor_informado, desconto_manual, desconto_motivo, criado_em, finalizado_em, motoboy_id, troco_para, observacoes, previsao_inicio, previsao_fim, motivo_cancelamento, cancelado_em, cancelamento_decisao_financeira, cancelamento_decisao_financeira_em, cancelamento_decisao_financeira_por,
    clientes ( nome, telefone ),
    enderecos_cliente!endereco_entrega_id ( logradouro, numero, bairro, cidade, complemento, referencia ),
    itens_pedido (
      produto_id, nome_grupo_snapshot, nome_tamanho_snapshot, sabores_esperados, precificacao_finalizada_em,
      preco_unitario, quantidade, observacoes,
      produtos ( nome ),
      itens_pedido_sabores ( produto_id, nome_produto_snapshot, preco_unitario, ordem, produtos ( nome ) )
    )
  `;

  function pedidoFinalizadoPodeSerCancelado(pedido, agoraMs = Date.now()) {
    if (!['entregue', 'retirado'].includes(pedido?.status) || !pedido.finalizado_em) return false;
    const finalizadoEmMs = new Date(pedido.finalizado_em).getTime();
    if (!Number.isFinite(finalizadoEmMs) || finalizadoEmMs > agoraMs) return false;
    return agoraMs - finalizadoEmMs <= PRAZO_CANCELAMENTO_FINALIZADO_MS;
  }

  async function loadPedidos() {
    const { data, error } = await sb.from('pedidos')
      .select(CAMPOS_PEDIDOS)
      .eq('restaurante_id', restauranteId)
      .not('status', 'in', '(entregue,retirado,cancelado)')
      .order('criado_em', { ascending: false })
      .limit(200);
    if (error) {
      document.getElementById('orderList').innerHTML = `
        <div class="empty-state">
          <div class="ic">⚠️</div>
          <h4>Não foi possível carregar os pedidos</h4>
          <p>Verifique sua conexão e tente novamente.</p>
          <button class="btn" type="button" onclick="loadPedidos()">Tentar novamente</button>
        </div>`;
      return false;
    }
    const inicio = inicioDiaComercial();
    const abertos = data || [];
    const anteriores = abertos.filter(pedido => new Date(pedido.criado_em) < inicio);
    const atuais = abertos.filter(pedido => new Date(pedido.criado_em) >= inicio);
    orders = [...anteriores, ...atuais];
    garantirInterfaceHistoricoPedidos();
    atualizarSubtituloPedidos();
    renderOrders();
    return true;
  }

  function garantirInterfaceHistoricoPedidos() {
    if (document.getElementById('modoListaPedidos')) return;
    const filtrosPagamento = document.getElementById('filterTabsPedidos');
    const linhaFiltro = filtrosPagamento?.closest('.filter-row');
    if (!linhaFiltro) return;
    const modos = document.createElement('div');
    modos.id = 'modoListaPedidos';
    modos.className = 'tabs';
    modos.style.marginBottom = '10px';
    modos.innerHTML = `
      <button class="tab active" type="button" data-modo-pedidos="andamento" onclick="setModoListaPedidos('andamento')">Em andamento</button>
      <button class="tab" type="button" data-modo-pedidos="historico" onclick="setModoListaPedidos('historico')">Histórico</button>`;
    linhaFiltro.parentNode.insertBefore(modos, linhaFiltro);
    const formulario = document.createElement('div');
    formulario.id = 'filtrosHistoricoPedidos';
    formulario.innerHTML = `
      <label style="display:grid; gap:4px; font-size:11px; font-weight:700;">Data inicial
        <input id="historicoDataInicial" type="date" style="padding:7px 9px; border:1px solid var(--border); border-radius:8px; font:inherit;">
      </label>
      <label style="display:grid; gap:4px; font-size:11px; font-weight:700;">Data final
        <input id="historicoDataFinal" type="date" style="padding:7px 9px; border:1px solid var(--border); border-radius:8px; font:inherit;">
      </label>
      <label style="display:grid; gap:4px; min-width:210px; flex:1; font-size:11px; font-weight:700;">Telefone do cliente
        <input id="historicoTelefone" type="tel" placeholder="(41) 99999-9999" style="padding:7px 9px; border:1px solid var(--border); border-radius:8px; font:inherit;">
      </label>
      <button class="btn primary" type="button" onclick="buscarHistoricoPedidos()">Buscar</button>
      <button class="btn" type="button" onclick="limparFiltrosHistoricoPedidos()">Limpar filtros</button>`;
    linhaFiltro.parentNode.insertBefore(formulario, linhaFiltro.nextSibling);
  }

  function setModoListaPedidos(modo) {
    modoListaPedidos = modo === 'historico' ? 'historico' : 'andamento';
    document.querySelectorAll('[data-modo-pedidos]').forEach(botao => {
      botao.classList.toggle('active', botao.dataset.modoPedidos === modoListaPedidos);
    });
    const formulario = document.getElementById('filtrosHistoricoPedidos');
    const filtrosPagamento = document.getElementById('filterTabsPedidos');
    const rotuloPagamento = filtrosPagamento?.previousElementSibling;
    if (formulario) {
      formulario.classList.toggle('is-visible', modoListaPedidos === 'historico');
    }
    if (filtrosPagamento) filtrosPagamento.style.display = modoListaPedidos === 'historico' ? 'none' : '';
    if (rotuloPagamento) rotuloPagamento.style.display = modoListaPedidos === 'historico' ? 'none' : '';
    if (modoListaPedidos === 'historico') {
      preencherDiaComercialAtualHistorico();
      buscarHistoricoPedidos();
      return;
    }
    renderOrders();
  }

  function normalizarTelefoneHistorico(telefone) {
    const digitos = String(telefone || '').replace(/\D/g, '');
    return digitos.startsWith('55') && digitos.length > 11 ? digitos.slice(2) : digitos;
  }

  function formatarDataInputHistorico(data) {
    const ano = data.getFullYear();
    const mes = String(data.getMonth() + 1).padStart(2, '0');
    const dia = String(data.getDate()).padStart(2, '0');
    return `${ano}-${mes}-${dia}`;
  }

  function dataDiaComercialAtualHistorico() {
    return formatarDataInputHistorico(inicioDiaComercial());
  }

  function preencherDiaComercialAtualHistorico() {
    const dataAtual = dataDiaComercialAtualHistorico();
    document.getElementById('historicoDataInicial').value = dataAtual;
    document.getElementById('historicoDataFinal').value = dataAtual;
    document.getElementById('historicoTelefone').value = '';
  }

  function limitesPeriodoHistorico(dataInicial, dataFinal) {
    const criarInicioDiaComercial = valor => {
      const [ano, mes, dia] = valor.split('-').map(Number);
      return new Date(ano, mes - 1, dia, HORA_RESET_PEDIDOS, 0, 0, 0);
    };
    const inicio = criarInicioDiaComercial(dataInicial);
    const fimExclusivo = criarInicioDiaComercial(dataFinal);
    fimExclusivo.setDate(fimExclusivo.getDate() + 1);
    return { inicio: inicio.toISOString(), fimExclusivo: fimExclusivo.toISOString() };
  }

  function definirMensagemHistorico(mensagem, erro = false) {
    erroHistoricoPedidos = erro ? mensagem : null;
    estadoHistoricoPedidos = erro ? 'erro' : 'inicial';
    document.getElementById('filterCountPedidos').textContent = '';
    document.getElementById('orderList').innerHTML = `<div class="empty-state"><div class="ic">${erro ? '⚠️' : '🕘'}</div><p>${escapeHtml(mensagem)}</p></div>`;
  }

  async function buscarIdsClientesPorTelefoneHistorico(telefone) {
    const telefoneNormalizado = normalizarTelefoneHistorico(telefone);
    const ultimosQuatro = telefoneNormalizado.slice(-4);
    const { data, error } = await sb.from('clientes')
      .select('id, telefone')
      .eq('restaurante_id', restauranteId)
      .ilike('telefone', `%${ultimosQuatro}%`)
      .limit(50);
    if (error) throw error;
    return (data || [])
      .filter(cliente => normalizarTelefoneHistorico(cliente.telefone) === telefoneNormalizado)
      .map(cliente => cliente.id);
  }

  async function buscarHistoricoPedidos(manterPagina = false) {
    const dataInicial = document.getElementById('historicoDataInicial').value;
    const dataFinal = document.getElementById('historicoDataFinal').value;
    const telefone = document.getElementById('historicoTelefone').value;
    const telefoneNormalizado = normalizarTelefoneHistorico(telefone);
    const temAlgumaData = Boolean(dataInicial || dataFinal);
    if (!manterPagina) historicoPaginaAtual = 0;
    historicoConsultaDiaAtual = dataInicial === dataDiaComercialAtualHistorico()
      && dataFinal === dataInicial
      && !telefoneNormalizado;
    if (!temAlgumaData && !telefoneNormalizado) {
      definirMensagemHistorico('Informe um período ou telefone para consultar pedidos anteriores.', true);
      return;
    }
    if (temAlgumaData && (!dataInicial || !dataFinal)) {
      definirMensagemHistorico('Informe a data inicial e a data final.', true);
      return;
    }
    if (dataInicial && dataFinal && dataInicial > dataFinal) {
      definirMensagemHistorico('O período informado é inválido.', true);
      return;
    }

    estadoHistoricoPedidos = 'carregando';
    erroHistoricoPedidos = null;
    document.getElementById('filterCountPedidos').textContent = historicoConsultaDiaAtual ? 'Buscando pedidos de hoje…' : 'Buscando…';
    document.getElementById('orderList').innerHTML = `<div class="empty-state"><div class="ic">🕘</div><p>${historicoConsultaDiaAtual ? 'Buscando pedidos de hoje…' : 'Buscando pedidos anteriores…'}</p></div>`;
    try {
      let clientesIds = null;
      if (telefoneNormalizado) {
        clientesIds = await buscarIdsClientesPorTelefoneHistorico(telefoneNormalizado);
        if (!clientesIds.length) {
          pedidosHistorico = [];
          historicoTotalResultados = 0;
          estadoHistoricoPedidos = 'carregado';
          renderHistoricoPedidos();
          return;
        }
      }
      let consulta = sb.from('pedidos')
        .select(CAMPOS_PEDIDOS, { count: 'exact' })
        .eq('restaurante_id', restauranteId)
        .in('status', STATUS_HISTORICO_PEDIDOS);
      if (dataInicial && dataFinal) {
        const periodo = limitesPeriodoHistorico(dataInicial, dataFinal);
        consulta = consulta.gte('criado_em', periodo.inicio).lt('criado_em', periodo.fimExclusivo);
      }
      if (clientesIds) consulta = consulta.in('cliente_id', clientesIds);
      const inicioPagina = historicoPaginaAtual * HISTORICO_TAMANHO_PAGINA;
      const fimPagina = inicioPagina + HISTORICO_TAMANHO_PAGINA - 1;
      const { data, error, count } = await consulta
        .order('criado_em', { ascending: false })
        .range(inicioPagina, fimPagina);
      if (error) throw error;
      pedidosHistorico = data || [];
      historicoTotalResultados = Number(count || 0);
      estadoHistoricoPedidos = 'carregado';
      renderHistoricoPedidos();
    } catch (error) {
      definirMensagemHistorico('Não foi possível carregar o histórico. Tente novamente.', true);
    }
  }

  async function mudarPaginaHistorico(delta) {
    const totalPaginas = Math.ceil(historicoTotalResultados / HISTORICO_TAMANHO_PAGINA);
    const novaPagina = historicoPaginaAtual + delta;
    if (estadoHistoricoPedidos === 'carregando' || novaPagina < 0 || novaPagina >= totalPaginas) return;
    historicoPaginaAtual = novaPagina;
    await buscarHistoricoPedidos(true);
  }

  function limparFiltrosHistoricoPedidos() {
    preencherDiaComercialAtualHistorico();
    buscarHistoricoPedidos();
  }

  function formatarDataHoraHistorico(valor) {
    return new Date(valor).toLocaleString('pt-BR', {
      timeZone: 'America/Sao_Paulo',
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23'
    });
  }

  function renderItemHistorico(itemOriginal) {
    const item = normalizarItemPedido(itemOriginal);
    const detalhes = [];
    if (item.nomeTamanho) detalhes.push(`Tamanho: ${escapeHtml(item.nomeTamanho)}`);
    if (item.sabores.length) detalhes.push(`Sabores: ${item.sabores.map(escapeHtml).join(' + ')}`);
    if (item.observacoes) detalhes.push(`Obs. do item: ${escapeHtml(item.observacoes)}`);
    return `
      <div class="order-history-item">
        <strong>${escapeHtml(item.quantidade)}x ${escapeHtml(item.nomePrincipal)}</strong>
        ${detalhes.length ? `<span>${detalhes.join(' · ')}</span>` : ''}
      </div>`;
  }

  function renderCardHistorico(pedido) {
    const cliente = escapeHtml(pedido.clientes?.nome || 'Cliente balcão');
    const telefone = pedido.clientes?.telefone
      ? `<div class="order-card__phone">${escapeHtml(pedido.clientes.telefone)}</div>`
      : '';
    const tipoBadge = pedido.tipo === 'entrega'
      ? '<span class="badge entrega">🛵 entrega</span>'
      : '<span class="badge retirada">🏠 retirada</span>';
    const statusBadge = `<span class="badge status order-history-status order-history-status--${escapeHtml(pedido.status)}">${escapeHtml(STATUS_LABEL[pedido.status] || pedido.status)}</span>`;
    const pagoBadge = pedido.pago
      ? '<span class="badge pago">pago</span>'
      : '<span class="badge pendente">pendente</span>';
    const estadoFinanceiro = pedido.cancelamento_decisao_financeira;
    let cancelamentoFinanceiroBadge = '';
    let botaoResolverFinanceiro = '';
    if (pedido.status === 'cancelado') {
      if (!pedido.pago || estadoFinanceiro === 'nao_aplicavel') {
        cancelamentoFinanceiroBadge = '<span class="badge cancelamento-financeiro cancelamento-financeiro--neutro">Sem impacto financeiro</span>';
      } else if (estadoFinanceiro === 'estornado') {
        cancelamentoFinanceiroBadge = '<span class="badge cancelamento-financeiro cancelamento-financeiro--estornado">Valor estornado</span>';
      } else if (estadoFinanceiro === 'mantido') {
        cancelamentoFinanceiroBadge = '<span class="badge cancelamento-financeiro cancelamento-financeiro--mantido">Valor mantido</span>';
      } else if (estadoFinanceiro === 'pendente') {
        cancelamentoFinanceiroBadge = '<span class="badge cancelamento-financeiro cancelamento-financeiro--pendente">Decisão financeira pendente</span>';
        botaoResolverFinanceiro = `<button class="order-btn order-btn--warning" type="button" data-order-action="resolver-financeiro" data-order-id="${escapeHtml(pedido.id)}">Resolver financeiro</button>`;
      }
    }
    const endereco = pedido.enderecos_cliente;
    const partesEndereco = endereco
      ? [
          endereco.logradouro,
          endereco.numero,
          endereco.bairro,
          endereco.cidade,
          endereco.complemento,
          endereco.referencia ? `Ref: ${endereco.referencia}` : ''
        ].filter(Boolean).map(escapeHtml)
      : [];
    const enderecoLinha = pedido.tipo === 'entrega' && partesEndereco.length
      ? `<div class="order-detail order-detail--address">📍 ${partesEndereco.join(' · ')}</div>`
      : '';
    const observacaoLinha = pedido.observacoes
      ? `<div class="order-detail order-detail--note">📝 ${escapeHtml(pedido.observacoes)}</div>`
      : '';
    const trocoLinha = pedido.forma_pagamento === 'dinheiro' && pedido.troco_para
      ? `<div class="order-detail order-detail--change">💵 Troco: R$ ${(Number(pedido.troco_para) - Number(pedido.total)).toFixed(2).replace('.', ',')} (paga com R$ ${Number(pedido.troco_para).toFixed(2).replace('.', ',')})</div>`
      : '';
    const pedidoId = escapeHtml(pedido.id);
    const botaoCancelar = pedidoFinalizadoPodeSerCancelado(pedido)
      ? `<button class="order-btn order-btn--danger" type="button" data-order-action="cancelar" data-order-id="${pedidoId}">Cancelar pedido</button>`
      : '';

    return `
      <div class="order-row order-row--history">
        <div class="order-card__top">
          <div class="order-card__code order-code">
            <span>${escapeHtml(codigoPedido(pedido))}</span>
            <span class="order-history-date">${escapeHtml(formatarDataHoraHistorico(pedido.criado_em))}</span>
          </div>
          <div class="order-card__total order-total">R$ ${Number(pedido.total).toFixed(2).replace('.', ',')}</div>
        </div>
        <div class="order-card__body order-card__body--history">
          <div class="order-main">
            <div class="order-card__identity order-card__identity--history">
              <div class="order-history-customer">
                <div class="order-cliente">${cliente}</div>
                ${telefone}
              </div>
              <div class="order-badges">${tipoBadge}${statusBadge}${pagoBadge}${cancelamentoFinanceiroBadge}</div>
            </div>
            <div class="order-card__details">
              <div class="order-detail order-detail--items">${(pedido.itens_pedido || []).map(renderItemHistorico).join('') || 'sem itens'}</div>
              ${enderecoLinha}
              ${observacaoLinha}
              ${trocoLinha}
            </div>
          </div>
          <div class="order-history-actions">
            <button class="order-btn order-btn--secondary" type="button" data-order-action="imprimir" data-order-id="${pedidoId}">🖨️ Imprimir</button>
            ${botaoCancelar}
            ${botaoResolverFinanceiro}
          </div>
        </div>
      </div>`;
  }

  function renderHistoricoPedidos() {
    const list = document.getElementById('orderList');
    if (estadoHistoricoPedidos === 'inicial') {
      document.getElementById('filterCountPedidos').textContent = '';
      list.innerHTML = '<div class="empty-state"><div class="ic">🕘</div><p>Informe um período ou telefone para consultar pedidos anteriores.</p></div>';
      return;
    }
    if (estadoHistoricoPedidos === 'erro') {
      document.getElementById('filterCountPedidos').textContent = '';
      list.innerHTML = `<div class="empty-state"><div class="ic">⚠️</div><p>${escapeHtml(erroHistoricoPedidos || 'Não foi possível carregar o histórico.')}</p></div>`;
      return;
    }
    if (estadoHistoricoPedidos === 'carregando') {
      document.getElementById('filterCountPedidos').textContent = historicoConsultaDiaAtual ? 'Buscando pedidos de hoje…' : 'Buscando…';
      list.innerHTML = `<div class="empty-state"><div class="ic">🕘</div><p>${historicoConsultaDiaAtual ? 'Buscando pedidos de hoje…' : 'Buscando pedidos anteriores…'}</p></div>`;
      return;
    }
    const inicioResultado = historicoTotalResultados ? historicoPaginaAtual * HISTORICO_TAMANHO_PAGINA + 1 : 0;
    const fimResultado = Math.min((historicoPaginaAtual + 1) * HISTORICO_TAMANHO_PAGINA, historicoTotalResultados);
    document.getElementById('filterCountPedidos').textContent = historicoConsultaDiaAtual
      ? (historicoTotalResultados ? `${historicoTotalResultados} ${historicoTotalResultados === 1 ? 'pedido' : 'pedidos'} do dia` : '')
      : (historicoTotalResultados
        ? `Mostrando ${inicioResultado}–${fimResultado} de ${historicoTotalResultados} pedidos`
        : 'Nenhum pedido encontrado');
    if (!historicoTotalResultados) {
      list.innerHTML = `<div class="empty-state"><div class="ic">📋</div><p>${historicoConsultaDiaAtual ? 'Nenhum pedido finalizado neste dia.' : 'Nenhum pedido encontrado.'}</p></div>`;
      return;
    }
    list.innerHTML = pedidosHistorico.map(renderCardHistorico).join('');
    if (historicoTotalResultados) {
      const totalPaginas = Math.ceil(historicoTotalResultados / HISTORICO_TAMANHO_PAGINA);
      list.insertAdjacentHTML('beforeend', `
        <div id="paginacaoHistoricoPedidos" style="display:flex; align-items:center; justify-content:center; gap:10px; flex-wrap:wrap; padding:18px 0 6px;">
          <button class="btn" type="button" onclick="mudarPaginaHistorico(-1)" ${historicoPaginaAtual === 0 ? 'disabled' : ''}>← Anterior</button>
          <span style="font-size:12px; font-weight:700;">Página ${historicoPaginaAtual + 1} de ${totalPaginas}</span>
          <button class="btn" type="button" onclick="mudarPaginaHistorico(1)" ${historicoPaginaAtual + 1 >= totalPaginas ? 'disabled' : ''}>Próxima →</button>
        </div>`);
    }
  }

  function agruparPendenciasAnteriores() {
    const filtrados = orders.filter(pedido => filtroPedidos === 'todos'
      ? true
      : (filtroPedidos === 'pago' ? pedido.pago : !pedido.pago));
    const linhas = [...document.querySelectorAll('#orderList .order-row')];
    const inicio = inicioDiaComercial();
    let grupoAnteriorInserido = false;
    linhas.forEach((linha, indice) => {
      const anterior = new Date(filtrados[indice]?.criado_em) < inicio;
      if (anterior && !grupoAnteriorInserido) {
        linha.insertAdjacentHTML('beforebegin', '<h3 style="margin:8px 0 10px; font-size:13px;">Pendências anteriores</h3>');
        grupoAnteriorInserido = true;
      }
    });
  }

  window.renderOrders = function renderOrdersComHistorico() {
    if (modoListaPedidos === 'historico') return renderHistoricoPedidos();
    renderOrdersEmAndamento();
    agruparPendenciasAnteriores();
  };

  function atualizarPillConexaoRealtime(status) {
    const pill = document.getElementById('connPill');
    const label = document.getElementById('connLabel');
    if (!pill || !label) return;
    if (status === 'conectado') {
      pill.className = 'pill-status on';
      label.textContent = 'Conectado';
    } else if (status === 'conectando') {
      pill.className = 'pill-status off';
      label.textContent = 'Conectando...';
    } else {
      pill.className = 'pill-status off';
      label.textContent = 'Reconectando...';
    }
  }

  function pararPollingContingenciaRealtime() {
    if (timerPollingContingenciaRealtime) {
      clearInterval(timerPollingContingenciaRealtime);
      timerPollingContingenciaRealtime = null;
    }
  }

  function iniciarPollingContingenciaRealtime() {
    if (timerPollingContingenciaRealtime) return;
    timerPollingContingenciaRealtime = setInterval(() => {
      if (statusRealtimePedidos !== 'conectado') loadPedidos();
    }, POLLING_CONTINGENCIA_REALTIME_MS);
  }

  function cancelarReconexaoRealtime() {
    if (timerReconexaoRealtime) {
      clearTimeout(timerReconexaoRealtime);
      timerReconexaoRealtime = null;
    }
  }

  function programarReconexaoRealtime() {
    if (timerReconexaoRealtime) return;
    timerReconexaoRealtime = setTimeout(() => {
      timerReconexaoRealtime = null;
      subscribeRealtime();
    }, RECONEXAO_REALTIME_MS);
  }

  function cancelarTimeoutConexaoRealtime() {
    if (timerTimeoutConexaoRealtime) {
      clearTimeout(timerTimeoutConexaoRealtime);
      timerTimeoutConexaoRealtime = null;
    }
  }

  async function removerCanalPedidosRealtime() {
    cancelarTimeoutConexaoRealtime();
    if (!canalPedidosRealtime) return;
    const canalAnterior = canalPedidosRealtime;
    canalPedidosRealtime = null;
    try { await sb.removeChannel(canalAnterior); } catch (e) {}
  }

  function falhaConexaoRealtime() {
    statusRealtimePedidos = 'desconectado';
    inscricaoRealtimeEmAndamento = false;
    cancelarTimeoutConexaoRealtime();
    atualizarPillConexaoRealtime('desconectado');
    iniciarPollingContingenciaRealtime();
    programarReconexaoRealtime();
  }

  async function subscribeRealtime() {
    if (!sb || !restauranteId) return;
    if (statusRealtimePedidos === 'conectado' || inscricaoRealtimeEmAndamento) return;
    inscricaoRealtimeEmAndamento = true;
    cancelarReconexaoRealtime();
    statusRealtimePedidos = 'conectando';
    atualizarPillConexaoRealtime('conectando');

    await removerCanalPedidosRealtime();

    try {
      const novoCanal = sb.channel('pedidos-restaurante-' + restauranteId)
        .on('postgres_changes',
          { event: '*', schema: 'public', table: 'pedidos', filter: `restaurante_id=eq.${restauranteId}` },
          async (payload) => {
            if (canalPedidosRealtime !== novoCanal) return;
            if (payload.eventType === 'INSERT') {
              const idNovo = payload.new?.id;
              if (idNovo && pedidosCriadosManualmente.has(idNovo)) {
                pedidosCriadosManualmente.delete(idNovo);
              } else {
                tocarNovoPedido();
                showToast('Novo pedido recebido', 'Um pedido novo chegou no monitor.');
              }
            }
            await loadPedidos();
          }
        )
        .subscribe((status) => {
          if (canalPedidosRealtime !== novoCanal) return;
          if (status === 'SUBSCRIBED') {
            statusRealtimePedidos = 'conectado';
            inscricaoRealtimeEmAndamento = false;
            cancelarTimeoutConexaoRealtime();
            cancelarReconexaoRealtime();
            pararPollingContingenciaRealtime();
            atualizarPillConexaoRealtime('conectado');
            loadPedidos();
          } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
            falhaConexaoRealtime();
          } else {
            atualizarPillConexaoRealtime('conectando');
          }
        });

      canalPedidosRealtime = novoCanal;

      cancelarTimeoutConexaoRealtime();
      timerTimeoutConexaoRealtime = setTimeout(() => {
        timerTimeoutConexaoRealtime = null;
        if (canalPedidosRealtime !== novoCanal) return;
        if (statusRealtimePedidos !== 'conectando') return;
        falhaConexaoRealtime();
      }, TIMEOUT_CONEXAO_REALTIME_MS);
    } catch (e) {
      falhaConexaoRealtime();
    }
  }

  async function resincronizarRealtime() {
    if (resincronizandoRealtime) return;
    if (!sb || !restauranteId || !currentUser) return;
    resincronizandoRealtime = true;
    try {
      await loadPedidos();
      if (statusRealtimePedidos !== 'conectado') subscribeRealtime();
    } finally {
      resincronizandoRealtime = false;
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') resincronizarRealtime();
  });
  window.addEventListener('focus', resincronizarRealtime);
  window.addEventListener('online', resincronizarRealtime);

  async function advanceStatus(id, status, tipo) {
    let next = FLOW[FLOW.indexOf(status) + 1];
    if (status === 'em_preparo' && tipo === 'retirada') next = 'retirado';
    const { error } = await sb.from('pedidos').update({ status: next })
      .eq('id', id)
      .eq('restaurante_id', restauranteId);
    if (error) { showToast('Erro', error.message); return; }
    await loadPedidos();
  }

  async function atribuirMotoboy(pedidoId, motoboyId) {
    const { error } = await sb.from('pedidos').update({ motoboy_id: motoboyId || null })
      .eq('id', pedidoId)
      .eq('restaurante_id', restauranteId);
    if (error) { showToast('Erro ao atribuir motoboy', error.message); await loadPedidos(); return; }
    await loadPedidos();
  }

  async function marcarPago(id) {
    const { error } = await sb.from('pedidos').update({ pago: true })
      .eq('id', id)
      .eq('restaurante_id', restauranteId);
    if (error) { showToast('Erro', error.message); return; }
    await loadPedidos();
    if (currentView === 'financeiro') { loadMovimentacoes(); loadCaixaAtual(); }
  }

  function imprimirComanda(pedidoId) {
    const o = orders.find(x => x.id === pedidoId) || pedidosHistorico.find(x => x.id === pedidoId);
    if (!o) { showToast('Erro', 'Pedido não encontrado na lista atual.'); return; }

    const moeda = valor => 'R$ ' + Number(valor || 0).toFixed(2).replace('.', ',');
    const seguro = valor => escapeHtml(String(valor ?? ''));

    const nomeRestaurante = (restauranteInfo?.nome || document.getElementById('restauranteNome')?.textContent || 'EAF Menu').toUpperCase();
    const enderecoRestaurante = restauranteInfo?.endereco || '';
    const whatsappRestaurante = restauranteInfo?.whatsapp || '';

    const dataObj = new Date(o.criado_em);
    const timeZone = 'America/Sao_Paulo';
    const dataTxt = dataObj.toLocaleDateString('pt-BR', {
      timeZone, day: '2-digit', month: '2-digit', year: 'numeric'
    });
    const dataCurtaTxt = dataObj.toLocaleDateString('pt-BR', {
      timeZone, day: '2-digit', month: '2-digit'
    });
    const horaTxt = dataObj.toLocaleTimeString('pt-BR', {
      timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
    });

    const cliente = o.clientes?.nome || 'Cliente balcão';
    const telefoneCliente = o.clientes?.telefone || '';

    const end = o.enderecos_cliente;
    const enderecoHtml = (o.tipo === 'entrega' && end?.logradouro)
      ? `<section class="section endereco">
          <h2>ENTREGAR EM</h2>
          <div>${seguro(end.logradouro)}${end.numero ? ', ' + seguro(end.numero) : ''}</div>
          ${end.complemento ? `<div>${seguro(end.complemento)}</div>` : ''}
          ${(end.bairro || end.cidade) ? `<div>${seguro(end.bairro)}${end.bairro && end.cidade ? ' - ' : ''}${seguro(end.cidade)}</div>` : ''}
          ${end.referencia ? `<div class="referencia"><b>Referência:</b> ${seguro(end.referencia)}</div>` : ''}
        </section>`
      : '';

    const itensHtml = (o.itens_pedido || []).map(i => {
      const item = normalizarItemPedido(i);
      const detalhes = item.combinado
        ? `${item.sabores.length ? `<div class="sabores">${item.sabores.map(sabor => `• ${seguro(sabor)}`).join('<br>')}</div>` : ''}
          ${item.observacoes ? `<div class="item-observacao">Obs: ${seguro(item.observacoes)}</div>` : ''}
          <div class="item-valores">${moeda(item.precoUnitario)} un.<br>Total: ${moeda(item.subtotal)}</div>`
        : (item.sabores.length ? `<div class="sabores">${item.sabores.map(sabor => `• ${seguro(sabor)}`).join('<br>')}</div>` : '');
      return `<div class="item">
        <div class="item-linha"><span><b>${seguro(item.quantidade)}x</b> ${seguro(item.nomePrincipal)}</span><b>${moeda(item.subtotal)}</b></div>
        ${detalhes}
      </div>`;
    }).join('');

    const qtdItens = (o.itens_pedido || []).reduce((s, i) => s + Number(i.quantidade || 1), 0);

    const FORMA_LABEL = { dinheiro: 'Dinheiro', pix: 'Pix', cartao: 'Cartão (maquininha)' };
    const formaPagamento = FORMA_LABEL[o.forma_pagamento] || o.forma_pagamento || 'Não informado';
    const trocoHtml = (o.forma_pagamento === 'dinheiro' && o.troco_para)
      ? `<div class="troco"><div>Paga com <b>${moeda(o.troco_para)}</b></div><div>TROCO <b>${moeda(Number(o.troco_para) - Number(o.total))}</b></div></div>`
      : '';

    const horarioFinalPrevisao = o.tipo === 'entrega'
      ? formatarJanelaPrevisao(o.previsao_fim, o.previsao_fim)
      : null;
    const previsaoHtml = horarioFinalPrevisao
      ? `<section class="previsao"><div>ENTREGA PREVISTA PARA</div><strong>${seguro(horarioFinalPrevisao)}</strong></section>`
      : '';
    const subtotalComanda = o.subtotal == null ? NaN : Number(o.subtotal);
    const descontoComanda = o.desconto_manual == null ? 0 : Number(o.desconto_manual);
    const taxaComanda = o.taxa_entrega == null ? 0 : Number(o.taxa_entrega);
    const financeiroHtml = `<section class="financeiro">
      ${Number.isFinite(subtotalComanda) ? `<div class="financeiro-linha"><span>SUBTOTAL</span><b>${moeda(subtotalComanda)}</b></div>` : ''}
      ${Number.isFinite(descontoComanda) && descontoComanda > 0 ? `<div class="financeiro-linha desconto"><span>DESCONTO</span><b>- ${moeda(descontoComanda)}</b></div>` : ''}
      ${Number.isFinite(taxaComanda) && taxaComanda > 0 ? `<div class="financeiro-linha"><span>TAXA DE ENTREGA</span><b>${moeda(taxaComanda)}</b></div>` : ''}
      <div class="total"><span>TOTAL</span><span>${moeda(o.total)}</span></div>
    </section>`;

    const html = `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Comanda ${seguro(codigoPedido(o))}</title>
<style>
  @page { size: 80mm auto; margin: 0; }
  * { box-sizing: border-box; }
  body, body * { color:#000 !important; opacity:1 !important; border-color:#000 !important; }
  html { width:80mm; margin:0; padding:0; overflow-x:hidden; }
  body { width:72mm; max-width:72mm; margin:0; padding:2mm; overflow-x:hidden; font-family:Arial, Helvetica, sans-serif; font-size:12px; line-height:1.35; font-weight:700; background:#fff; overflow-wrap:anywhere; }
  .restaurante { text-align:center; padding-bottom:8px; }
  .restaurante h1 { margin:0 0 3px; font-size:16px; line-height:1.15; font-weight:900; }
  .restaurante div { font-size:11px; }
  .pedido-topo { border-top:2px dashed #000; padding:8px 0 3px; }
  .tipo-data, .item-linha, .qtd-total, .financeiro-linha, .total, .troco div { display:grid; grid-template-columns:minmax(0, 1fr) max-content; align-items:start; gap:4px; width:100%; }
  .tipo-data > :last-child, .item-linha > :last-child, .qtd-total > :last-child, .financeiro-linha > :last-child, .total > :last-child, .troco div > :last-child { white-space:nowrap; text-align:right; justify-self:end; }
  .tipo-data > :first-child, .item-linha > :first-child, .qtd-total > :first-child, .financeiro-linha > :first-child, .total > :first-child, .troco div > :first-child { min-width:0; overflow-wrap:anywhere; }
  .tipo-data b { font-size:12px; font-weight:900; }
  .pedido-numero { margin-top:3px; font-size:17px; font-weight:900; }
  .previsao { margin:8px 0; padding:7px 4px; border-top:3px solid #000; border-bottom:3px solid #000; text-align:center; font-weight:900; }
  .previsao strong { display:block; margin-top:2px; font-size:18px; line-height:1.15; }
  .section { padding:8px 0; border-bottom:1px dashed #000; }
  .section h2 { margin:0 0 4px; font-size:12px; font-weight:900; }
  .section .dado-principal { font-size:13px; font-weight:900; }
  .referencia { margin-top:4px; }
  .itens-cabecalho { display:grid; grid-template-columns:minmax(0, 1fr) max-content; gap:4px; width:100%; padding:6px 0 4px; border-bottom:1px dashed #000; font-weight:900; }
  .itens-cabecalho > :last-child { white-space:nowrap; text-align:right; justify-self:end; }
  .itens-cabecalho > :first-child { min-width:0; overflow-wrap:anywhere; }
  .item { padding:6px 0; border-bottom:1px dotted #000; }
  .item-linha { font-weight:900; }
  .sabores { margin:3px 0 0 18px; font-size:11px; }
  .item-observacao, .item-valores { margin:3px 0 0 18px; font-size:11px; }
  .qtd-total { padding:6px 0; border-bottom:2px solid #000; }
  .financeiro { border-bottom:2px solid #000; }
  .financeiro-linha { padding:6px 0; border-bottom:1px dashed #000; font-weight:900; }
  .total { padding:8px 0; font-size:16px; font-weight:900; border-bottom:2px solid #000; }
  .pagamento { border-bottom:1px dashed #000; font-weight:900; }
  .troco { margin-top:6px; padding:6px; border:2px solid #000; font-size:13px; font-weight:900; }
  .observacoes { margin-top:8px; padding:7px; border:2px solid #000; font-weight:900; }
  .observacoes h2 { margin-bottom:3px; font-weight:900; }
  .rodape { padding-top:8px; text-align:center; font-size:11px; }
  @media print { body { -webkit-print-color-adjust:exact; print-color-adjust:exact; } }
</style>
</head>
<body onload="window.print()">
  <header class="restaurante">
    <h1>${seguro(nomeRestaurante)}</h1>
    ${enderecoRestaurante ? `<div>${seguro(enderecoRestaurante)}</div>` : ''}
    ${whatsappRestaurante ? `<div>Telefone: ${seguro(whatsappRestaurante)}</div>` : ''}
  </header>
  <section class="pedido-topo">
    <div class="tipo-data"><b>${o.tipo === 'entrega' ? 'ENTREGA' : 'RETIRADA'}</b><span>${seguro(dataCurtaTxt)} ${seguro(horaTxt)}</span></div>
    <div class="pedido-numero">PEDIDO ${seguro(codigoPedido(o))}</div>
  </section>
  ${previsaoHtml}
  <section class="section cliente">
    <h2>CLIENTE</h2>
    <div class="dado-principal">${seguro(cliente)}</div>
    ${telefoneCliente ? `<div>${seguro(telefoneCliente)}</div>` : ''}
  </section>
  ${enderecoHtml}
  <section class="section itens">
    <div class="itens-cabecalho"><span>QTD / DESCRIÇÃO</span><span>VALOR</span></div>
    ${itensHtml || '<div class="item">sem itens</div>'}
    <div class="qtd-total"><span>Quantidade de itens:</span><b>${seguro(qtdItens)}</b></div>
  </section>
  ${financeiroHtml}
  <section class="section pagamento">
    <h2>FORMA DE PAGAMENTO</h2>
    <div class="dado-principal">${seguro(formaPagamento)}</div>
    ${trocoHtml}
  </section>
  ${o.observacoes ? `<section class="observacoes"><h2>OBSERVAÇÕES</h2><div>${seguro(o.observacoes)}</div></section>` : ''}
  <footer class="rodape">${seguro(dataTxt)} ${seguro(horaTxt)}<br>${seguro(restauranteInfo?.nome || nomeRestaurante)}</footer>
</body></html>`;

    const janela = window.open('', '_blank', 'width=380,height=600');
    if (!janela) { showToast('Bloqueado pelo navegador', 'Permita pop-ups pra imprimir a comanda.'); return; }
    janela.document.write(html);
    janela.document.close();
  }

  function beep() {
    if (!soundOn) return;
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      [880, 1180].forEach((freq, i) => {
        const t0 = audioCtx.currentTime + i * 0.11;
        const osc = audioCtx.createOscillator(); const gain = audioCtx.createGain();
        osc.type = 'sine'; osc.frequency.value = freq;
        gain.gain.setValueAtTime(0.001, t0);
        gain.gain.exponentialRampToValueAtTime(0.18, t0 + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.001, t0 + 0.16);
        osc.connect(gain); gain.connect(audioCtx.destination);
        osc.start(t0); osc.stop(t0 + 0.18);
      });
    } catch (e) {}
  }

  function testAlert() { beep(); showToast('Teste de alerta', 'Assim que soa um pedido novo.'); }

  // =====================================================================
  // CANCELAMENTO DE PEDIDO (segurança real fica na RPC cancelar_pedido_v2 no banco;
  // o frontend só coleta motivo/senha e mostra o erro amigável se a RPC recusar)
  // =====================================================================
  function abrirCancelarPedido(pedidoId) {
    const pedido = orders.find(item => item.id === pedidoId)
      || pedidosHistorico.find(item => item.id === pedidoId);
    if (pedido?.status === 'cancelado') {
      showToast('Pedido já cancelado', 'Este pedido já está cancelado.');
      return;
    }
    if (['entregue', 'retirado'].includes(pedido?.status) && !pedidoFinalizadoPodeSerCancelado(pedido)) {
      showToast('Prazo encerrado', 'Pedidos finalizados só podem ser cancelados nas primeiras 24 horas.');
      return;
    }
    document.getElementById('cpPedidoId').value = pedidoId;
    document.getElementById('cpPedidoResumo').textContent =
      `${codigoPedido(pedido)} · ${formatMoeda(pedido.total)} · ${formatarFormaPagamentoCancelamento(pedido.forma_pagamento)}`;
    document.getElementById('cpPedidoPago').value = pedido.pago ? 'true' : 'false';
    document.getElementById('cpMotivo').value = '';
    document.getElementById('cpSenha').value = '';
    document.querySelectorAll('input[name="cpDecisaoFinanceira"]').forEach(input => { input.checked = false; });
    document.getElementById('cpEscolhaFinanceira').classList.toggle('hidden', !pedido.pago);
    document.getElementById('cpInformacaoFinanceira').textContent = pedido.pago
      ? 'Este pedido foi pago. Escolha explicitamente como o valor recebido deve ser tratado.'
      : 'Este pedido não foi pago. O cancelamento não gera movimentação financeira.';
    document.getElementById('cpImpactoFinanceiro').textContent = pedido.pago
      ? 'Escolha uma opção para visualizar o impacto financeiro.'
      : 'Sem impacto financeiro.';
    document.getElementById('cpErro').classList.add('hidden');
    document.getElementById('cancelarPedidoModalBg').classList.add('show');
  }

  function fecharCancelarPedido() {
    document.getElementById('cancelarPedidoModalBg').classList.remove('show');
    document.getElementById('cpSenha').value = '';
    document.querySelectorAll('input[name="cpDecisaoFinanceira"]').forEach(input => { input.checked = false; });
  }

  function formatarFormaPagamentoCancelamento(forma) {
    return ({ dinheiro: 'Dinheiro', pix: 'Pix', cartao: 'Cartão' })[forma] || forma || 'Não informada';
  }

  function atualizarImpactoCancelamento() {
    const pedidoId = document.getElementById('cpPedidoId').value;
    const pedido = orders.find(item => item.id === pedidoId)
      || pedidosHistorico.find(item => item.id === pedidoId);
    const decisao = document.querySelector('input[name="cpDecisaoFinanceira"]:checked')?.value;
    const impactoEl = document.getElementById('cpImpactoFinanceiro');
    if (decisao === 'estornar') {
      impactoEl.textContent = `Será criada uma saída financeira de ${formatMoeda(pedido?.total)}. A receita original continuará registrada.`;
    } else if (decisao === 'manter_recebido') {
      impactoEl.textContent = 'O pedido será cancelado, mas o valor continuará registrado como recebido.';
    } else {
      impactoEl.textContent = 'Escolha uma opção para visualizar o impacto financeiro.';
    }
  }

  async function atualizarFinanceiroAposCancelamento() {
    const tarefas = [];
    const podeConsultarFinanceiro = currentUser?.role === 'dono' || currentUser?.role === 'gerente';
    if (podeConsultarFinanceiro && typeof loadMovimentacoes === 'function') tarefas.push(loadMovimentacoes());
    if (podeConsultarFinanceiro && typeof loadCaixaAtual === 'function') tarefas.push(loadCaixaAtual());
    if (currentUser?.role === 'dono' && currentView === 'relatorio'
        && typeof loadRelatorioFinanceiro === 'function') {
      tarefas.push(loadRelatorioFinanceiro());
    }
    await Promise.allSettled(tarefas);
  }

  async function submitCancelarPedido() {
    if (cancelamentoPedidoEmAndamento) return;
    const pedidoId = document.getElementById('cpPedidoId').value;
    const motivo = document.getElementById('cpMotivo').value.trim();
    const senha = document.getElementById('cpSenha').value;
    const pedidoPago = document.getElementById('cpPedidoPago').value === 'true';
    const decisaoFinanceira = document.querySelector('input[name="cpDecisaoFinanceira"]:checked')?.value || null;
    const erroEl = document.getElementById('cpErro');
    erroEl.classList.add('hidden');

    if (!motivo) { erroEl.textContent = 'Informe o motivo do cancelamento.'; erroEl.classList.remove('hidden'); return; }
    if (!senha) { erroEl.textContent = 'Informe a senha de confirmação.'; erroEl.classList.remove('hidden'); return; }

    if (pedidoPago && !decisaoFinanceira) {
      erroEl.textContent = 'Escolha se o valor será estornado ou mantido como recebido.';
      erroEl.classList.remove('hidden');
      return;
    }

    const btn = document.getElementById('cpConfirmarBtn');
    cancelamentoPedidoEmAndamento = true;
    btn.disabled = true; btn.textContent = 'Cancelando...';

    let data;
    let error;
    try {
      ({ data, error } = await sb.rpc('cancelar_pedido_v2', {
        p_pedido_id: pedidoId,
        p_motivo: motivo,
        p_senha_confirmacao: senha,
        p_decisao_financeira: pedidoPago ? decisaoFinanceira : null
      }));
    } catch (excecao) {
      document.getElementById('cpSenha').value = '';
      erroEl.textContent = 'Não foi possível confirmar a resposta do servidor. Tente novamente; o sistema verificará se a operação já foi processada.';
      erroEl.classList.remove('hidden');
      return;
    } finally {
      cancelamentoPedidoEmAndamento = false;
      btn.disabled = false; btn.textContent = 'Confirmar cancelamento';
    }

    if (error) {
      erroEl.textContent = error.message;
      erroEl.classList.remove('hidden');
      return;
    }

    const resultado = Array.isArray(data) ? data[0] : data;
    fecharCancelarPedido();
    const mensagem = resultado?.decisao_financeira === 'estornado' || resultado?.decisao_financeira === 'estornar'
      ? 'Pedido cancelado e valor estornado.'
      : resultado?.decisao_financeira === 'mantido' || resultado?.decisao_financeira === 'manter_recebido'
        ? 'Pedido cancelado e valor mantido como recebido.'
        : 'Pedido cancelado sem impacto financeiro.';
    showToast(resultado?.reutilizado ? 'Cancelamento já processado' : 'Pedido cancelado', mensagem);
    if (modoListaPedidos === 'historico') {
      await buscarHistoricoPedidos(true);
    } else {
      await loadPedidos();
    }
    await atualizarFinanceiroAposCancelamento();
  }

  function abrirResolverCancelamentoFinanceiro(pedidoId) {
    const pedido = pedidosHistorico.find(item => item.id === pedidoId);
    if (!pedido || pedido.status !== 'cancelado' || !pedido.pago
        || pedido.cancelamento_decisao_financeira !== 'pendente') {
      showToast('Decisão indisponível', 'Este cancelamento não está aguardando decisão financeira.');
      return;
    }
    document.getElementById('rcfPedidoId').value = pedidoId;
    document.getElementById('rcfPedidoResumo').textContent =
      `${codigoPedido(pedido)} · ${formatMoeda(pedido.total)} · ${formatarFormaPagamentoCancelamento(pedido.forma_pagamento)}`;
    document.getElementById('rcfMotivoOriginal').textContent =
      pedido.motivo_cancelamento || 'Sem motivo informado.';
    document.getElementById('rcfSenha').value = '';
    document.querySelectorAll('input[name="rcfDecisaoFinanceira"]').forEach(input => { input.checked = false; });
    document.getElementById('rcfImpactoFinanceiro').textContent =
      'Escolha uma opção para visualizar o impacto financeiro.';
    document.getElementById('rcfErro').classList.add('hidden');
    document.getElementById('resolverCancelamentoFinanceiroModalBg').classList.add('show');
  }

  function fecharResolverCancelamentoFinanceiro() {
    document.getElementById('resolverCancelamentoFinanceiroModalBg').classList.remove('show');
    document.getElementById('rcfSenha').value = '';
    document.querySelectorAll('input[name="rcfDecisaoFinanceira"]').forEach(input => { input.checked = false; });
  }

  function atualizarImpactoResolucaoFinanceira() {
    const pedidoId = document.getElementById('rcfPedidoId').value;
    const pedido = pedidosHistorico.find(item => item.id === pedidoId);
    const decisao = document.querySelector('input[name="rcfDecisaoFinanceira"]:checked')?.value;
    document.getElementById('rcfImpactoFinanceiro').textContent = decisao === 'estornar'
      ? `Será criada uma saída financeira de ${formatMoeda(pedido?.total)}. A receita original continuará registrada.`
      : decisao === 'manter_recebido'
        ? 'O valor continuará registrado como recebido e nenhuma saída será criada.'
        : 'Escolha uma opção para visualizar o impacto financeiro.';
  }

  async function submitResolverCancelamentoFinanceiro() {
    if (resolucaoFinanceiraEmAndamento) return;
    const pedidoId = document.getElementById('rcfPedidoId').value;
    const decisao = document.querySelector('input[name="rcfDecisaoFinanceira"]:checked')?.value;
    const senha = document.getElementById('rcfSenha').value;
    const erroEl = document.getElementById('rcfErro');
    erroEl.classList.add('hidden');
    if (!decisao) {
      erroEl.textContent = 'Escolha se o valor será estornado ou mantido como recebido.';
      erroEl.classList.remove('hidden');
      return;
    }
    if (!senha) {
      erroEl.textContent = 'Informe a senha de confirmação.';
      erroEl.classList.remove('hidden');
      return;
    }

    const btn = document.getElementById('rcfConfirmarBtn');
    resolucaoFinanceiraEmAndamento = true;
    btn.disabled = true;
    btn.textContent = 'Resolvendo...';
    let data;
    let error;
    try {
      ({ data, error } = await sb.rpc('resolver_cancelamento_financeiro_v1', {
        p_pedido_id: pedidoId,
        p_decisao_financeira: decisao,
        p_senha_confirmacao: senha
      }));
    } catch (excecao) {
      document.getElementById('rcfSenha').value = '';
      erroEl.textContent = 'Não foi possível confirmar a resposta do servidor. Tente novamente; o sistema verificará se a operação já foi processada.';
      erroEl.classList.remove('hidden');
      return;
    } finally {
      resolucaoFinanceiraEmAndamento = false;
      btn.disabled = false;
      btn.textContent = 'Confirmar decisão';
    }

    if (error) {
      erroEl.textContent = error.message;
      erroEl.classList.remove('hidden');
      return;
    }

    const resultado = Array.isArray(data) ? data[0] : data;
    fecharResolverCancelamentoFinanceiro();
    showToast(
      resultado?.reutilizado ? 'Decisão já processada' : 'Decisão financeira registrada',
      decisao === 'estornar' ? 'Valor estornado.' : 'Valor mantido como recebido.'
    );
    await buscarHistoricoPedidos(true);
    await atualizarFinanceiroAposCancelamento();
  }
