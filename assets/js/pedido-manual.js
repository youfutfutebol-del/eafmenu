// /assets/js/pedido-manual.js
// Logica do Pedido Manual (lancado pelo atendente/dono direto no painel), extraida do index.html (Etapa 12).
// Dependem de globais/funcoes do script principal: sb, restauranteId, produtosCache,
// clienteEncontradoAtual, enderecoEncontradoAtual, buscaTelefoneTimer, showToast (utils.js),
// loadPedidos() (pedidos.js). So chamadas apos o script principal rodar.
// Continuam globais (sem type=module).

  let pedidoManualItens = [];

  function openManualOrder() {
    document.getElementById('mCliTel').value = '';
    document.getElementById('mCliNome').value = '';
    document.getElementById('mTipo').value = 'retirada';
    document.getElementById('mEndLogradouro').value = '';
    document.getElementById('mEndNumero').value = '';
    document.getElementById('mEndBairro').value = '';
    document.getElementById('mEndComplemento').value = '';
    document.getElementById('mForma').value = 'dinheiro';
    document.getElementById('mTrocoPara').value = '';
    document.getElementById('mBuscaProduto').value = '';
    document.getElementById('mQtdAdicionar').value = 1;
    onFormaPagamentoManualChange();
    limparLookupCliente();
    onTipoManualChange();
    pedidoManualItens = [];
    filtrarProdutosBusca();
    renderItensManualLista();
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

  function obterOpcoesProdutoFlat() {
    return produtosCache.flatMap(p => (p.produto_precos || []).map(pp => ({
      precoId: pp.id,
      produtoId: p.id,
      opcaoTamanhoId: pp.opcao_tamanho_id || null,
      nomeProduto: p.nome,
      nomeTamanho: pp.opcoes_tamanho ? pp.opcoes_tamanho.nome : null,
      preco: Number(pp.preco)
    })));
  }

  function filtrarProdutosBusca() {
    const termo = document.getElementById('mBuscaProduto').value.trim().toLowerCase();
    const todas = obterOpcoesProdutoFlat();
    const filtradas = termo
      ? todas.filter(o => o.nomeProduto.toLowerCase().includes(termo) || (o.nomeTamanho || '').toLowerCase().includes(termo))
      : todas;
    const sel = document.getElementById('mProdutoSelecionado');
    sel.innerHTML = filtradas.length
      ? filtradas.map(o => `<option value="${o.precoId}">${o.nomeProduto}${o.nomeTamanho ? ' - ' + o.nomeTamanho : ''} (${formatMoeda(o.preco)})</option>`).join('')
      : '<option value="">Nenhum produto encontrado</option>';
  }

  function adicionarItemManual() {
    const precoId = document.getElementById('mProdutoSelecionado').value;
    if (!precoId) { showToast('Selecione um produto', 'Pesquise e escolha um produto antes de adicionar.'); return; }

    const qtdInput = document.getElementById('mQtdAdicionar');
    const qtd = Math.max(1, parseInt(qtdInput.value || '1', 10));

    const opcao = obterOpcoesProdutoFlat().find(o => o.precoId === precoId);
    if (!opcao) { showToast('Produto inválido', 'Tente pesquisar novamente.'); return; }

    // Mesma combinação produto+tamanho já está no carrinho: soma a quantidade em vez de duplicar linha.
    const existente = pedidoManualItens.find(i => i.precoId === precoId);
    if (existente) {
      existente.qtd += qtd;
    } else {
      pedidoManualItens.push({
        uid: 'pm' + Date.now() + Math.random().toString(36).slice(2, 6),
        precoId: opcao.precoId,
        produtoId: opcao.produtoId,
        opcaoTamanhoId: opcao.opcaoTamanhoId,
        nomeProduto: opcao.nomeProduto,
        nomeTamanho: opcao.nomeTamanho,
        precoUnit: opcao.preco,
        qtd
      });
    }

    qtdInput.value = 1;
    renderItensManualLista();
  }

  function removerItemManual(uid) {
    pedidoManualItens = pedidoManualItens.filter(i => i.uid !== uid);
    renderItensManualLista();
  }

  function alterarQtdItemManual(uid, delta) {
    const item = pedidoManualItens.find(i => i.uid === uid);
    if (!item) return;
    item.qtd = Math.max(1, item.qtd + delta);
    renderItensManualLista();
  }

  function renderItensManualLista() {
    const wrap = document.getElementById('mItens');
    if (pedidoManualItens.length === 0) {
      wrap.innerHTML = '<p class="pm-itens-vazio">Nenhum item adicionado ainda. Pesquise um produto acima.</p>';
    } else {
      wrap.innerHTML = pedidoManualItens.map(item => `
        <div class="pm-item-row">
          <div class="pm-item-info">
            <p class="pm-item-nome">${item.nomeProduto}${item.nomeTamanho ? ' <span class="pm-item-tamanho">(' + item.nomeTamanho + ')</span>' : ''}</p>
            <p class="pm-item-preco">${formatMoeda(item.precoUnit)} un.</p>
          </div>
          <div class="pm-item-qtd">
            <button type="button" onclick="alterarQtdItemManual('${item.uid}', -1)">−</button>
            <span>${item.qtd}</span>
            <button type="button" onclick="alterarQtdItemManual('${item.uid}', 1)">+</button>
          </div>
          <div class="pm-item-subtotal">${formatMoeda(item.precoUnit * item.qtd)}</div>
          <button type="button" class="pm-item-remover" onclick="removerItemManual('${item.uid}')" title="Remover">🗑</button>
        </div>`).join('');
    }
    atualizarTotalManualPreview();
  }

  function atualizarTotalManualPreview() {
    const total = pedidoManualItens.reduce((s, i) => s + i.precoUnit * i.qtd, 0);
    document.getElementById('mTotalPreview').textContent = formatMoeda(total);
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

    const linhas = pedidoManualItens.map(item => ({
      precoId: item.precoId,
      qtd: item.qtd
    }));

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

    pedidoManualItens = [];
    closeManualOrder();
    showToast('Pedido #' + numeroDiario + ' lançado', nome + ' · R$ ' + total.toFixed(2).replace('.', ','));
    await loadPedidos();
  }
