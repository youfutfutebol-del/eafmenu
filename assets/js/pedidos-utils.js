// /assets/js/pedidos-utils.js
// Funcoes auxiliares de pedido SEM query no Supabase, extraidas do index.html (Etapa 4).
// Dependem de globais do script principal: orders, filtroPedidos, motoboysAtivosCache,
// STATUS_LABEL, STATUS_FINAIS, NEXT_LABEL. So chamadas apos o script principal rodar.
// Continuam globais (sem type=module).

  function timeAgo(iso) {
    const min = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
    if (min < 1) return 'agora';
    if (min < 60) return min + ' min atrás';
    return Math.floor(min/60) + 'h' + (min%60) + 'min atrás';
  }

  function codigoPedido(o) {
    return (o.numero_diario != null) ? ('#' + o.numero_diario) : ('#' + o.id.slice(0,8).toUpperCase());
  }

  function setFiltroPedidos(f) {
    filtroPedidos = f;
    document.querySelectorAll('#filterTabsPedidos .tab').forEach(t => t.classList.toggle('active', t.dataset.f === f));
    renderOrders();
  }

  function renderOrders() {
    const filtered = orders.filter(o => filtroPedidos === 'todos' ? true : (filtroPedidos === 'pago' ? o.pago : !o.pago));
    document.getElementById('filterCountPedidos').textContent = `Mostrando ${filtered.length} de ${orders.length} pedidos`;

    const list = document.getElementById('orderList');
    if (filtered.length === 0) {
      list.innerHTML = `<div class="empty-state"><div class="ic">📋</div><h4>Nenhum pedido por aqui</h4><p>Os pedidos enviados pela página pública aparecerão aqui instantaneamente.</p></div>`;
      return;
    }

    list.innerHTML = filtered.map(o => {
      const itens = (o.itens_pedido || []).map(i => {
        const nomeSabores = i.produtos?.nome || (i.itens_pedido_sabores || []).map(s => s.produtos?.nome).filter(Boolean).join(' + ') || 'item';
        return `${i.quantidade}x ${nomeSabores}`;
      }).join(' · ');
      const cliente = o.clientes?.nome || 'Cliente balcão';
      const tipoBadge = o.tipo === 'entrega' ? `<span class="badge entrega">🛵 entrega</span>` : `<span class="badge retirada">🏠 retirada</span>`;
      const pagoBadge = o.pago ? `<span class="badge pago">pago</span>` : `<span class="badge pendente">pendente</span>`;
      const statusBadge = `<span class="badge status">${STATUS_LABEL[o.status] || o.status}</span>`;

      const end = o.enderecos_cliente;
      const enderecoLinha = (o.tipo === 'entrega' && end?.logradouro)
        ? `<div class="order-itens" style="margin-top:2px;">📍 ${end.logradouro}${end.numero ? ', ' + end.numero : ''}${end.bairro ? ' - ' + end.bairro : ''}</div>`
        : '';
      const trocoLinha = (o.forma_pagamento === 'dinheiro' && o.troco_para)
        ? `<div class="order-itens" style="margin-top:2px; color:var(--amber); font-weight:700;">💵 Troco: R$ ${(Number(o.troco_para) - Number(o.total)).toFixed(2).replace('.', ',')} (paga com R$ ${Number(o.troco_para).toFixed(2).replace('.', ',')})</div>`
        : '';

      const motoboySelect = (o.tipo === 'entrega' && !STATUS_FINAIS.includes(o.status))
        ? `<select onchange="atribuirMotoboy('${o.id}', this.value)" style="margin-top:6px; font-size:11.5px; padding:5px 8px; border:1px solid var(--border); border-radius:7px; max-width:170px;">
             <option value="">🛵 Sem motoboy</option>
             ${motoboysAtivosCache.map(m => `<option value="${m.id}" ${o.motoboy_id === m.id ? 'selected' : ''}>${m.nome}</option>`).join('')}
           </select>`
        : '';

      let actionHtml;
      if (STATUS_FINAIS.includes(o.status)) {
        actionHtml = `<div class="done">✓ ${STATUS_LABEL[o.status] || 'Concluído'}</div>`;
      } else {
        actionHtml = `<button onclick="advanceStatus('${o.id}','${o.status}','${o.tipo}')">${NEXT_LABEL[o.status] || 'Avançar'}</button>`;
      }
      if (!o.pago) {
        actionHtml += `<button class="pago-btn" onclick="marcarPago('${o.id}')">Marcar pago</button>`;
      }
      actionHtml += `<button class="pago-btn" onclick="imprimirComanda('${o.id}')">🖨️ Imprimir</button>`;

      return `
        <div class="order-row">
          <div class="order-main">
            <div class="order-code">${codigoPedido(o)} · ${timeAgo(o.criado_em)}</div>
            <div class="order-cliente">${cliente}</div>
            <div class="order-itens">${itens || 'sem itens'}</div>
            ${enderecoLinha}
            ${trocoLinha}
          </div>
          <div class="order-badges">${tipoBadge}${statusBadge}${pagoBadge}</div>
          <div class="order-total">R$ ${Number(o.total).toFixed(2).replace('.', ',')}</div>
          <div class="order-action">${actionHtml}${motoboySelect}</div>
        </div>`;
    }).join('');
  }
