// /assets/js/pedido-manual.js
// Checkout do pedido manual. Depende das globais do painel: sb, restauranteId,
// restauranteInfo, currentUser, produtosCache, gruposTamanhoCache, clienteEncontradoAtual,
// enderecoEncontradoAtual, buscaTelefoneTimer, showToast, loadPedidos e
// pedidosCriadosManualmente.

  let pedidoManualItens = [];
  let pedidoManualEtapa = 1;
  let pedidoManualDescontoAtivo = false;
  let pedidoManualDescontoTipo = 'valor';
  let pedidoManualPrecisaTroco = false;
  let pedidoManualSubmetendo = false;
  let pedidoManualEquipe = [];
  let pedidoManualEquipeErro = null;
  let pedidoManualPedidoCriado = null;
  let pedidoManualCombinacao = null;

  function limparCombinacaoPedidoManual() {
    pedidoManualCombinacao = null;
    const bloco = document.getElementById('mSaboresBlock');
    if (bloco) bloco.classList.add('hidden');
    const opcoes = document.getElementById('mSaboresOpcoes');
    if (opcoes) opcoes.innerHTML = '';
  }

  function mostrarErroPedidoManual(titulo, mensagem) {
    const box = document.getElementById('mPedidoErro');
    box.textContent = `${titulo}: ${mensagem}`;
    box.classList.remove('hidden');
    showToast(titulo, mensagem);
  }

  function limparErroPedidoManual() {
    const box = document.getElementById('mPedidoErro');
    box.textContent = '';
    box.classList.add('hidden');
  }

  function erroFluxoPedidoManual(titulo, mensagem) {
    const erro = new Error(mensagem);
    erro.titulo = titulo;
    return erro;
  }

  async function openManualOrder() {
    pedidoManualItens = [];
    pedidoManualEtapa = 1;
    pedidoManualDescontoAtivo = false;
    pedidoManualDescontoTipo = 'valor';
    pedidoManualPrecisaTroco = false;
    pedidoManualSubmetendo = false;
    pedidoManualEquipe = [];
    pedidoManualEquipeErro = null;
    pedidoManualPedidoCriado = null;
    limparCombinacaoPedidoManual();
    clearTimeout(buscaTelefoneTimer);
    buscaTelefoneTimer = null;

    document.getElementById('mCliTel').value = '';
    document.getElementById('mCliNome').value = '';
    document.getElementById('mTipo').value = 'retirada';
    document.getElementById('mEndLogradouro').value = '';
    document.getElementById('mEndNumero').value = '';
    document.getElementById('mEndBairro').value = '';
    document.getElementById('mEndComplemento').value = '';
    document.getElementById('mEndReferencia').value = '';
    document.getElementById('mObservacoes').value = '';
    document.getElementById('mBuscaProduto').value = '';
    document.getElementById('mQtdAdicionar').value = '1';
    document.getElementById('mDescontoAtivo').checked = false;
    document.getElementById('mDescontoValor').value = '';
    document.getElementById('mDescontoMotivo').value = '';
    document.getElementById('mDescontoCampos').classList.add('hidden');
    document.getElementById('mDescontoEquipeErro').classList.add('hidden');
    document.getElementById('mDescontoAplicadoPor').textContent = currentUser?.nome || 'Usuário atual';
    document.getElementById('mTrocoPara').value = '';
    document.getElementById('mConfirmarBtn').disabled = false;
    document.getElementById('mConfirmarBtn').textContent = 'Confirmar e lançar pedido';

    limparErroPedidoManual();
    limparLookupCliente();
    onTipoManualChange();
    setTipoDescontoManual('valor');
    setFormaPagamentoManual('dinheiro');
    setNecessidadeTrocoManual(false);
    filtrarProdutosBusca();
    renderItensManualLista();
    irParaEtapaPedidoManual(1);
    document.getElementById('manualModalBg').classList.add('show');
    await carregarEquipeDescontoManual();
  }

  function closeManualOrder() {
    if (pedidoManualSubmetendo) return;
    limparCombinacaoPedidoManual();
    document.getElementById('manualModalBg').classList.remove('show');
  }

  function irParaEtapaPedidoManual(etapa) {
    pedidoManualEtapa = etapa === 2 ? 2 : 1;
    document.getElementById('mEtapaPedido').classList.toggle('hidden', pedidoManualEtapa !== 1);
    document.getElementById('mEtapaPagamento').classList.toggle('hidden', pedidoManualEtapa !== 2);
    document.getElementById('mEtapaIndicador1').classList.toggle('active', pedidoManualEtapa === 1);
    document.getElementById('mEtapaIndicador2').classList.toggle('active', pedidoManualEtapa === 2);
    document.querySelector('#manualModalBg .modal')?.scrollTo({ top: 0, behavior: 'smooth' });
    if (pedidoManualEtapa === 2) atualizarResumoFinanceiroManual();
  }

  function validarEtapaPedidoManual() {
    limparErroPedidoManual();
    const nome = document.getElementById('mCliNome').value.trim();
    const tipo = document.getElementById('mTipo').value;
    if (!nome) {
      mostrarErroPedidoManual('Faltou o nome', 'Informe o nome do cliente.');
      return false;
    }
    if (!['retirada', 'entrega'].includes(tipo)) {
      mostrarErroPedidoManual('Tipo inválido', 'Escolha entrega ou retirada.');
      return false;
    }
    if (pedidoManualItens.length === 0) {
      mostrarErroPedidoManual('Faltou item', 'Adicione ao menos um produto.');
      return false;
    }
    const itensInvalidos = pedidoManualItens.some(item =>
      !Number.isInteger(item.qtd) || item.qtd < 1 || !Number.isFinite(item.precoUnit) || item.precoUnit <= 0
    );
    if (itensInvalidos) {
      mostrarErroPedidoManual('Itens inválidos', 'Revise quantidades e preços dos produtos.');
      return false;
    }
    if (tipo === 'entrega') {
      const logradouro = document.getElementById('mEndLogradouro').value.trim();
      const numero = document.getElementById('mEndNumero').value.trim();
      const bairro = document.getElementById('mEndBairro').value.trim();
      if (!logradouro || !numero || !bairro) {
        mostrarErroPedidoManual('Endereço incompleto', 'Informe rua, número e bairro para a entrega.');
        return false;
      }
    }
    return true;
  }

  function continuarParaPagamentoManual() {
    if (!validarEtapaPedidoManual()) return;
    setFormaPagamentoManual('dinheiro');
    setNecessidadeTrocoManual(false);
    preencherResumoEtapaPagamentoManual();
    irParaEtapaPedidoManual(2);
  }

  function onTipoManualChange() {
    const isEntrega = document.getElementById('mTipo').value === 'entrega';
    document.getElementById('enderecoFields').classList.toggle('show', isEntrega);
    atualizarResumoFinanceiroManual();
  }

  function limparLookupCliente() {
    clienteEncontradoAtual = null;
    enderecoEncontradoAtual = null;
    const box = document.getElementById('clienteLookupBox');
    box.className = 'cliente-lookup-box';
    box.innerHTML = '';
  }

  function onTelefoneManualInput() {
    if (clienteEncontradoAtual) limparLookupCliente();
    clearTimeout(buscaTelefoneTimer);
    const tel = document.getElementById('mCliTel').value.trim();
    if (tel.length < 8) return;
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
        .select('id, logradouro, numero, bairro, complemento, referencia, padrao')
        .eq('cliente_id', cliente.id)
        .order('padrao', { ascending: false })
        .limit(1);

      if (enderecos?.length) {
        enderecoEncontradoAtual = enderecos[0];
        document.getElementById('mEndLogradouro').value = enderecos[0].logradouro || '';
        document.getElementById('mEndNumero').value = enderecos[0].numero || '';
        document.getElementById('mEndBairro').value = enderecos[0].bairro || '';
        document.getElementById('mEndComplemento').value = enderecos[0].complemento || '';
        document.getElementById('mEndReferencia').value = enderecos[0].referencia || '';
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
      box.innerHTML = '<b>Cliente novo</b>Será cadastrado automaticamente ao lançar o pedido.';
    }
  }

  function obterOpcoesProdutoFlat() {
    return produtosCache.flatMap(p => (p.produto_precos || []).filter(pp => pp.ativo).map(pp => ({
      precoId: pp.id,
      produtoId: p.id,
      grupoTamanhoId: p.grupo_tamanho_id || null,
      opcaoTamanhoId: pp.opcao_tamanho_id || null,
      nomeProduto: p.nome,
      nomeTamanho: pp.opcoes_tamanho ? pp.opcoes_tamanho.nome : null,
      precoNormal: Number(pp.preco),
      precoPromocional: Number(pp.preco_promocional),
      promocaoAtiva: precoPromocionalValidoManual(pp),
      preco: precoEfetivoManual(pp)
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
      ? filtradas.map(o => `<option value="${escapeHtml(o.precoId)}">${escapeHtml(o.nomeProduto)}${o.nomeTamanho ? ' - ' + escapeHtml(o.nomeTamanho) : ''} — ${o.promocaoAtiva ? `de ${formatMoeda(o.precoNormal)} por ${formatMoeda(o.preco)}` : formatMoeda(o.preco)}</option>`).join('')
      : '<option value="">Nenhum produto encontrado</option>';
    onProdutoManualChange();
  }

  function precoPromocionalValidoManual(pp) {
    const normal = Number(pp?.preco);
    const promocional = Number(pp?.preco_promocional);
    return pp?.promocao_ativa === true
      && Number.isFinite(promocional)
      && promocional > 0
      && promocional < normal;
  }

  function precoEfetivoManual(pp) {
    return precoPromocionalValidoManual(pp) ? Number(pp.preco_promocional) : Number(pp.preco);
  }

  function obterPrecoSaborManual(produto, opcaoTamanhoId) {
    const preco = (produto?.produto_precos || []).find(pp => pp.ativo && (pp.opcao_tamanho_id || null) === opcaoTamanhoId);
    const valor = precoEfetivoManual(preco);
    return preco && Number.isFinite(valor) && valor > 0 ? { ...preco, valor } : null;
  }

  function saboresDisponiveisPedidoManual(opcao) {
    if (!opcao?.grupoTamanhoId) return [];
    return produtosCache.filter(produto =>
      produto.grupo_tamanho_id === opcao.grupoTamanhoId
      && obterPrecoSaborManual(produto, opcao.opcaoTamanhoId)
    );
  }

  function precoCombinacaoPedidoManual() {
    if (!pedidoManualCombinacao?.saboresIds.length) return 0;
    const soma = pedidoManualCombinacao.saboresIds.reduce((total, produtoId) => {
      const produto = produtosCache.find(p => p.id === produtoId);
      return total + (obterPrecoSaborManual(produto, pedidoManualCombinacao.opcaoTamanhoId)?.valor || 0);
    }, 0);
    return arredondarMoedaManual(soma / pedidoManualCombinacao.saboresIds.length);
  }

  function renderSaboresPedidoManual() {
    const estado = pedidoManualCombinacao;
    const bloco = document.getElementById('mSaboresBlock');
    if (!estado || estado.maxSabores <= 1 || estado.disponiveis.length <= 1) {
      bloco.classList.add('hidden');
      return;
    }
    bloco.classList.remove('hidden');
    document.getElementById('mSaboresLabel').textContent = `Escolha até ${estado.maxSabores} sabores`;
    document.getElementById('mSaboresPreco').textContent = formatMoeda(precoCombinacaoPedidoManual());
    document.getElementById('mSaboresOpcoes').innerHTML = estado.disponiveis.map(produto => {
      const selecionado = estado.saboresIds.includes(produto.id);
      return `<button type="button" class="pm-sabor-opcao${selecionado ? ' selected' : ''}" aria-pressed="${selecionado}" onclick="toggleSaborPedidoManual('${escapeHtml(produto.id)}')">
        <span>${escapeHtml(produto.nome)}</span><b>${selecionado ? '✓' : '+'}</b>
      </button>`;
    }).join('');
  }

  function onProdutoManualChange() {
    const precoId = document.getElementById('mProdutoSelecionado').value;
    const opcao = obterOpcoesProdutoFlat().find(o => o.precoId === precoId);
    if (!opcao) { limparCombinacaoPedidoManual(); return; }
    const grupo = gruposTamanhoCache.find(g => g.id === opcao.grupoTamanhoId);
    const disponiveis = saboresDisponiveisPedidoManual(opcao);
    pedidoManualCombinacao = {
      precoId: opcao.precoId,
      produtoBaseId: opcao.produtoId,
      grupoTamanhoId: opcao.grupoTamanhoId,
      opcaoTamanhoId: opcao.opcaoTamanhoId,
      maxSabores: Math.max(1, parseInt(grupo?.max_sabores || '1', 10)),
      saboresIds: [opcao.produtoId],
      disponiveis
    };
    renderSaboresPedidoManual();
  }

  function toggleSaborPedidoManual(produtoId) {
    const estado = pedidoManualCombinacao;
    if (!estado || !estado.disponiveis.some(p => p.id === produtoId)) return;
    const indice = estado.saboresIds.indexOf(produtoId);
    if (indice >= 0) {
      if (estado.saboresIds.length === 1) {
        showToast('Mantenha um sabor', 'A pizza precisa ter pelo menos um sabor selecionado.');
        return;
      }
      estado.saboresIds.splice(indice, 1);
    } else {
      if (estado.saboresIds.length >= estado.maxSabores) {
        showToast('Limite de sabores', `Escolha no máximo ${estado.maxSabores} sabores para este tamanho.`);
        return;
      }
      estado.saboresIds.push(produtoId);
    }
    renderSaboresPedidoManual();
  }

  function adicionarItemManual() {
    const precoId = document.getElementById('mProdutoSelecionado').value;
    if (!precoId) { showToast('Selecione um produto', 'Pesquise e escolha um produto antes de adicionar.'); return; }
    const qtdInput = document.getElementById('mQtdAdicionar');
    const qtd = Number(qtdInput.value);
    if (!Number.isInteger(qtd) || qtd < 1) {
      showToast('Quantidade inválida', 'Use uma quantidade inteira maior que zero.');
      return;
    }
    const opcao = obterOpcoesProdutoFlat().find(o => o.precoId === precoId);
    if (!opcao || !Number.isFinite(opcao.preco) || opcao.preco <= 0) {
      showToast('Produto inválido', 'O produto selecionado não possui preço válido.');
      return;
    }
    const estado = pedidoManualCombinacao?.precoId === precoId ? pedidoManualCombinacao : null;
    const saboresIds = estado?.saboresIds.length ? [...estado.saboresIds] : [opcao.produtoId];
    const sabores = saboresIds.map(produtoId => {
      const produto = produtosCache.find(p => p.id === produtoId);
      const preco = obterPrecoSaborManual(produto, opcao.opcaoTamanhoId);
      return produto && preco ? { produtoId, nome: produto.nome, preco: preco.valor } : null;
    });
    if (sabores.some(sabor => !sabor)) {
      showToast('Sabores inválidos', 'Um dos sabores não possui preço válido para o tamanho escolhido.');
      return;
    }
    const precoUnit = arredondarMoedaManual(sabores.reduce((soma, sabor) => soma + sabor.preco, 0) / sabores.length);
    const chaveCombinacao = `${opcao.opcaoTamanhoId || 'sem-tamanho'}:${saboresIds.slice().sort().join(',')}`;
    const produtoPrincipalId = saboresIds.includes(opcao.produtoId) ? opcao.produtoId : saboresIds[0];
    const produtoPrincipal = sabores.find(sabor => sabor.produtoId === produtoPrincipalId);
    const nomeExibicao = sabores.map(sabor => sabor.nome).join(' + ');
    const existente = pedidoManualItens.find(i => i.chaveCombinacao === chaveCombinacao);
    if (existente) existente.qtd += qtd;
    else pedidoManualItens.push({
      uid: 'pm' + Date.now() + Math.random().toString(36).slice(2, 6),
      precoId: opcao.precoId,
      produtoId: produtoPrincipalId,
      opcaoTamanhoId: opcao.opcaoTamanhoId,
      nomeProduto: produtoPrincipal.nome,
      nomeExibicao,
      nomeTamanho: opcao.nomeTamanho,
      grupoTamanhoId: opcao.grupoTamanhoId,
      maxSabores: estado?.maxSabores || 1,
      sabores,
      saboresIds,
      saboresNomes: sabores.map(sabor => sabor.nome),
      chaveCombinacao,
      precoUnit,
      qtd
    });
    qtdInput.value = '1';
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

  function subtotalProdutosPedidoManual() {
    return Math.round(pedidoManualItens.reduce((s, i) => s + Number(i.precoUnit) * Number(i.qtd), 0) * 100) / 100;
  }

  function renderItensManualLista() {
    const wrap = document.getElementById('mItens');
    if (!pedidoManualItens.length) {
      wrap.innerHTML = '<p class="pm-itens-vazio">Nenhum item adicionado ainda. Pesquise um produto acima.</p>';
    } else {
      wrap.innerHTML = pedidoManualItens.map(item => {
        const uidArg = escapeHtml(JSON.stringify(item.uid));
        return `<div class="pm-item-row">
          <div class="pm-item-info">
            <p class="pm-item-nome">${escapeHtml(item.nomeExibicao || item.nomeProduto)}${item.nomeTamanho ? ` <span class="pm-item-tamanho">(${escapeHtml(item.nomeTamanho)})</span>` : ''}</p>
            <p class="pm-item-preco">${formatMoeda(item.precoUnit)} un.</p>
          </div>
          <div class="pm-item-qtd">
            <button type="button" onclick="alterarQtdItemManual(${uidArg}, -1)">−</button>
            <span>${item.qtd}</span>
            <button type="button" onclick="alterarQtdItemManual(${uidArg}, 1)">+</button>
          </div>
          <div class="pm-item-subtotal">${formatMoeda(item.precoUnit * item.qtd)}</div>
          <button type="button" class="pm-item-remover" onclick="removerItemManual(${uidArg})" title="Remover">🗑</button>
        </div>`;
      }).join('');
    }
    document.getElementById('mTotalPreview').textContent = formatMoeda(subtotalProdutosPedidoManual());
    atualizarResumoFinanceiroManual();
  }

  function taxaEntregaPreviewManual() {
    if (document.getElementById('mTipo').value !== 'entrega') return 0;
    const taxa = Number(restauranteInfo?.taxa_entrega_padrao);
    return Number.isFinite(taxa) && taxa > 0 ? Math.round(taxa * 100) / 100 : 0;
  }

  function parseDecimalManual(valor) {
    const texto = String(valor ?? '').trim();
    if (!/^\d+(?:[.,]\d{1,2})?$/.test(texto)) return null;
    const numero = Number(texto.replace(',', '.'));
    return Number.isFinite(numero) ? numero : null;
  }

  function arredondarMoedaManual(valor) {
    return Math.round((Number(valor) + Number.EPSILON) * 100) / 100;
  }

  function descontoPreviewManual() {
    if (!pedidoManualDescontoAtivo) return { valorInformado: 0, valorCalculado: 0, detalhe: '' };
    const valorInformado = parseDecimalManual(document.getElementById('mDescontoValor').value);
    const subtotal = subtotalProdutosPedidoManual();
    if (valorInformado === null || valorInformado <= 0) return { valorInformado: 0, valorCalculado: 0, detalhe: '' };
    if (pedidoManualDescontoTipo === 'percentual') {
      if (valorInformado > 100) return { valorInformado, valorCalculado: 0, detalhe: '' };
      const calculado = arredondarMoedaManual(subtotal * valorInformado / 100);
      return { valorInformado, valorCalculado: calculado, detalhe: `${String(valorInformado).replace('.', ',')}% = ${formatMoeda(calculado)}` };
    }
    if (valorInformado > subtotal) return { valorInformado, valorCalculado: 0, detalhe: '' };
    return { valorInformado, valorCalculado: arredondarMoedaManual(valorInformado), detalhe: '' };
  }

  function financeiroPreviewManual() {
    const subtotal = subtotalProdutosPedidoManual();
    const descontoInfo = descontoPreviewManual();
    const taxa = taxaEntregaPreviewManual();
    const total = Math.max(0, arredondarMoedaManual(subtotal - descontoInfo.valorCalculado + taxa));
    return { subtotal, desconto: descontoInfo.valorCalculado, descontoInfo, taxa, total };
  }

  function setDescontoAtivoManual(ativo) {
    pedidoManualDescontoAtivo = Boolean(ativo);
    document.getElementById('mDescontoAtivo').checked = pedidoManualDescontoAtivo;
    document.getElementById('mDescontoCampos').classList.toggle('hidden', !pedidoManualDescontoAtivo);
    if (!pedidoManualDescontoAtivo) {
      document.getElementById('mDescontoValor').value = '';
      document.getElementById('mDescontoMotivo').value = '';
      setTipoDescontoManual('valor');
    }
    atualizarResumoFinanceiroManual();
  }

  function setTipoDescontoManual(tipo) {
    pedidoManualDescontoTipo = tipo === 'percentual' ? 'percentual' : 'valor';
    document.querySelectorAll('.pm-segmentado [data-tipo]').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.tipo === pedidoManualDescontoTipo);
    });
    atualizarResumoFinanceiroManual();
  }

  async function carregarEquipeDescontoManual() {
    const select = document.getElementById('mDescontoAutorizadoPor');
    const erroEl = document.getElementById('mDescontoEquipeErro');
    select.disabled = true;
    select.innerHTML = '<option value="">Carregando equipe...</option>';
    erroEl.classList.add('hidden');
    pedidoManualEquipeErro = null;

    const { data, error } = await sb.from('usuarios')
      .select('id, nome, role')
      .eq('restaurante_id', restauranteId)
      .eq('ativo', true)
      .neq('role', 'motoboy')
      .order('nome');

    if (error) {
      pedidoManualEquipe = [];
      pedidoManualEquipeErro = error;
      select.innerHTML = '<option value="">Equipe indisponível</option>';
      erroEl.textContent = 'Não foi possível carregar a equipe. Desative o desconto para continuar.';
      erroEl.classList.remove('hidden');
      return;
    }

    pedidoManualEquipe = data || [];
    select.disabled = false;
    select.innerHTML = '<option value="">Selecione o autorizador</option>' + pedidoManualEquipe.map(usuario => {
      const cargo = String(usuario.role || '').replaceAll('_', ' ');
      const cargoLabel = cargo ? cargo.charAt(0).toUpperCase() + cargo.slice(1) : 'Equipe';
      return `<option value="${escapeHtml(usuario.id)}">${escapeHtml(usuario.nome)} — ${escapeHtml(cargoLabel)}</option>`;
    }).join('');
    if (currentUser?.id && pedidoManualEquipe.some(usuario => usuario.id === currentUser.id)) select.value = currentUser.id;
  }

  function setFormaPagamentoManual(forma) {
    const valor = ['dinheiro', 'pix', 'cartao'].includes(forma) ? forma : 'dinheiro';
    document.getElementById('mForma').value = valor;
    document.querySelectorAll('.pm-pagamento-opcoes [data-forma]').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.forma === valor);
    });
    const dinheiro = valor === 'dinheiro';
    document.getElementById('mCampoTroco').classList.toggle('hidden', !dinheiro);
    if (!dinheiro) setNecessidadeTrocoManual(false);
    atualizarResumoFinanceiroManual();
  }

  function onFormaPagamentoManualChange() {
    setFormaPagamentoManual(document.getElementById('mForma').value);
  }

  function setNecessidadeTrocoManual(precisa) {
    pedidoManualPrecisaTroco = Boolean(precisa) && document.getElementById('mForma').value === 'dinheiro';
    document.getElementById('mTrocoNaoBtn').classList.toggle('active', !pedidoManualPrecisaTroco);
    document.getElementById('mTrocoSimBtn').classList.toggle('active', pedidoManualPrecisaTroco);
    document.getElementById('mTrocoValorWrap').classList.toggle('hidden', !pedidoManualPrecisaTroco);
    if (!pedidoManualPrecisaTroco) document.getElementById('mTrocoPara').value = '';
    atualizarResumoFinanceiroManual();
  }

  function validarDescontoManual() {
    if (!pedidoManualDescontoAtivo) return { valido: true, ativo: false, tipo: null, valorInformado: null, valorCalculado: 0, motivo: null, autorizadoPor: null };
    if (pedidoManualEquipeErro) return { valido: false, titulo: 'Erro ao carregar equipe', mensagem: 'Desative o desconto ou tente abrir o pedido novamente.' };
    const valor = parseDecimalManual(document.getElementById('mDescontoValor').value);
    const subtotal = subtotalProdutosPedidoManual();
    if (valor === null || valor <= 0) return { valido: false, titulo: 'Desconto inválido', mensagem: 'Informe um desconto maior que zero, com até duas casas decimais.' };
    if (pedidoManualDescontoTipo === 'percentual' && valor > 100) return { valido: false, titulo: 'Desconto inválido', mensagem: 'O percentual não pode ultrapassar 100%.' };
    if (pedidoManualDescontoTipo === 'valor' && valor > subtotal) return { valido: false, titulo: 'Desconto inválido', mensagem: 'O desconto em valor não pode ultrapassar o subtotal.' };
    const motivo = document.getElementById('mDescontoMotivo').value.trim();
    if (!motivo) return { valido: false, titulo: 'Motivo obrigatório', mensagem: 'Informe o motivo do desconto.' };
    const autorizadoPor = document.getElementById('mDescontoAutorizadoPor').value;
    if (!autorizadoPor || !pedidoManualEquipe.some(usuario => usuario.id === autorizadoPor)) {
      return { valido: false, titulo: 'Autorizador inválido', mensagem: 'Selecione um integrante ativo da equipe para autorizar o desconto.' };
    }
    const valorCalculado = pedidoManualDescontoTipo === 'percentual'
      ? arredondarMoedaManual(subtotal * valor / 100)
      : arredondarMoedaManual(valor);
    if (!Number.isFinite(valorCalculado) || valorCalculado <= 0) {
      return {
        valido: false,
        titulo: 'Desconto inválido',
        mensagem: 'O percentual informado resulta em desconto de R$ 0,00. Aumente o percentual.'
      };
    }
    return { valido: true, ativo: true, tipo: pedidoManualDescontoTipo, valorInformado: valor, valorCalculado, motivo, autorizadoPor };
  }

  function validarTrocoManual(totalFinal) {
    if (document.getElementById('mForma').value !== 'dinheiro' || !pedidoManualPrecisaTroco) return { valido: true, valor: null, troco: null };
    const valor = parseDecimalManual(document.getElementById('mTrocoPara').value);
    if (valor === null || valor <= 0 || valor < totalFinal) {
      return { valido: false, titulo: 'Troco inválido', mensagem: 'Informe um valor para troco maior ou igual ao total final.' };
    }
    return { valido: true, valor, troco: arredondarMoedaManual(valor - totalFinal) };
  }

  function preencherResumoEtapaPagamentoManual() {
    const nome = document.getElementById('mCliNome').value.trim();
    const tipo = document.getElementById('mTipo').value;
    document.getElementById('mResumoCliente').textContent = nome;
    document.getElementById('mResumoTipo').textContent = tipo === 'entrega' ? 'Entrega' : 'Retirada';
    const enderecoLinha = document.getElementById('mResumoEnderecoLinha');
    if (tipo === 'entrega') {
      const endereco = [document.getElementById('mEndLogradouro').value.trim(), document.getElementById('mEndNumero').value.trim()].filter(Boolean).join(', ');
      const bairro = document.getElementById('mEndBairro').value.trim();
      document.getElementById('mResumoEndereco').textContent = `${endereco}${bairro ? ' — ' + bairro : ''}`;
      enderecoLinha.classList.remove('hidden');
    } else enderecoLinha.classList.add('hidden');

    document.getElementById('mResumoItens').innerHTML = pedidoManualItens.map(item => `
      <div class="pm-resumo-item"><span>${item.qtd}x ${escapeHtml(item.nomeExibicao || item.nomeProduto)}${item.nomeTamanho ? ` (${escapeHtml(item.nomeTamanho)})` : ''}<small>${formatMoeda(item.precoUnit)} un.</small></span><b>${formatMoeda(item.precoUnit * item.qtd)}</b></div>
    `).join('');
    atualizarResumoFinanceiroManual();
  }

  function atualizarResumoFinanceiroManual() {
    const financeiro = financeiroPreviewManual();
    const descontoLinha = document.getElementById('mResumoDescontoLinha');
    document.getElementById('mResumoSubtotal').textContent = formatMoeda(financeiro.subtotal);
    document.getElementById('mResumoTaxa').textContent = formatMoeda(financeiro.taxa);
    document.getElementById('mResumoTotal').textContent = formatMoeda(financeiro.total);
    descontoLinha.classList.toggle('hidden', financeiro.desconto <= 0);
    document.getElementById('mResumoDesconto').textContent = '- ' + formatMoeda(financeiro.desconto);
    document.getElementById('mResumoDescontoDetalhe').textContent = financeiro.descontoInfo.detalhe;

    const troco = validarTrocoManual(financeiro.total);
    const trocoPreview = document.getElementById('mTrocoPreview');
    if (troco.valido && troco.troco !== null) {
      trocoPreview.textContent = `Troco: ${formatMoeda(troco.troco)}`;
      trocoPreview.classList.remove('hidden');
    } else trocoPreview.classList.add('hidden');
    atualizarRevisaoFinalManual();
  }

  function atualizarRevisaoFinalManual() {
    const wrap = document.getElementById('mRevisaoFinal');
    if (!wrap) return;
    const financeiro = financeiroPreviewManual();
    const forma = document.getElementById('mForma')?.value || 'dinheiro';
    const formaLabel = { dinheiro: 'Dinheiro', pix: 'Pix', cartao: 'Cartão' }[forma];
    const qtdItens = pedidoManualItens.reduce((soma, item) => soma + item.qtd, 0);
    const troco = validarTrocoManual(financeiro.total);
    const linhas = [
      ['Cliente', document.getElementById('mCliNome')?.value.trim() || '—'],
      ['Tipo', document.getElementById('mTipo')?.value === 'entrega' ? 'Entrega' : 'Retirada'],
      ['Itens', String(qtdItens)],
      ['Pagamento', formaLabel],
      ['Subtotal', formatMoeda(financeiro.subtotal)],
      financeiro.desconto > 0 ? ['Desconto', '- ' + formatMoeda(financeiro.desconto)] : null,
      ['Taxa', formatMoeda(financeiro.taxa)],
      ['Total', formatMoeda(financeiro.total)],
      troco.valido && troco.troco !== null ? ['Troco', formatMoeda(troco.troco)] : null
    ].filter(Boolean);
    wrap.innerHTML = linhas.map(([label, valor]) => `<div class="pm-revisao-linha"><span>${label}</span><b>${escapeHtml(valor)}</b></div>`).join('');
  }

  function mensagemErroRpcDesconto(error) {
    const mensagem = error?.message || 'A RPC recusou a aplicação do desconto.';
    const texto = mensagem.toLowerCase();
    if (texto.includes('pago')) return { titulo: 'Pedido pago', mensagem };
    if (texto.includes('cancel')) return { titulo: 'Pedido cancelado', mensagem };
    if (texto.includes('autor')) return { titulo: 'Autorizador inválido', mensagem };
    return { titulo: 'Falha ao aplicar desconto', mensagem };
  }

  async function obterOuCriarClienteManual(nome, telefone) {
    if (clienteEncontradoAtual && clienteEncontradoAtual.telefone === telefone) {
      if (clienteEncontradoAtual.nome !== nome) {
        const { error } = await sb.from('clientes').update({ nome }).eq('id', clienteEncontradoAtual.id);
        if (error) throw erroFluxoPedidoManual('Falha ao criar cliente', error.message);
      }
      return clienteEncontradoAtual.id;
    }

    let clienteExistente = null;
    if (telefone) {
      const { data, error } = await sb.from('clientes').select('id, nome').eq('restaurante_id', restauranteId).eq('telefone', telefone).maybeSingle();
      if (error) throw erroFluxoPedidoManual('Falha ao criar cliente', error.message);
      clienteExistente = data;
    }
    if (clienteExistente) {
      if (clienteExistente.nome !== nome) {
        const { error } = await sb.from('clientes').update({ nome }).eq('id', clienteExistente.id);
        if (error) throw erroFluxoPedidoManual('Falha ao criar cliente', error.message);
      }
      return clienteExistente.id;
    }

    const { data: cliente, error } = await sb.from('clientes')
      .insert({ nome, telefone: telefone || null, restaurante_id: restauranteId, auth_user_id: null })
      .select('id').single();
    if (!error) return cliente.id;
    if (error.code === '23505' && telefone) {
      const { data: clienteCorrida } = await sb.from('clientes').select('id').eq('restaurante_id', restauranteId).eq('telefone', telefone).maybeSingle();
      if (clienteCorrida) return clienteCorrida.id;
    }
    throw erroFluxoPedidoManual('Falha ao criar cliente', error.message);
  }

  async function obterOuCriarEnderecoManual(clienteId, tipo) {
    if (tipo !== 'entrega') return null;
    const logradouro = document.getElementById('mEndLogradouro').value.trim();
    const numero = document.getElementById('mEndNumero').value.trim();
    const bairro = document.getElementById('mEndBairro').value.trim();
    const complemento = document.getElementById('mEndComplemento').value.trim();
    const referencia = document.getElementById('mEndReferencia').value.trim();
    const mesmoEndereco = enderecoEncontradoAtual
      && enderecoEncontradoAtual.logradouro === logradouro
      && (enderecoEncontradoAtual.numero || '') === numero
      && (enderecoEncontradoAtual.bairro || '') === bairro
      && (enderecoEncontradoAtual.complemento || '') === complemento
      && (enderecoEncontradoAtual.referencia || '') === referencia;
    if (mesmoEndereco) return enderecoEncontradoAtual.id;

    const { data, error } = await sb.from('enderecos_cliente')
      .insert({ cliente_id: clienteId, logradouro, numero, bairro, complemento: complemento || null, referencia: referencia || null })
      .select('id').single();
    if (error) throw erroFluxoPedidoManual('Falha ao salvar endereço', error.message);
    return data.id;
  }

  function montarItensParaInserirManual() {
    return pedidoManualItens.map(item => {
      if (!Number.isInteger(item.qtd) || item.qtd < 1 || !Array.isArray(item.saboresIds) || item.saboresIds.length < 1
        || new Set(item.saboresIds).size !== item.saboresIds.length || !item.saboresIds.includes(item.produtoId)) {
        throw erroFluxoPedidoManual('Itens inválidos', 'Revise a quantidade e os sabores dos itens antes de continuar.');
      }
      const produtoBase = produtosCache.find(p => p.id === item.produtoId);
      const grupo = item.grupoTamanhoId ? gruposTamanhoCache.find(g => g.id === item.grupoTamanhoId) : null;
      const maxSabores = item.grupoTamanhoId ? Number(grupo?.max_sabores) : 1;
      const precoBase = obterPrecoSaborManual(produtoBase, item.opcaoTamanhoId);
      if (!produtoBase || produtoBase.grupo_tamanho_id !== item.grupoTamanhoId || !precoBase
        || !Number.isInteger(maxSabores) || maxSabores < 1 || item.saboresIds.length > maxSabores) {
        throw erroFluxoPedidoManual('Itens indisponíveis', 'Um produto ou limite de sabores foi alterado. Remova o item e adicione novamente.');
      }
      const sabores = item.saboresIds.map(produtoId => {
        const produto = produtosCache.find(p => p.id === produtoId);
        const preco = obterPrecoSaborManual(produto, item.opcaoTamanhoId);
        if (!produto || produto.grupo_tamanho_id !== item.grupoTamanhoId || !preco) return null;
        return { produtoId, preco: preco.valor };
      });
      if (sabores.some(sabor => !sabor)) {
        throw erroFluxoPedidoManual('Itens indisponíveis', 'Um sabor não está mais disponível neste tamanho. Remova o item e adicione novamente.');
      }
      const precoMedio = arredondarMoedaManual(sabores.reduce((soma, sabor) => soma + sabor.preco, 0) / sabores.length);
      if (!Number.isFinite(precoMedio) || precoMedio <= 0 || precoMedio !== item.precoUnit) {
        throw erroFluxoPedidoManual('Preço atualizado', 'O preço de um sabor mudou. Remova o item e adicione novamente para revisar o total.');
      }
      return {
        produto_id: produtoBase.id,
        opcao_tamanho_id: item.opcaoTamanhoId || null,
        quantidade: item.qtd,
        preco_unitario: precoMedio,
        sabores_esperados: item.saboresIds.length,
        saboresIds: item.saboresIds
      };
    });
  }

  async function submitManualOrder() {
    if (pedidoManualSubmetendo) return;
    if (pedidoManualPedidoCriado) {
      mostrarErroPedidoManual('Pedido já criado', `O pedido #${pedidoManualPedidoCriado.numero_diario || pedidoManualPedidoCriado.id} já foi criado. Recarregue a lista antes de tentar novamente.`);
      await loadPedidos();
      return;
    }
    if (!validarEtapaPedidoManual()) { irParaEtapaPedidoManual(1); return; }

    const desconto = validarDescontoManual();
    if (!desconto.valido) { mostrarErroPedidoManual(desconto.titulo, desconto.mensagem); return; }
    const financeiro = financeiroPreviewManual();
    const troco = validarTrocoManual(financeiro.total);
    if (!troco.valido) { mostrarErroPedidoManual(troco.titulo, troco.mensagem); return; }

    const btn = document.getElementById('mConfirmarBtn');
    pedidoManualSubmetendo = true;
    btn.disabled = true;
    btn.textContent = 'Lançando pedido...';
    limparErroPedidoManual();

    let pedido = null;
    try {
      const nome = document.getElementById('mCliNome').value.trim();
      const telefone = document.getElementById('mCliTel').value.trim();
      const tipo = document.getElementById('mTipo').value;
      const forma = document.getElementById('mForma').value;
      const observacoes = document.getElementById('mObservacoes').value.trim();

      const clienteId = await obterOuCriarClienteManual(nome, telefone);
      const enderecoId = await obterOuCriarEnderecoManual(clienteId, tipo);
      const itensParaInserir = montarItensParaInserirManual();

      const { data, error: pedidoErro } = await sb.from('pedidos').insert({
        restaurante_id: restauranteId,
        cliente_id: clienteId,
        tipo,
        forma_pagamento: forma,
        status: 'recebido',
        endereco_entrega_id: enderecoId,
        troco_para: null,
        observacoes: observacoes || null
      }).select('id, numero_diario').single();
      if (pedidoErro) throw erroFluxoPedidoManual('Falha ao criar pedido', pedidoErro.message);

      pedido = data;
      pedidoManualPedidoCriado = pedido;
      pedidosCriadosManualmente.add(pedido.id);

      for (const item of itensParaInserir) {
        const { saboresIds, ...itemPedido } = item;
        const { data: itemInserido, error: itemErro } = await sb.from('itens_pedido')
          .insert({ ...itemPedido, pedido_id: pedido.id })
          .select('id').single();
        if (itemErro) throw erroFluxoPedidoManual('Falha ao salvar itens', itemErro.message);
        if (saboresIds.length > 1) {
          const saboresParaInserir = saboresIds.map(produtoId => ({
            item_pedido_id: itemInserido.id,
            produto_id: produtoId,
            preco_unitario: item.preco_unitario
          }));
          const { error: saboresErro } = await sb.from('itens_pedido_sabores').insert(saboresParaInserir);
          if (saboresErro) throw erroFluxoPedidoManual('Falha ao salvar sabores', saboresErro.message);
        }
      }

      let resultadoFinanceiro;
      if (desconto.ativo) {
        const { data: rpcData, error: rpcErro } = await sb.rpc('aplicar_desconto_manual', {
          p_pedido_id: pedido.id,
          p_tipo: desconto.tipo,
          p_valor: desconto.valorInformado,
          p_motivo: desconto.motivo,
          p_autorizado_por: desconto.autorizadoPor
        });
        if (rpcErro) {
          const detalhe = mensagemErroRpcDesconto(rpcErro);
          throw erroFluxoPedidoManual(detalhe.titulo, detalhe.mensagem);
        }
        resultadoFinanceiro = Array.isArray(rpcData) ? rpcData[0] : rpcData;
      } else {
        const { data: pedidoFinal, error: totalErro } = await sb.from('pedidos')
          .select('id, numero_diario, subtotal, taxa_entrega, total')
          .eq('id', pedido.id)
          .single();
        if (totalErro) throw erroFluxoPedidoManual('Falha ao recuperar total final', totalErro.message);
        resultadoFinanceiro = pedidoFinal;
      }

      let totalDefinitivo = Number(resultadoFinanceiro?.total);
      if (!Number.isFinite(totalDefinitivo)) {
        const { data: pedidoFinal, error: totalErro } = await sb.from('pedidos').select('total').eq('id', pedido.id).single();
        if (totalErro || !Number.isFinite(Number(pedidoFinal?.total))) {
          throw erroFluxoPedidoManual('Falha ao recuperar total final', totalErro?.message || 'O banco não retornou um total válido.');
        }
        totalDefinitivo = Number(pedidoFinal.total);
      }

      if (troco.valor !== null && troco.valor < totalDefinitivo) {
        throw erroFluxoPedidoManual(
          'Troco insuficiente para o total final',
          `O total definitivo do pedido é ${formatMoeda(totalDefinitivo)}, maior que o valor informado para troco (${formatMoeda(troco.valor)}).`
        );
      }

      if (troco.valor !== null) {
        const { data: pedidoComTroco, error: trocoErro } = await sb.from('pedidos')
          .update({ troco_para: troco.valor })
          .eq('id', pedido.id)
          .select('id, troco_para')
          .single();
        if (trocoErro) throw erroFluxoPedidoManual('Falha ao salvar troco', trocoErro.message);
        if (Number(pedidoComTroco?.troco_para) !== troco.valor) {
          throw erroFluxoPedidoManual('Falha ao confirmar troco', 'O banco não confirmou o valor informado para troco.');
        }
      }

      pedidoManualSubmetendo = false;
      document.getElementById('manualModalBg').classList.remove('show');
      pedidoManualItens = [];
      limparCombinacaoPedidoManual();
      showToast(`Pedido #${pedido.numero_diario || pedido.id} lançado`, `${nome} · ${formatMoeda(totalDefinitivo)}`);
      pedidoManualPedidoCriado = null;
      await loadPedidos();
    } catch (error) {
      const titulo = error.titulo || 'Erro ao lançar pedido';
      const prefixo = pedido ? `Pedido #${pedido.numero_diario || pedido.id} criado, mas a finalização falhou. ` : '';
      mostrarErroPedidoManual(titulo, prefixo + (error.message || 'Tente novamente.'));
      if (pedido) await loadPedidos();
    } finally {
      pedidoManualSubmetendo = false;
      btn.disabled = false;
      btn.textContent = 'Confirmar e lançar pedido';
    }
  }
