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
        id, numero_diario, tipo, status, pago, forma_pagamento, subtotal, taxa_entrega, total, desconto_tipo, desconto_valor_informado, desconto_manual, desconto_motivo, criado_em, motoboy_id, troco_para, observacoes, previsao_inicio, previsao_fim,
        clientes ( nome, telefone ),
        enderecos_cliente!endereco_entrega_id ( logradouro, numero, bairro, cidade, complemento, referencia ),
        itens_pedido (
          produto_id, nome_grupo_snapshot, nome_tamanho_snapshot, sabores_esperados, precificacao_finalizada_em,
          preco_unitario, quantidade, observacoes,
          produtos ( nome ),
          itens_pedido_sabores ( produto_id, nome_produto_snapshot, preco_unitario, ordem, produtos ( nome ) )
        )
      `)
      .eq('restaurante_id', restauranteId)
      .gte('criado_em', inicio)
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
    orders = data || [];
    atualizarSubtituloPedidos();
    renderOrders();
    return true;
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
