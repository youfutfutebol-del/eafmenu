// /assets/js/pedido-manual.js
// Logica do Pedido Manual (lancado pelo atendente/dono direto no painel), extraida do index.html (Etapa 12).
// Dependem de globais/funcoes do script principal: sb, restauranteId, produtosCache,
// clienteEncontradoAtual, enderecoEncontradoAtual, buscaTelefoneTimer, showToast (utils.js),
// loadPedidos() (pedidos.js). So chamadas apos o script principal rodar.
// Continuam globais (sem type=module).

  function openManualOrder() {
    document.getElementById('mItens').innerHTML = '';
    document.getElementById('mCliTel').value = '';
    document.getElementById('mCliNome').value = '';
    document.getElementById('mTipo').value = 'retirada';
    document.getElementById('mEndLogradouro').value = '';
    document.getElementById('mEndNumero').value = '';
    document.getElementById('mEndBairro').value = '';
    document.getElementById('mEndComplemento').value = '';
    document.getElementById('mForma').value = 'dinheiro';
    document.getElementById('mTrocoPara').value = '';
    onFormaPagamentoManualChange();
    limparLookupCliente();
    onTipoManualChange();
    addItemLine();
    document.getElementById('manualModalBg').classList.add('show');
  }

  function closeManualOrder() { document.getElementById('manualModalBg').classList.remove('show'); }

  function onFormaPagamentoManualChange() {
    const isDinheiro = document.getElementById('mForma').value === 'dinheiro';
    document.getElementById('mCampoTroco').style.display = isDinheiro ? 'block' : 'none';
    if (!isDinheiro) document.getElementById('mTrocoPara').value = '';
  }

  function onTipoManualChange() {
    const isEntrega = document.getElementById('mTipo').value === 'entrega';
    document.getElementById('enderecoFields').classList.toggle('show', isEntrega);
  }

  function limparLookupCliente() {
    clienteEncontradoAtual = null;
    enderecoEncontradoAtual = null;
    const box = document.getElementById('clienteLookupBox');
    box.className = 'cliente-lookup-box';
    box.innerHTML = '';
  }

  function onTelefoneManualInput() {
    // Se o telefone mudar depois de já ter encontrado/preenchido um cliente, invalida o match anterior.
    if (clienteEncontradoAtual) limparLookupCliente();
    clearTimeout(buscaTelefoneTimer);
    const tel = document.getElementById('mCliTel').value.trim();
    if (tel.length < 8) return;
    // Busca automática com um pequeno debounce, sem depender só do onblur.
    buscaTelefoneTimer = setTimeout(buscarClientePorTelefone, 500);
  }

  async function buscarClientePorTelefone() {
    const tel = document.getElementById('mCliTel').value.trim();
    const box = document.getElementById('clienteLookupBox');
    if (!tel) { limparLookupCliente(); return; }

    const { data: cliente, error } = await sb.from('clientes')
      .select('id, nome, telefone')
      .eq('restaurante_id', restauranteId)
      .eq('telefone', tel)
      .maybeSingle();

    if (error) { console.error(error); return; }

    if (cliente) {
      clienteEncontradoAtual = cliente;
      document.getElementById('mCliNome').value = cliente.nome;

      const { data: enderecos } = await sb.from('enderecos_cliente')
        .select('id, logradouro, numero, bairro, complemento, padrao')
        .eq('cliente_id', cliente.id)
        .order('padrao', { ascending: false })
        .limit(1);

      if (enderecos && enderecos.length > 0) {
        enderecoEncontradoAtual = enderecos[0];
        document.getElementById('mEndLogradouro').value = enderecos[0].logradouro || '';
        document.getElementById('mEndNumero').value = enderecos[0].numero || '';
        document.getElementById('mEndBairro').value = enderecos[0].bairro || '';
        document.getElementById('mEndComplemento').value = enderecos[0].complemento || '';
      } else {
        enderecoEncontradoAtual = null;
      }

      const { count } = await sb.from('pedidos')
        .select('id', { count: 'exact', head: true })
        .eq('cliente_id', cliente.id);

      box.className = 'cliente-lookup-box found';
      box.innerHTML = `<b>✓ Cliente encontrado</b>${count || 0} pedido(s) anterior(es) · dados preenchidos automaticamente`;
    } else {
      clienteEncontradoAtual = null;
      enderecoEncontradoAtual = null;
      box.className = 'cliente-lookup-box new';
      box.innerHTML = `<b>Cliente novo</b>Será cadastrado automaticamente ao lançar o pedido.`;
    }
  }

  function addItemLine() {
    const wrap = document.getElementById('mItens');
    const row = document.createElement('div');
    row.className = 'item-line';
    const options = produtosCache.flatMap(p => (p.produto_precos || []).map(pp =>
      `<option value="${pp.id}">${p.nome}${pp.opcoes_tamanho ? ' - ' + pp.opcoes_tamanho.nome : ''} (R$ ${Number(pp.preco).toFixed(2)})</option>`
    )).join('');
    row.innerHTML = `<select class="mItemPreco">${options || '<option value="">cadastre produtos primeiro</option>'}</select>
                      <input class="mItemQtd" type="number" min="1" value="1">`;
    wrap.appendChild(row);
  }

  async function submitManualOrder() {
    const nome = document.getElementById('mCliNome').value.trim();
    if (!nome) { showToast('Faltou o nome', 'Informe o nome do cliente.'); return; }
    const telefone = document.getElementById('mCliTel').value.trim();
    const tipo = document.getElementById('mTipo').value;
    const forma = document.getElementById('mForma').value;
    const trocoParaRaw = document.getElementById('mTrocoPara').value;

    // Reutiliza o cliente encontrado pelo telefone; só cria um novo se não houve match.
    let clienteId;
    if (clienteEncontradoAtual && clienteEncontradoAtual.telefone === telefone) {
      clienteId = clienteEncontradoAtual.id;
      if (clienteEncontradoAtual.nome !== nome) {
        await sb.from('clientes').update({ nome }).eq('id', clienteId);
      }
    } else {
      // Checagem final por telefone antes de criar — evita duplicidade se a busca
      // automática (com debounce) ainda não tinha rodado quando o pedido foi enviado.
      let clienteExistente = null;
      if (telefone) {
        const { data } = await sb.from('clientes')
          .select('id, nome')
          .eq('restaurante_id', restauranteId)
          .eq('telefone', telefone)
          .maybeSingle();
        clienteExistente = data;
      }

      if (clienteExistente) {
        clienteId = clienteExistente.id;
        if (clienteExistente.nome !== nome) {
          await sb.from('clientes').update({ nome }).eq('id', clienteId);
        }
      } else {
        const { data: cliente, error: cliErr } = await sb.from('clientes')
          .insert({ nome, telefone: telefone || null, restaurante_id: restauranteId, auth_user_id: null })
          .select().single();

        if (cliErr) {
          // Corrida rara: alguém criou o mesmo telefone entre a checagem acima e o insert.
          if (cliErr.code === '23505' && telefone) {
            const { data: clienteCorrida } = await sb.from('clientes')
              .select('id').eq('restaurante_id', restauranteId).eq('telefone', telefone).maybeSingle();
            if (clienteCorrida) {
              clienteId = clienteCorrida.id;
            } else {
              showToast('Erro ao criar cliente', cliErr.message);
              return;
            }
          } else {
            showToast('Erro ao criar cliente', cliErr.message);
            return;
          }
        } else {
          clienteId = cliente.id;
        }
      }
    }

    // Endereço de entrega (só quando o tipo é entrega)
    let enderecoId = null;
    if (tipo === 'entrega') {
      const logradouro = document.getElementById('mEndLogradouro').value.trim();
      const numero = document.getElementById('mEndNumero').value.trim();
      const bairro = document.getElementById('mEndBairro').value.trim();
      const complemento = document.getElementById('mEndComplemento').value.trim();
      if (!logradouro) { showToast('Faltou o endereço', 'Informe o endereço de entrega.'); return; }

      const mesmoEnderecoDoLookup = enderecoEncontradoAtual
        && enderecoEncontradoAtual.logradouro === logradouro
        && (enderecoEncontradoAtual.numero || '') === numero
        && (enderecoEncontradoAtual.bairro || '') === bairro
        && (enderecoEncontradoAtual.complemento || '') === complemento;

      if (mesmoEnderecoDoLookup) {
        enderecoId = enderecoEncontradoAtual.id;
      } else {
        const { data: novoEndereco, error: endErr } = await sb.from('enderecos_cliente')
          .insert({ cliente_id: clienteId, logradouro, numero, bairro, complemento: complemento || null })
          .select().single();
        if (endErr) { showToast('Erro ao salvar endereço', endErr.message); return; }
        enderecoId = novoEndereco.id;
      }
    }

    const linhas = [...document.querySelectorAll('#mItens .item-line')].map(row => ({
      precoId: row.querySelector('.mItemPreco').value,
      qtd: parseInt(row.querySelector('.mItemQtd').value || '1', 10)
    })).filter(l => l.precoId);

    if (linhas.length === 0) { showToast('Faltou item', 'Adicione ao menos um item.'); return; }

    let total = 0;
    const itensParaInserir = [];
    for (const l of linhas) {
      const produto = produtosCache.find(p => (p.produto_precos||[]).some(pp => pp.id === l.precoId));
      const preco = produto.produto_precos.find(pp => pp.id === l.precoId);
      total += preco.preco * l.qtd;
      itensParaInserir.push({ produto_id: produto.id, opcao_tamanho_id: preco.opcao_tamanho_id || null, quantidade: l.qtd, preco_unitario: preco.preco });
    }

    // Numeração diária: agora é automática (trigger no banco), não precisa mais
    // chamar a função manualmente aqui — funciona igual para pedidos vindos
    // do painel ou do App do Cliente.
    let trocoPara = null;
    if (forma === 'dinheiro' && trocoParaRaw) {
      trocoPara = parseFloat(trocoParaRaw);
      if (isNaN(trocoPara) || trocoPara < total) {
        showToast('Valor de troco inválido', 'O valor pra troco precisa ser maior ou igual ao total do pedido.');
        return;
      }
    }

    const { data: pedido, error: pedErr } = await sb.from('pedidos')
      .insert({
        restaurante_id: restauranteId, cliente_id: clienteId, tipo, forma_pagamento: forma,
        subtotal: total, total, status: 'recebido',
        endereco_entrega_id: enderecoId, troco_para: trocoPara
      })
      .select().single();
    if (pedErr) { showToast('Erro ao criar pedido', pedErr.message); return; }
    const numeroDiario = pedido.numero_diario;

    const itensFinal = itensParaInserir.map(i => ({ ...i, pedido_id: pedido.id }));
    const { error: itensErr } = await sb.from('itens_pedido').insert(itensFinal);
    if (itensErr) { showToast('Erro ao salvar itens', itensErr.message); return; }

    closeManualOrder();
    showToast('Pedido #' + numeroDiario + ' lançado', nome + ' · R$ ' + total.toFixed(2).replace('.', ','));
    await loadPedidos();
  }
