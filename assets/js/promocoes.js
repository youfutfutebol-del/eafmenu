// Administração de promoções. Não calcula descontos nem altera pedidos/checkout.
(function () {
  'use strict';

  let promocoesCache = [];
  let promoProdutos = [];
  let promoCategorias = [];
  let promoForm = novoEstadoForm();

  function novoEstadoForm() {
    return {
      condicao: { tipo: 'produto', categoriaId: '', itens: [{ produtoId: '', tamanhoId: '' }] },
      beneficio: { tipo: 'produto', categoriaId: '', itens: [{ produtoId: '', tamanhoId: '' }] },
      somenteLeitura: false
    };
  }

  const el = id => document.getElementById(id);
  const podeAdministrar = () => currentUser?.role === 'dono' || currentUser?.role === 'gerente';
  const tipoTelaParaBanco = tipo => tipo === 'lista' ? 'lista_produtos' : tipo;
  const tipoBancoParaTela = tipo => tipo === 'lista_produtos' ? 'lista' : tipo;
  const h = valor => String(valor ?? '').replace(/[&<>'"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[c]));
  const numero = (id, padrao = 0) => Number(el(id)?.value || padrao);
  const erroAmigavel = erro => {
    const msg = erro?.message || String(erro || 'Não foi possível concluir a operação.');
    if (/row-level security|permission denied|not allowed/i.test(msg)) return 'Seu perfil não tem permissão para realizar esta ação.';
    if (/duplicate|unique/i.test(msg)) return 'Já existe um item igual nesta promoção.';
    if (/foreign key/i.test(msg)) return 'Um produto, tamanho ou categoria selecionado não está mais disponível.';
    return msg;
  };

  async function carregarReferenciasPromocao() {
    const [produtosRes, gruposRes, categoriasRes] = await Promise.all([
      sb.from('produtos').select('id, nome, ativo, categoria_id, grupo_tamanho_id')
        .eq('restaurante_id', restauranteId).eq('ativo', true).order('nome'),
      sb.from('grupos_tamanho').select('id, ativo').eq('restaurante_id', restauranteId).eq('ativo', true),
      sb.from('categorias').select('id, nome').eq('restaurante_id', restauranteId).order('nome')
    ]);
    const erroFase1 = [produtosRes, gruposRes, categoriasRes].find(res => res.error)?.error;
    if (erroFase1) throw erroFase1;
    const produtos = produtosRes.data || [];
    const grupos = gruposRes.data || [];
    const produtoIds = produtos.map(produto => produto.id);
    const grupoIds = grupos.map(grupo => grupo.id);
    const [precosRes, opcoesRes] = await Promise.all([
      produtoIds.length
        ? sb.from('produto_precos').select('id, produto_id, ativo, opcao_tamanho_id').in('produto_id', produtoIds).eq('ativo', true)
        : Promise.resolve({ data: [], error: null }),
      grupoIds.length
        ? sb.from('opcoes_tamanho').select('id, nome, grupo_id, ativo').in('grupo_id', grupoIds).eq('ativo', true)
        : Promise.resolve({ data: [], error: null })
    ]);
    const erroFase2 = [precosRes, opcoesRes].find(res => res.error)?.error;
    if (erroFase2) throw erroFase2;
    const gruposAtivos = new Set((gruposRes.data || []).map(g => String(g.id)));
    const opcoesAtivas = new Map((opcoesRes.data || []).map(o => [String(o.id), o]));
    promoProdutos = produtos.map(produto => {
      const grupoId = produto.grupo_tamanho_id ? String(produto.grupo_tamanho_id) : '';
      if (grupoId && !gruposAtivos.has(grupoId)) return null;
      const produtoPrecos = (precosRes.data || []).filter(preco => {
        if (String(preco.produto_id) !== String(produto.id) || !preco.ativo) return false;
        if (!grupoId) return !preco.opcao_tamanho_id;
        const opcao = opcoesAtivas.get(String(preco.opcao_tamanho_id));
        return Boolean(opcao?.ativo && String(opcao.grupo_id) === grupoId);
      }).map(preco => ({ ...preco, opcoes_tamanho: preco.opcao_tamanho_id ? opcoesAtivas.get(String(preco.opcao_tamanho_id)) : null }));
      return { ...produto, produto_precos: produtoPrecos };
    }).filter(produto => produto?.produto_precos.length);
    promoCategorias = categoriasRes.data || [];
  }

  async function loadPromocoes() {
    const tbody = el('promocoesTableBody');
    if (!tbody || !restauranteId) return;
    el('novaPromocaoBtn').style.display = podeAdministrar() ? '' : 'none';
    tbody.innerHTML = '<tr><td colspan="6"><div class="empty-state"><h4>Carregando promoções...</h4></div></td></tr>';
    try {
      await carregarReferenciasPromocao();
    } catch (erro) {
      tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state"><h4>Não foi possível carregar produtos e categorias</h4><p>${h(erroAmigavel(erro))}</p></div></td></tr>`;
      return;
    }
    const { data, error } = await sb.from('promocoes')
      .select('id, restaurante_id, nome, ativo, arquivado_em, condicao_quantidade, beneficio_quantidade, beneficio_percentual, beneficio_modo, max_aplicacoes_por_pedido, criado_por, criado_em')
      .eq('restaurante_id', restauranteId);
    if (error) {
      tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state"><h4>Não foi possível carregar as promoções</h4><p>${h(erroAmigavel(error))}</p></div></td></tr>`;
      return;
    }
    promocoesCache = data || [];
    const promocaoIds = promocoesCache.map(p => p.id);
    if (promocaoIds.length) {
      const escoposRes = await sb.from('promocao_escopos')
        .select('id, promocao_id, restaurante_id, papel, tipo')
        .eq('restaurante_id', restauranteId).in('promocao_id', promocaoIds);
      if (escoposRes.error) {
        tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state"><h4>Não foi possível carregar os detalhes das promoções</h4><p>${h(erroAmigavel(escoposRes.error))}</p></div></td></tr>`;
        return;
      }
      const escoposCarregados = escoposRes.data || [];
      const escopoIds = escoposCarregados.map(e => e.id);
      let itensCarregados = [];
      if (escopoIds.length) {
        const itensRes = await sb.from('promocao_escopo_itens')
          .select('id, promocao_escopo_id, restaurante_id, produto_id, categoria_id, opcao_tamanho_id')
          .eq('restaurante_id', restauranteId).in('promocao_escopo_id', escopoIds);
        if (itensRes.error) {
          tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state"><h4>Não foi possível carregar os itens das promoções</h4><p>${h(erroAmigavel(itensRes.error))}</p></div></td></tr>`;
          return;
        }
        itensCarregados = itensRes.data || [];
      }
      escoposCarregados.forEach(escopo => { escopo.promocao_escopo_itens = itensCarregados.filter(i => String(i.promocao_escopo_id) === String(escopo.id)); });
      promocoesCache.forEach(promo => { promo.promocao_escopos = escoposCarregados.filter(e => String(e.promocao_id) === String(promo.id)); });
    }
    renderPromocoes();
  }

  function escopos(promo) { return promo.promocao_escopos || []; }
  function papelEscopo(e) { return e.papel; }
  function tipoEscopo(e) { return tipoBancoParaTela(e?.tipo || 'produto'); }
  function itensEscopo(e) { return e?.promocao_escopo_itens || []; }
  function encontrarEscopo(promo, papel) { return escopos(promo).find(e => papelEscopo(e) === papel); }
  function produtoPorId(id) { return promoProdutos.find(p => String(p.id) === String(id)); }
  function categoriaPorId(id) { return promoCategorias.find(c => String(c.id) === String(id)); }
  function tamanhoNome(produto, tamanhoId) {
    if (!tamanhoId) return '';
    const preco = (produto?.produto_precos || []).find(p => String(p.opcao_tamanho_id) === String(tamanhoId));
    return preco?.opcoes_tamanho?.nome || '';
  }

  function escopoCompleto(e) {
    if (!e) return false;
    if (tipoEscopo(e) === 'categoria') return itensEscopo(e).some(i => i.categoria_id);
    return itensEscopo(e).length > 0;
  }

  function statusPromo(p) {
    if (p.arquivado_em) return { chave: 'arquivada', nome: 'Arquivada' };
    if (p.ativo) return { chave: 'ativa', nome: 'Ativa' };
    const completa = Number(p.condicao_quantidade) > 0 && Number(p.beneficio_quantidade) > 0 && Number(p.beneficio_percentual) > 0
      && escopoCompleto(encontrarEscopo(p, 'condicao')) && escopoCompleto(encontrarEscopo(p, 'beneficio'));
    if (!completa) return { chave: escopos(p).length ? 'incompleta' : 'rascunho', nome: escopos(p).length ? 'Incompleta' : 'Rascunho' };
    return { chave: 'inativa', nome: 'Inativa' };
  }

  function resumoEscopo(e, quantidade, prefixo) {
    if (!e) return `${prefixo} ${quantidade || '?'} item(ns) — configuração incompleta`;
    if (tipoEscopo(e) === 'categoria') return `${prefixo} ${quantidade} produto(s) da categoria ${categoriaPorId(itensEscopo(e)[0]?.categoria_id)?.nome || 'selecionada'}`;
    const nomes = itensEscopo(e).map(i => {
      const produto = produtoPorId(i.produto_id);
      const tam = tamanhoNome(produto, i.opcao_tamanho_id);
      return `${produto?.nome || 'Produto'}${tam ? ` ${tam}` : ''}`;
    });
    if (tipoEscopo(e) === 'produto') return `${prefixo} ${quantidade} ${nomes[0] || 'produto'}`;
    return `${prefixo} ${quantidade} item(ns) entre ${nomes.slice(0, 2).join(', ')}${nomes.length > 2 ? ` e mais ${nomes.length - 2}` : ''}`;
  }

  function resumoBeneficio(p) {
    const e = encontrarEscopo(p, 'beneficio');
    const qtd = Number(p.beneficio_quantidade) || '?';
    const pct = Number(p.beneficio_percentual);
    const desconto = pct === 100 ? 'grátis' : `com ${pct}% de desconto`;
    if (p.beneficio_modo === 'escolha_cliente') {
      if (tipoEscopo(e) === 'categoria') return `Escolha ${qtd} produto${qtd === 1 ? '' : 's'} da categoria ${categoriaPorId(itensEscopo(e)[0]?.categoria_id)?.nome || 'selecionada'} ${desconto}`;
      const nomes = itensEscopo(e).map(item => {
        const produto = produtoPorId(item.produto_id);
        const tamanho = tamanhoNome(produto, item.opcao_tamanho_id);
        return `${produto?.nome || 'Produto'}${tamanho ? ` ${tamanho}` : ''}`;
      });
      return `Escolha ${qtd} item${qtd === 1 ? '' : 's'} entre ${nomes.join(' e ') || 'as opções'} ${desconto}`;
    }
    if (p.beneficio_modo === 'menor_preco_elegivel') return `Aplique em ${qtd} item(ns) elegível(is) de menor preço ${desconto}`;
    return `${resumoEscopo(e, qtd, 'Ganhe')} ${desconto}`;
  }

  function renderPromocoes() {
    const tbody = el('promocoesTableBody');
    if (!promocoesCache.length) {
      tbody.innerHTML = '<tr><td colspan="6"><div class="empty-state"><div class="ic">🎁</div><h4>Nenhuma promoção cadastrada</h4><p>Crie sua primeira campanha para incentivar novas compras.</p></div></td></tr>';
      return;
    }
    tbody.innerHTML = promocoesCache.map(p => {
      const status = statusPromo(p);
      const leitura = `<button onclick="openPromocao('${p.id}', true)">Ver detalhes</button>`;
      let acoes = leitura;
      if (podeAdministrar() && !p.arquivado_em) {
        if (!p.ativo) acoes += `<button onclick="openPromocao('${p.id}')">Editar</button><button onclick="acaoPromocao('ativar', '${p.id}')">Ativar</button>`;
        else acoes += `<button onclick="acaoPromocao('desativar', '${p.id}')">Desativar</button>`;
        acoes += `<button class="danger" onclick="acaoPromocao('arquivar', '${p.id}')">Arquivar</button>`;
      }
      return `<tr><td data-label="Nome"><b>${h(p.nome)}</b></td><td data-label="Condição">${h(resumoEscopo(encontrarEscopo(p, 'condicao'), p.condicao_quantidade, 'Compre'))}</td><td data-label="Benefício">${h(resumoBeneficio(p))}</td><td data-label="Status"><span class="promo-status promo-status--${status.chave}">${status.nome}</span></td><td data-label="Limite/pedido">${p.max_aplicacoes_por_pedido || 'Sem limite'}</td><td data-label="Ações"><div class="row-actions">${acoes}</div></td></tr>`;
    }).join('');
  }

  function opcoesProduto(selecionado) {
    return '<option value="">Selecione um produto</option>' + promoProdutos.map(p => `<option value="${h(p.id)}" ${String(p.id) === String(selecionado) ? 'selected' : ''}>${h(p.nome)}</option>`).join('');
  }
  function opcoesTamanho(produtoId, selecionado) {
    const produto = produtoPorId(produtoId);
    const tamanhos = [...new Map((produto?.produto_precos || []).filter(p => p.opcao_tamanho_id).map(p => [String(p.opcao_tamanho_id), p.opcoes_tamanho?.nome])).entries()];
    return '<option value="">Qualquer tamanho</option>' + tamanhos.map(([id, nome]) => `<option value="${h(id)}" ${String(id) === String(selecionado) ? 'selected' : ''}>${h(nome)}</option>`).join('');
  }

  function renderEscopo(papel) {
    const estado = promoForm[papel];
    const wrap = el(papel === 'condicao' ? 'promoCondicaoCampos' : 'promoBeneficioCampos');
    if (!wrap) return;
    if (estado.tipo === 'categoria') {
      wrap.innerHTML = `<div class="field"><label>Categoria</label><select ${promoForm.somenteLeitura ? 'disabled' : ''} onchange="setPromoCategoria('${papel}', this.value)"><option value="">Selecione uma categoria</option>${promoCategorias.map(c => `<option value="${h(c.id)}" ${String(c.id) === String(estado.categoriaId) ? 'selected' : ''}>${h(c.nome)}</option>`).join('')}</select></div>`;
      return;
    }
    wrap.innerHTML = estado.itens.map((item, indice) => `<div class="promo-item-row"><div class="field"><label>${estado.tipo === 'lista' ? `Produto ${indice + 1}` : 'Produto'}</label><select ${promoForm.somenteLeitura ? 'disabled' : ''} onchange="setPromoItem('${papel}', ${indice}, 'produtoId', this.value)">${opcoesProduto(item.produtoId)}</select></div><div class="field"><label>Tamanho</label><select ${promoForm.somenteLeitura ? 'disabled' : ''} onchange="setPromoItem('${papel}', ${indice}, 'tamanhoId', this.value)">${opcoesTamanho(item.produtoId, item.tamanhoId)}</select></div>${estado.tipo === 'lista' && !promoForm.somenteLeitura ? `<button class="promo-remove-item" type="button" onclick="removerPromoItem('${papel}', ${indice})">Remover</button>` : '<span></span>'}</div>`).join('')
      + (estado.tipo === 'lista' && !promoForm.somenteLeitura ? `<button class="promo-add-item" type="button" onclick="adicionarPromoItem('${papel}')">+ Adicionar produto</button>` : '');
  }

  function renderPromocaoEscopos() {
    promoForm.condicao.tipo = el('promoCondicaoTipo').value;
    promoForm.beneficio.tipo = el('promoBeneficioTipo').value;
    renderEscopo('condicao'); renderEscopo('beneficio'); atualizarPreviewPromocao();
  }
  function setPromoCategoria(papel, valor) { promoForm[papel].categoriaId = valor; atualizarPreviewPromocao(); }
  function setPromoItem(papel, indice, campo, valor) {
    promoForm[papel].itens[indice][campo] = valor;
    if (campo === 'produtoId') { promoForm[papel].itens[indice].tamanhoId = ''; renderEscopo(papel); }
    atualizarPreviewPromocao();
  }
  function adicionarPromoItem(papel) { promoForm[papel].itens.push({ produtoId: '', tamanhoId: '' }); renderEscopo(papel); }
  function removerPromoItem(papel, indice) { promoForm[papel].itens.splice(indice, 1); if (!promoForm[papel].itens.length) adicionarPromoItem(papel); else renderEscopo(papel); atualizarPreviewPromocao(); }

  function onPromocaoModoChange() {
    const modo = el('promoBeneficioModo').value;
    const tipo = el('promoBeneficioTipo');
    [...tipo.options].forEach(o => { o.disabled = modo === 'produto_fixo' ? o.value !== 'produto' : modo === 'escolha_cliente' ? o.value === 'produto' : false; });
    if (modo === 'produto_fixo') tipo.value = 'produto';
    if (modo === 'escolha_cliente' && tipo.value === 'produto') tipo.value = 'lista';
    renderPromocaoEscopos();
  }

  function copiarCondicaoParaBeneficio() {
    promoForm.beneficio = {
      tipo: promoForm.condicao.tipo,
      categoriaId: promoForm.condicao.categoriaId,
      itens: promoForm.condicao.itens.map(item => ({ produtoId: item.produtoId, tamanhoId: item.tamanhoId }))
    };
    el('promoBeneficioTipo').value = promoForm.beneficio.tipo;
    renderEscopo('beneficio');
  }
  function aplicarAtalhoLevePague() { el('promoAtalhoCampos').hidden = false; el('promoBeneficioModo').value = 'menor_preco_elegivel'; atualizarAtalhoLevePague(); }
  function atualizarAtalhoLevePague() {
    const x = numero('promoLeveX', 3), y = numero('promoPagueY', 2);
    if (x > y && y > 0) { el('promoCondicaoQtd').value = x; el('promoBeneficioQtd').value = x - y; el('promoPercentual').value = 100; el('promoBeneficioModo').value = 'menor_preco_elegivel'; }
    copiarCondicaoParaBeneficio(); onPromocaoModoChange(); atualizarPreviewPromocao();
  }

  function resumoEstado(estado, qtd, prefixo) {
    if (estado.tipo === 'categoria') return `${prefixo} ${qtd} produto(s) da categoria ${categoriaPorId(estado.categoriaId)?.nome || 'selecionada'}`;
    const nomes = estado.itens.filter(i => i.produtoId).map(i => { const p = produtoPorId(i.produtoId); const t = tamanhoNome(p, i.tamanhoId); return `${p?.nome || 'produto'}${t ? ` ${t}` : ''}`; });
    return `${prefixo} ${qtd} ${estado.tipo === 'lista' ? `item(ns) entre ${nomes.join(', ') || 'a lista'}` : nomes[0] || 'produto'}`;
  }
  function atualizarPreviewPromocao() {
    const cond = resumoEstado(promoForm.condicao, numero('promoCondicaoQtd', 2), 'Compre');
    const ben = resumoEstado(promoForm.beneficio, numero('promoBeneficioQtd', 1), 'receba');
    const pct = numero('promoPercentual', 100);
    el('promoResumoPreview').textContent = `${cond}; ${ben} ${pct === 100 ? 'grátis' : `com ${pct}% de desconto`}.`;
  }

  function estadoDoEscopo(e) {
    if (!e) return { tipo: 'produto', categoriaId: '', itens: [{ produtoId: '', tamanhoId: '' }] };
    return { tipo: tipoEscopo(e), categoriaId: itensEscopo(e)[0]?.categoria_id || '', itens: (itensEscopo(e).length ? itensEscopo(e) : [{}]).map(i => ({ produtoId: i.produto_id || '', tamanhoId: i.opcao_tamanho_id || '' })) };
  }

  async function openPromocao(id, somenteLeitura = false) {
    const existente = id ? promocoesCache.find(p => String(p.id) === String(id)) : null;
    if (existente?.ativo && !somenteLeitura) { showToast('Desative primeiro', 'Uma promoção ativa não pode ser editada.'); return; }
    if (existente?.arquivado_em && !somenteLeitura) { showToast('Somente visualização', 'Uma promoção arquivada não pode ser editada ou reativada.'); return; }
    if (!podeAdministrar() && !somenteLeitura) return;
    try { await carregarReferenciasPromocao(); } catch (erro) { showToast('Erro ao carregar opções', erroAmigavel(erro)); return; }
    promoForm = novoEstadoForm();
    promoForm.somenteLeitura = somenteLeitura || !podeAdministrar() || Boolean(existente?.ativo || existente?.arquivado_em);
    el('promoId').value = existente?.id || '';
    el('promoNome').value = existente?.nome || '';
    el('promoCondicaoQtd').value = existente?.condicao_quantidade || 2;
    el('promoBeneficioQtd').value = existente?.beneficio_quantidade || 1;
    el('promoPercentual').value = existente?.beneficio_percentual || 100;
    el('promoLimite').value = existente?.max_aplicacoes_por_pedido || '';
    el('promoBeneficioModo').value = existente?.beneficio_modo || 'produto_fixo';
    if (existente) { promoForm.condicao = estadoDoEscopo(encontrarEscopo(existente, 'condicao')); promoForm.beneficio = estadoDoEscopo(encontrarEscopo(existente, 'beneficio')); }
    el('promoCondicaoTipo').value = promoForm.condicao.tipo;
    el('promoBeneficioTipo').value = promoForm.beneficio.tipo;
    el('promocaoModalTitle').textContent = promoForm.somenteLeitura ? 'Detalhes da promoção' : existente ? 'Editar promoção' : 'Nova promoção';
    el('promocaoModalHint').textContent = promoForm.somenteLeitura ? 'Visualização somente leitura.' : 'A promoção será salva inicialmente como rascunho inativo.';
    el('salvarPromocaoBtn').style.display = promoForm.somenteLeitura ? 'none' : '';
    ['promoNome','promoCondicaoQtd','promoBeneficioQtd','promoPercentual','promoLimite','promoCondicaoTipo','promoBeneficioModo','promoBeneficioTipo'].forEach(i => { el(i).disabled = promoForm.somenteLeitura; });
    document.querySelector('.promo-shortcut').style.display = promoForm.somenteLeitura ? 'none' : '';
    el('promoAtalhoCampos').hidden = true; mostrarErroForm(''); onPromocaoModoChange();
    el('promocaoModalBg').classList.add('show');
  }
  function closePromocao() { el('promocaoModalBg').classList.remove('show'); }
  function mostrarErroForm(msg) { el('promoFormError').textContent = msg; el('promoFormError').classList.toggle('show', Boolean(msg)); }

  function validarEscopo(papel) {
    const e = promoForm[papel];
    if (e.tipo === 'categoria') return e.categoriaId ? '' : `Selecione a categoria do ${papel === 'condicao' ? 'critério' : 'benefício'}.`;
    if (!e.itens.length || e.itens.some(i => !i.produtoId)) return 'Selecione todos os produtos.';
    const chaves = e.itens.map(i => `${i.produtoId}:${i.tamanhoId || '*'}`);
    if (new Set(chaves).size !== chaves.length) return 'Não repita o mesmo produto e tamanho.';
    for (const item of e.itens) {
      const doProduto = e.itens.filter(i => i.produtoId === item.produtoId);
      if (doProduto.some(i => !i.tamanhoId) && doProduto.some(i => i.tamanhoId)) return 'Não use “qualquer tamanho” junto com um tamanho específico do mesmo produto.';
    }
    return '';
  }

  function validarPromocao() {
    if (!el('promoNome').value.trim()) return 'Informe o nome da promoção.';
    if (numero('promoCondicaoQtd') < 1 || numero('promoBeneficioQtd') < 1) return 'As quantidades devem ser maiores que zero.';
    if (numero('promoPercentual') < 1 || numero('promoPercentual') > 100) return 'O desconto deve ficar entre 1% e 100%.';
    const modo = el('promoBeneficioModo').value;
    if (modo === 'produto_fixo' && promoForm.beneficio.tipo !== 'produto') return 'No produto definido pelo restaurante, o benefício deve ser um produto.';
    if (modo === 'escolha_cliente' && promoForm.beneficio.tipo === 'produto') return 'Na escolha do cliente, use uma lista ou categoria.';
    if (modo === 'produto_fixo') {
      const item = promoForm.beneficio.itens[0], produto = produtoPorId(item?.produtoId);
      const combinacoes = new Set((produto?.produto_precos || []).map(p => p.opcao_tamanho_id || '__unico'));
      if (combinacoes.size > 1 && !item?.tamanhoId) return 'Escolha um tamanho específico para o produto do benefício.';
    }
    if (modo === 'menor_preco_elegivel') {
      const elegibilidadeErro = validarMenorPrecoElegivel();
      if (elegibilidadeErro) return elegibilidadeErro;
    }
    return validarEscopo('condicao') || validarEscopo('beneficio');
  }

  function validarMenorPrecoElegivel() {
    const condicao = promoForm.condicao;
    const beneficio = promoForm.beneficio;
    if (condicao.tipo === 'categoria') {
      if (beneficio.tipo === 'categoria') {
        return condicao.categoriaId === beneficio.categoriaId ? '' : 'No menor preço elegível, condição e benefício devem usar a mesma categoria.';
      }
      const foraDaCategoria = beneficio.itens.some(item => produtoPorId(item.produtoId)?.categoria_id !== condicao.categoriaId);
      return foraDaCategoria ? 'Todos os produtos do benefício devem pertencer à categoria da condição.' : '';
    }
    if (beneficio.tipo === 'categoria') return 'Um benefício por categoria exige que a condição use a mesma categoria.';
    for (const itemBeneficio of beneficio.itens) {
      const candidatos = condicao.itens.filter(item => String(item.produtoId) === String(itemBeneficio.produtoId));
      if (!candidatos.length) return 'Todos os produtos do benefício devem também existir na condição.';
      if (candidatos.some(item => !item.tamanhoId)) continue;
      if (!itemBeneficio.tamanhoId) return '“Qualquer tamanho” no benefício exige “qualquer tamanho” para esse produto na condição.';
      if (!candidatos.some(item => String(item.tamanhoId) === String(itemBeneficio.tamanhoId))) return 'O tamanho do benefício deve estar entre os tamanhos permitidos na condição.';
    }
    return '';
  }

  function payloadGeral(incluirCriador = false) {
    const payload = { restaurante_id: restauranteId, nome: el('promoNome').value.trim(), condicao_quantidade: numero('promoCondicaoQtd'), beneficio_quantidade: numero('promoBeneficioQtd'), beneficio_percentual: numero('promoPercentual'), beneficio_modo: el('promoBeneficioModo').value, max_aplicacoes_por_pedido: el('promoLimite').value ? numero('promoLimite') : null, ativo: false };
    if (incluirCriador) payload.criado_por = currentUser.id;
    return payload;
  }
  async function criarEscopo(promocaoId, papel, estado) {
    const { data, error } = await sb.from('promocao_escopos').insert({ promocao_id: promocaoId, restaurante_id: restauranteId, papel, tipo: tipoTelaParaBanco(estado.tipo) }).select('id').single();
    if (error) throw error;
    const itens = estado.tipo === 'categoria'
      ? [{ promocao_escopo_id: data.id, restaurante_id: restauranteId, produto_id: null, categoria_id: estado.categoriaId, opcao_tamanho_id: null }]
      : estado.itens.map(i => ({ promocao_escopo_id: data.id, restaurante_id: restauranteId, produto_id: i.produtoId, categoria_id: null, opcao_tamanho_id: i.tamanhoId || null }));
    const itensRes = await sb.from('promocao_escopo_itens').insert(itens);
    if (itensRes.error) throw itensRes.error;
  }

  async function submitPromocao() {
    if (!podeAdministrar() || promoForm.somenteLeitura) return;
    const validacao = validarPromocao(); if (validacao) { mostrarErroForm(validacao); return; }
    mostrarErroForm(''); const btn = el('salvarPromocaoBtn'); btn.disabled = true; btn.textContent = 'Salvando...';
    let promocaoId = el('promoId').value;
    try {
      if (promocaoId) {
        const atual = promocoesCache.find(p => String(p.id) === String(promocaoId));
        if (atual?.ativo || atual?.arquivado_em) throw new Error('Esta promoção não pode mais ser editada. Recarregue a lista.');
        const upd = await sb.from('promocoes').update(payloadGeral()).eq('id', promocaoId).eq('restaurante_id', restauranteId); if (upd.error) throw upd.error;
        const ids = escopos(atual).map(e => e.id).filter(Boolean);
        for (const idDoEscopo of ids) {
          const delItens = await sb.from('promocao_escopo_itens').delete().eq('promocao_escopo_id', idDoEscopo).eq('restaurante_id', restauranteId);
          if (delItens.error) throw delItens.error;
        }
        const delEscopos = await sb.from('promocao_escopos').delete().eq('promocao_id', promocaoId).eq('restaurante_id', restauranteId); if (delEscopos.error) throw delEscopos.error;
      } else {
        const ins = await sb.from('promocoes').insert(payloadGeral(true)).select('id').single(); if (ins.error) throw ins.error; promocaoId = ins.data.id; el('promoId').value = promocaoId;
      }
      await criarEscopo(promocaoId, 'condicao', promoForm.condicao);
      await criarEscopo(promocaoId, 'beneficio', promoForm.beneficio);
      closePromocao(); showToast('Promoção salva', 'A campanha foi salva como rascunho e já pode ser ativada.'); await loadPromocoes();
    } catch (erro) {
      const parcial = promocaoId ? 'A promoção foi salva como rascunho, mas ainda está incompleta. ' : '';
      mostrarErroForm(parcial + erroAmigavel(erro)); showToast('Não foi possível concluir', parcial + erroAmigavel(erro)); await loadPromocoes();
    } finally { btn.disabled = false; btn.textContent = 'Salvar rascunho'; }
  }

  async function acaoPromocao(acao, id) {
    if (!podeAdministrar()) return;
    if (acao === 'arquivar' && !confirm('Arquivar esta promoção? Ela não poderá ser reativada ou editada.')) return;
    const rpc = { ativar: 'ativar_promocao', desativar: 'desativar_promocao', arquivar: 'arquivar_promocao' }[acao];
    const { error } = await sb.rpc(rpc, { p_promocao_id: id });
    if (error) showToast('Ação não concluída', erroAmigavel(error));
    else showToast('Promoção atualizada', acao === 'ativar' ? 'A campanha está ativa.' : acao === 'desativar' ? 'A campanha foi desativada.' : 'A campanha foi arquivada.');
    await loadPromocoes();
  }

  Object.assign(window, { loadPromocoes, openPromocao, closePromocao, renderPromocaoEscopos, onPromocaoModoChange, setPromoCategoria, setPromoItem, adicionarPromoItem, removerPromoItem, aplicarAtalhoLevePague, atualizarAtalhoLevePague, submitPromocao, acaoPromocao });
  document.addEventListener('input', event => { if (event.target.closest?.('#promocaoModalBg')) atualizarPreviewPromocao(); });
  document.addEventListener('keydown', event => { if (event.key === 'Escape' && el('promocaoModalBg')?.classList.contains('show')) closePromocao(); });
})();
