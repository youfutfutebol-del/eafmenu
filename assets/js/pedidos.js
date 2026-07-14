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

  async function loadPedidos() {
    const inicio = inicioDiaComercial().toISOString();
    const { data, error } = await sb
      .from('pedidos')
      .select(`
        id, numero_diario, tipo, status, pago, forma_pagamento, total, criado_em, motoboy_id, troco_para, observacoes, previsao_inicio, previsao_fim,
        clientes ( nome ),
        enderecos_cliente!endereco_entrega_id ( logradouro, numero, bairro, cidade, complemento, referencia ),
        itens_pedido ( quantidade, produtos ( nome ), itens_pedido_sabores ( produtos ( nome ) ) )
      `)
      .eq('restaurante_id', restauranteId)
      .gte('criado_em', inicio)
      .order('criado_em', { ascending: false })
      .limit(200);
    if (error) { console.error(error); return; }
    orders = data || [];
    atualizarSubtituloPedidos();
    renderOrders();
  }

  function subscribeRealtime() {
    sb.channel('pedidos-restaurante-' + restauranteId)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'pedidos', filter: `restaurante_id=eq.${restauranteId}` },
        async (payload) => {
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
        const isOn = status === 'SUBSCRIBED';
        document.getElementById('connPill').className = 'pill-status ' + (isOn ? 'on' : 'off');
        document.getElementById('connLabel').textContent = isOn ? 'Conectado' : 'Conectando...';
      });
  }

  async function advanceStatus(id, status, tipo) {
    let next = FLOW[FLOW.indexOf(status) + 1];
    if (status === 'em_preparo' && tipo === 'retirada') next = 'retirado';
    const { error } = await sb.from('pedidos').update({ status: next }).eq('id', id);
    if (error) { showToast('Erro', error.message); return; }
    await loadPedidos();
  }

  async function atribuirMotoboy(pedidoId, motoboyId) {
    const { error } = await sb.from('pedidos').update({ motoboy_id: motoboyId || null }).eq('id', pedidoId);
    if (error) { showToast('Erro ao atribuir motoboy', error.message); await loadPedidos(); return; }
    await loadPedidos();
  }

  async function marcarPago(id) {
    const { error } = await sb.from('pedidos').update({ pago: true }).eq('id', id);
    if (error) { showToast('Erro', error.message); return; }
    await loadPedidos();
    if (currentView === 'financeiro') { loadMovimentacoes(); loadCaixaAtual(); }
  }

  function imprimirComanda(pedidoId) {
    const o = orders.find(x => x.id === pedidoId);
    if (!o) { showToast('Erro', 'Pedido não encontrado na lista atual.'); return; }

    const LARGURA = 42; // colunas aproximadas de uma bobina de 80mm em fonte monoespaçada
    const linhaTracejada = '-'.repeat(LARGURA);

    function linhaValor(desc, valor) {
      const valorTxt = 'R$ ' + Number(valor).toFixed(2).replace('.', ',');
      const espacos = Math.max(1, LARGURA - desc.length - valorTxt.length);
      return desc + ' '.repeat(espacos) + valorTxt;
    }
    function linhaDireita(desc, valorTxt) {
      const espacos = Math.max(1, LARGURA - desc.length - valorTxt.length);
      return desc + ' '.repeat(espacos) + valorTxt;
    }

    const nomeRestaurante = (restauranteInfo?.nome || document.getElementById('restauranteNome')?.textContent || 'EAF Menu').toUpperCase();
    const enderecoRestaurante = restauranteInfo?.endereco || '';
    const whatsappRestaurante = restauranteInfo?.whatsapp || '';

    const dataObj = new Date(o.criado_em);
    const dataTxt = dataObj.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
    const horaTxt = dataObj.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

    const cliente = o.clientes?.nome || 'Cliente balcão';
    const telefoneCliente = o.clientes?.telefone || '';

    const end = o.enderecos_cliente;
    const enderecoLinhas = (o.tipo === 'entrega' && end?.logradouro)
      ? [
          `${end.logradouro}${end.numero ? ', ' + end.numero : ''}`,
          end.complemento || null,
          `${end.bairro || ''}${end.cidade ? ' - ' + end.cidade : ''}`
        ].filter(Boolean).join('\n')
      : null;

    // Itens — cada linha principal com valor à direita, e sub-linhas de sabores indentadas (igual cupom real de pizza meio a meio)
    const itensLinhas = (o.itens_pedido || []).map(i => {
      const sabores = (i.itens_pedido_sabores || []).map(s => s.produtos?.nome).filter(Boolean);
      const nomePrincipal = i.produtos?.nome || (sabores.length ? sabores.join(' + ') : 'item');
      const valorItem = Number(i.preco_unitario || 0) * Number(i.quantidade || 1);
      let bloco = linhaValor(`${i.quantidade}x ${nomePrincipal}`, valorItem);
      if (sabores.length > 1) {
        bloco += '\n' + sabores.map(s => `   -1x ${s}`).join('\n');
      }
      return bloco;
    }).join('\n');

    const qtdItens = (o.itens_pedido || []).reduce((s, i) => s + Number(i.quantidade || 1), 0);

    const FORMA_LABEL = { dinheiro: 'Dinheiro', pix: 'Pix', cartao: 'Cartão (maquininha)' };
    let pagamentoLinhas = linhaValor(FORMA_LABEL[o.forma_pagamento] || o.forma_pagamento, o.total);
    if (o.forma_pagamento === 'dinheiro' && o.troco_para) {
      pagamentoLinhas += `\nPaga com R$ ${Number(o.troco_para).toFixed(2).replace('.', ',')}`;
      pagamentoLinhas += '\n' + linhaValor('TROCO', Number(o.troco_para) - Number(o.total));
    }

    const janelaPrevisao = o.tipo === 'entrega'
      ? formatarJanelaPrevisao(o.previsao_inicio, o.previsao_fim)
      : null;
    const previsaoLinhas = janelaPrevisao
      ? `${linhaTracejada}\nPREVISAO DE ENTREGA\n${janelaPrevisao.replace('–', ' A ')}\n${linhaTracejada}`
      : null;

    const corpo = [
      nomeRestaurante,
      enderecoRestaurante,
      whatsappRestaurante ? 'Tel: ' + whatsappRestaurante : null,
      linhaTracejada,
      linhaDireita(o.tipo === 'entrega' ? 'ENTREGA' : 'RETIRADA', dataTxt + ' ' + horaTxt),
      `Pedido: ${codigoPedido(o)}`,
      previsaoLinhas,
      cliente,
      telefoneCliente ? 'Telefone: ' + telefoneCliente : null,
      `Status: ${o.pago ? 'PAGO' : 'PENDENTE'}`,
      o.observacoes ? 'OBS: ' + o.observacoes : null,
      linhaTracejada,
      enderecoLinhas ? 'ENTREGAR EM:\n' + enderecoLinhas : null,
      end?.referencia ? 'REFERÊNCIA: ' + end.referencia : null,
      enderecoLinhas ? linhaTracejada : null,
      linhaDireita('Qt. Descrição', 'Valor'),
      linhaTracejada,
      itensLinhas || 'sem itens',
      linhaTracejada,
      linhaDireita('Quantidade de itens:', String(qtdItens)),
      linhaTracejada,
      linhaValor('TOTAL', o.total),
      linhaTracejada,
      'FORMA DE PAGAMENTO',
      pagamentoLinhas,
      linhaTracejada,
      `${dataTxt} ${horaTxt}`,
      restauranteInfo?.nome || nomeRestaurante
    ].filter(l => l !== null).join('\n');

    const html = `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><title>Comanda ${codigoPedido(o)}</title>
<style>
  @page { size: 80mm auto; margin: 3mm; }
  * { box-sizing: border-box; }
  body { font-family: 'Courier New', ui-monospace, monospace; font-size: 12.5px; line-height:1.45; color:#000; width: 100%; margin:0; padding:0; white-space: pre-wrap; word-break: break-word; }
  @media print { body { -webkit-print-color-adjust: exact; } }
</style>
</head>
<body onload="window.print()">${corpo}</body></html>`;

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
  // CANCELAMENTO DE PEDIDO (segurança real fica na RPC cancelar_pedido no banco;
  // o frontend só coleta motivo/senha e mostra o erro amigável se a RPC recusar)
  // =====================================================================
  function abrirCancelarPedido(pedidoId) {
    document.getElementById('cpPedidoId').value = pedidoId;
    document.getElementById('cpMotivo').value = '';
    document.getElementById('cpSenha').value = '';
    document.getElementById('cpErro').classList.add('hidden');
    document.getElementById('cancelarPedidoModalBg').classList.add('show');
  }

  function fecharCancelarPedido() {
    document.getElementById('cancelarPedidoModalBg').classList.remove('show');
  }

  async function submitCancelarPedido() {
    const pedidoId = document.getElementById('cpPedidoId').value;
    const motivo = document.getElementById('cpMotivo').value.trim();
    const senha = document.getElementById('cpSenha').value;
    const erroEl = document.getElementById('cpErro');
    erroEl.classList.add('hidden');

    if (!motivo) { erroEl.textContent = 'Informe o motivo do cancelamento.'; erroEl.classList.remove('hidden'); return; }
    if (!senha) { erroEl.textContent = 'Informe a senha de confirmação.'; erroEl.classList.remove('hidden'); return; }

    const btn = document.getElementById('cpConfirmarBtn');
    btn.disabled = true; btn.textContent = 'Cancelando...';

    const { error } = await sb.rpc('cancelar_pedido', {
      p_pedido_id: pedidoId,
      p_motivo: motivo,
      p_senha_confirmacao: senha
    });

    btn.disabled = false; btn.textContent = 'Confirmar cancelamento';

    if (error) {
      erroEl.textContent = error.message;
      erroEl.classList.remove('hidden');
      return;
    }

    fecharCancelarPedido();
    showToast('Pedido cancelado', motivo);
    await loadPedidos();
  }
