// /assets/js/produtos-categorias.js
// Logica de Produtos, Categorias, Grupos de Tamanho e upload de imagem de produto, extraida do index.html (Etapa 6).
// Dependem de globais do script principal: sb, restauranteId, categoriasCache, gruposTamanhoCache,
// produtosAdminCache, novosTamanhosState e das funcoes
// showToast/formatMoeda/loadProdutos (essa ultima fica no script principal, alimenta o pedido manual).
// So chamadas apos o script principal rodar. Continuam globais (sem type=module).

  const categoriasProdutosAbertas = new Set();
  const CATEGORIA_SEM_CATEGORIA = '__sem_categoria__';

  async function loadCategorias() {
    const { data, error } = await sb.from('categorias')
      .select('id, nome, ordem')
      .eq('restaurante_id', restauranteId)
      .order('ordem', { ascending: true });
    if (!error) categoriasCache = data || [];
    fillCategoriaSelect();
  }

  async function loadCategoriasAdmin() {
    await loadCategorias();
    const { data: produtos } = await sb.from('produtos').select('id, categoria_id').eq('restaurante_id', restauranteId);
    const contagem = {};
    (produtos || []).forEach(p => { if (p.categoria_id) contagem[p.categoria_id] = (contagem[p.categoria_id] || 0) + 1; });

    const tbody = document.getElementById('categoriasTableBody');
    if (categoriasCache.length === 0) {
      tbody.innerHTML = `<tr><td colspan="4"><div class="empty-state"><div class="ic">🗂️</div><h4>Nenhuma categoria cadastrada</h4></div></td></tr>`;
      return;
    }
    tbody.innerHTML = categoriasCache.map(c => `
      <tr>
        <td data-label="Nome"><b>${c.nome}</b></td>
        <td data-label="Ordem">${c.ordem}</td>
        <td data-label="Produtos">${contagem[c.id] || 0} produto(s)</td>
        <td data-label="Ações">
          <div class="row-actions">
            <button onclick='openCategoria(${JSON.stringify(c)})'>Editar</button>
            <button class="danger" onclick="deleteCategoria('${c.id}', ${contagem[c.id] || 0})">Excluir</button>
          </div>
        </td>
      </tr>`).join('');
  }

  function fillCategoriaSelect() {
    const sel = document.getElementById('pCategoria');
    const atual = sel.value;
    sel.innerHTML = '<option value="">Sem categoria</option>' +
      categoriasCache.map(c => `<option value="${c.id}">${c.nome}</option>`).join('');
    sel.value = atual;
  }

  function openCategoria(cat) {
    document.getElementById('categoriaModalTitle').textContent = cat ? 'Editar categoria' : 'Nova categoria';
    document.getElementById('catId').value = cat ? cat.id : '';
    document.getElementById('catNome').value = cat ? cat.nome : '';
    document.getElementById('catOrdem').value = cat ? cat.ordem : categoriasCache.length;
    document.getElementById('categoriaModalBg').classList.add('show');
  }

  function closeCategoria() { document.getElementById('categoriaModalBg').classList.remove('show'); }

  async function submitCategoria() {
    const id = document.getElementById('catId').value;
    const nome = document.getElementById('catNome').value.trim();
    const ordem = parseInt(document.getElementById('catOrdem').value || '0', 10);
    if (!nome) { showToast('Faltou o nome', 'Informe o nome da categoria.'); return; }

    const payload = { nome, ordem, restaurante_id: restauranteId };
    const { error } = id
      ? await sb.from('categorias').update(payload).eq('id', id)
      : await sb.from('categorias').insert(payload);

    if (error) { showToast('Erro ao salvar', error.message); return; }
    closeCategoria();
    showToast('Categoria salva', nome);
    await loadCategoriasAdmin();
  }

  async function deleteCategoria(id, qtdProdutos) {
    if (qtdProdutos > 0) {
      showToast('Não é possível excluir', `Essa categoria tem ${qtdProdutos} produto(s) vinculado(s). Mude a categoria deles primeiro.`);
      return;
    }
    if (!confirm('Excluir esta categoria?')) return;
    const { error } = await sb.from('categorias').delete().eq('id', id);
    if (error) { showToast('Erro ao excluir', error.message); return; }
    showToast('Categoria excluída', '');
    await loadCategoriasAdmin();
  }

  async function loadGruposTamanho() {
    const { data, error } = await sb.from('grupos_tamanho')
      .select('id, nome, max_sabores, opcoes_tamanho(id, nome, ordem)')
      .eq('restaurante_id', restauranteId);
    if (!error) gruposTamanhoCache = (data || []).map(g => ({
      ...g,
      opcoes_tamanho: (g.opcoes_tamanho || []).sort((a, b) => a.ordem - b.ordem)
    }));
  }

  async function loadProdutosAdmin() {
    const { data, error } = await sb.from('produtos')
      .select(`
        id, nome, descricao, imagem_url, ativo, categoria_id, grupo_tamanho_id,
        categorias ( nome ),
        produto_precos ( id, preco, ativo, opcao_tamanho_id, opcoes_tamanho ( nome ) )
      `)
      .eq('restaurante_id', restauranteId)
      .order('nome', { ascending: true });
    if (error) { showToast('Erro ao carregar produtos', error.message); return; }
    produtosAdminCache = data || [];
    renderProdutosTable();
  }

  function renderProdutosTable() {
    const wrap = document.getElementById('produtosCategorias');
    const buscaEl = document.getElementById('produtoBusca');
    if (!wrap) return;
    if (produtosAdminCache.length === 0) {
      wrap.innerHTML = `<div class="empty-state"><div class="ic">🛍️</div><h4>Nenhum produto cadastrado</h4></div>`;
      return;
    }

    const normalizarBusca = valor => String(valor || '').normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('pt-BR').trim();
    const termo = normalizarBusca(buscaEl?.value);
    const pesquisando = termo.length > 0;
    const produtosFiltrados = pesquisando
      ? produtosAdminCache.filter(p => normalizarBusca(`${p.nome || ''} ${p.descricao || ''}`).includes(termo))
      : produtosAdminCache;
    if (pesquisando && produtosFiltrados.length === 0) {
      wrap.innerHTML = `<div class="empty-state"><div class="ic">🔍</div><h4>Nenhum produto encontrado</h4><p>Tente pesquisar por outro nome.</p></div>`;
      return;
    }

    const categoriasValidas = new Set(categoriasCache.map(c => String(c.id)));
    categoriasProdutosAbertas.forEach(chave => {
      if (chave !== CATEGORIA_SEM_CATEGORIA && !categoriasValidas.has(chave)) categoriasProdutosAbertas.delete(chave);
    });
    const grupos = categoriasCache.map(c => ({ chave: String(c.id), nome: c.nome, produtos: [] }));
    const gruposPorId = new Map(grupos.map(grupo => [grupo.chave, grupo]));
    const semCategoria = { chave: CATEGORIA_SEM_CATEGORIA, nome: 'Sem categoria', produtos: [] };
    produtosFiltrados.forEach(produto => {
      const grupo = produto.categoria_id ? gruposPorId.get(String(produto.categoria_id)) : null;
      (grupo || semCategoria).produtos.push(produto);
    });
    if (semCategoria.produtos.length) grupos.push(semCategoria);
    grupos.forEach(grupo => grupo.produtos.sort((a, b) => String(a.nome || '').localeCompare(String(b.nome || ''), 'pt-BR', { sensitivity: 'base' })));

    const renderProduto = p => {
      const precosAtivos = (p.produto_precos || []).filter(pp => pp.ativo);

      let precoHtml = '—';
      if (precosAtivos.length === 1 && !precosAtivos[0].opcoes_tamanho) {
        precoHtml = formatMoeda(precosAtivos[0].preco);
      } else if (precosAtivos.length >= 1) {
        precoHtml = '<div class="price-tags">' + precosAtivos
          .slice()
          .sort((a, b) => Number(a.preco) - Number(b.preco))
          .map(pp => pp.opcoes_tamanho?.nome
            ? `<span class="price-tag">${escapeHtml(pp.opcoes_tamanho.nome)}: <b>${escapeHtml(formatMoeda(pp.preco))}</b></span>`
            : `<span class="price-tag"><b>${escapeHtml(formatMoeda(pp.preco))}</b></span>`)
          .join('') + '</div>';
      }

      const thumb = p.imagem_url
        ? `<img src="${escapeHtml(p.imagem_url)}" alt="">`
        : getProdutoPlaceholder(p);
      const produtoId = escapeHtml(String(p.id));

      return `
        <tr>
          <td data-label="Produto">
            <div class="prod-row-name">
              <div class="prod-thumb">${thumb}</div>
              <div class="prod-name-text"><b>${escapeHtml(p.nome)}</b>${p.descricao ? `<span>${escapeHtml(p.descricao)}</span>` : ''}</div>
            </div>
          </td>
          <td data-label="Preço">${precoHtml}</td>
          <td data-label="Status"><span class="status-pill ${p.ativo ? 'ativo' : 'inativo'}">${p.ativo ? 'Ativo' : 'Inativo'}</span></td>
          <td data-label="Ações">
            <div class="row-actions">
              <button type="button" data-produto-acao="editar" data-produto-id="${produtoId}">Editar</button>
              <button type="button" data-produto-acao="alternar" data-produto-id="${produtoId}" data-produto-ativo="${p.ativo ? 'true' : 'false'}">${p.ativo ? 'Ocultar' : 'Reativar'}</button>
            </div>
          </td>
        </tr>`;
    };

    wrap.innerHTML = grupos.filter(grupo => grupo.produtos.length).map((grupo, indice) => {
      const aberto = pesquisando || categoriasProdutosAbertas.has(grupo.chave);
      const painelId = `produtos-categoria-${indice}`;
      const quantidade = grupo.produtos.length;
      return `<section class="produtos-categoria" data-categoria-chave="${escapeHtml(grupo.chave)}">
        <button class="produtos-categoria__cabecalho" type="button" aria-expanded="${aberto}" aria-controls="${painelId}">
          <span class="produtos-categoria__nome">${escapeHtml(grupo.nome)}</span>
          <span class="produtos-categoria__quantidade">${quantidade} ${quantidade === 1 ? 'produto' : 'produtos'}</span>
          <span class="produtos-categoria__seta" aria-hidden="true">${aberto ? '&#9650;' : '&#9660;'}</span>
        </button>
        <div class="produtos-categoria__conteudo" id="${painelId}" ${aberto ? '' : 'hidden'}>
          <table class="data-table produtos-categoria__tabela">
            <thead><tr><th>Foto / Nome</th><th>Preço</th><th>Status</th><th>Ações</th></tr></thead>
            <tbody>${grupo.produtos.map(renderProduto).join('')}</tbody>
          </table>
        </div>
      </section>`;
    }).join('');
  }

  function inicializarProdutosCategorias() {
    const busca = document.getElementById('produtoBusca');
    const wrap = document.getElementById('produtosCategorias');
    if (!busca || !wrap || busca.dataset.inicializado) return;
    busca.dataset.inicializado = 'true';
    busca.addEventListener('input', renderProdutosTable);
    wrap.addEventListener('click', evento => {
      const acao = evento.target.closest('[data-produto-acao]');
      if (acao) {
        const id = acao.dataset.produtoId;
        if (acao.dataset.produtoAcao === 'editar') editProduto(id);
        else toggleProdutoAtivo(id, acao.dataset.produtoAtivo === 'true');
        return;
      }
      const cabecalho = evento.target.closest('.produtos-categoria__cabecalho');
      if (!cabecalho || busca.value.trim()) return;
      const chave = cabecalho.closest('.produtos-categoria').dataset.categoriaChave;
      if (categoriasProdutosAbertas.has(chave)) categoriasProdutosAbertas.delete(chave);
      else categoriasProdutosAbertas.add(chave);
      renderProdutosTable();
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', inicializarProdutosCategorias);
  else inicializarProdutosCategorias();

  async function toggleProdutoAtivo(id, ativoAtual) {
    const { error } = await sb.from('produtos').update({ ativo: !ativoAtual }).eq('id', id);
    if (error) { showToast('Erro', error.message); return; }
    await loadProdutosAdmin();
    await loadProdutos();
  }

  function addNovoTamanhoRow(nome, preco) {
    novosTamanhosState.push({ nome: nome ?? '', preco: preco ?? '' });
    renderNovosTamanhosRows();
  }

  function removeNovoTamanhoRow(idx) {
    novosTamanhosState.splice(idx, 1);
    renderNovosTamanhosRows();
  }

  function atualizarNovoTamanho(idx, campo, valor) {
    if (novosTamanhosState[idx]) novosTamanhosState[idx][campo] = valor;
  }

  function renderNovosTamanhosRows() {
    const wrap = document.getElementById('novosTamanhosRows');
    if (novosTamanhosState.length === 0) {
      wrap.innerHTML = `<p class="novos-tamanhos-empty">Adicione ao menos uma linha de preço.</p>`;
      return;
    }
    wrap.innerHTML = novosTamanhosState.map((t, i) => `
      <div class="novo-tamanho-row">
        <input class="nome" aria-label="Nome do tamanho, opcional" placeholder="Ex: Grande, 30 cm, Família" value="${escapeHtml(t.nome)}" oninput="atualizarNovoTamanho(${i}, 'nome', this.value)">
        <input class="preco" aria-label="Preço" type="number" step="0.01" min="0" placeholder="0,00" value="${escapeHtml(t.preco)}" oninput="atualizarNovoTamanho(${i}, 'preco', this.value)">
        <button type="button" class="remove" onclick="removeNovoTamanhoRow(${i})" aria-label="Remover tamanho" title="Remover">✕</button>
      </div>`).join('');
  }

  function onPermitirCombinarChange() {
    const permitir = document.getElementById('pPermitirCombinar').checked;
    document.getElementById('pMaxSaboresWrap').classList.toggle('hidden', !permitir);
    if (permitir && Number(document.getElementById('pMaxSabores').value) < 2) {
      document.getElementById('pMaxSabores').value = 2;
    }
  }

  function normalizarNomeTamanho(nome) {
    return String(nome || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .trim()
      .replace(/\s+/g, ' ')
      .toLocaleLowerCase('pt-BR');
  }

  function assinaturaTamanhos(tamanhos) {
    return tamanhos.map(t => normalizarNomeTamanho(t.nome)).join('\u001f');
  }

  function validarTamanhosProduto(linhas, permitirCombinar, maxSaboresValor) {
    if (!linhas.length) return { erro: ['Faltaram os preços', 'Adicione ao menos uma linha de preço.'] };

    const tamanhos = linhas.map(linha => ({
      nome: String(linha.nome ?? ''),
      preco: Number(linha.preco)
    }));
    if (linhas.some(linha => String(linha.preco ?? '').trim() === '') || tamanhos.some(t => !Number.isFinite(t.preco) || t.preco <= 0)) {
      return { erro: ['Preço inválido', 'Informe um preço maior que zero em todas as linhas.'] };
    }
    if (tamanhos.length > 1 && tamanhos.some(t => !t.nome.trim())) {
      return { erro: ['Faltou o tamanho', 'Quando há mais de uma linha, informe o nome de todos os tamanhos.'] };
    }

    const nomesNormalizados = tamanhos.map(t => normalizarNomeTamanho(t.nome)).filter(Boolean);
    if (new Set(nomesNormalizados).size !== nomesNormalizados.length) {
      return { erro: ['Tamanho duplicado', 'Use um nome diferente para cada tamanho.'] };
    }
    if (permitirCombinar && tamanhos.some(t => !t.nome.trim())) {
      return { erro: ['Nomeie o tamanho', 'Para combinar sabores, todas as linhas precisam ter nome.'] };
    }

    const maxSabores = permitirCombinar ? Number(maxSaboresValor) : 1;
    if (permitirCombinar && (!Number.isInteger(maxSabores) || maxSabores < 2)) {
      return { erro: ['Máximo inválido', 'Informe um número inteiro de sabores igual ou maior que 2.'] };
    }
    return { tamanhos, maxSabores };
  }

  function grupoTemAssinatura(grupo, tamanhos, maxSabores) {
    return Number(grupo?.max_sabores || 1) === maxSabores
      && assinaturaTamanhos(grupo?.opcoes_tamanho || []) === assinaturaTamanhos(tamanhos);
  }

  function encontrarGrupoCompativel(categoriaId, tamanhos, maxSabores, produtoId) {
    return gruposTamanhoCache.find(grupo => {
      if (!grupoTemAssinatura(grupo, tamanhos, maxSabores)) return false;
      const vinculados = produtosAdminCache.filter(p => p.grupo_tamanho_id === grupo.id);
      if (!vinculados.length) return false;
      const outros = vinculados.filter(p => p.id !== produtoId);
      if (!outros.length && vinculados.some(p => p.id === produtoId)) return true;
      return outros.length > 0 && outros.every(p => (p.categoria_id || null) === categoriaId);
    }) || null;
  }

  function encontrarGrupoExclusivoAtual(produtoId, tamanhos) {
    if (!produtoId) return null;
    const produto = produtosAdminCache.find(p => p.id === produtoId);
    const grupo = gruposTamanhoCache.find(g => g.id === produto?.grupo_tamanho_id);
    if (!grupoTemAssinatura(grupo, tamanhos, 1)) return null;
    const outros = produtosAdminCache.filter(p => p.id !== produtoId && p.grupo_tamanho_id === grupo.id);
    return outros.length === 0 ? grupo : null;
  }

  function nomeGrupoInterno(categoriaId, tamanhos, maxSabores) {
    const categoria = normalizarNomeTamanho(categoriaId || 'sem-categoria').replace(/[^a-z0-9-]+/g, '-');
    const nomes = tamanhos.map(t => normalizarNomeTamanho(t.nome).replace(/[^a-z0-9-]+/g, '-')).join('-');
    const sufixo = globalThis.crypto?.randomUUID?.() || `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
    return `interno-categoria-${categoria}-${nomes}-${maxSabores}-${sufixo}`;
  }

  async function criarGrupoInterno(categoriaId, tamanhos, maxSabores) {
    const { data: grupo, error: grupoErr } = await sb.from('grupos_tamanho')
      .insert({
        nome: nomeGrupoInterno(categoriaId, tamanhos, maxSabores),
        restaurante_id: restauranteId,
        max_sabores: maxSabores
      }).select().single();
    if (grupoErr) throw new Error(grupoErr.message);

    const { data: opcoes, error: opcoesErr } = await sb.from('opcoes_tamanho')
      .insert(tamanhos.map((t, ordem) => ({ grupo_id: grupo.id, nome: t.nome, ordem })))
      .select();
    if (opcoesErr) throw new Error(opcoesErr.message);
    const opcoesOrdenadas = (opcoes || []).slice().sort((a, b) => a.ordem - b.ordem);
    const grupoCompleto = { ...grupo, opcoes_tamanho: opcoesOrdenadas };
    gruposTamanhoCache.push(grupoCompleto);
    return grupoCompleto;
  }

  function openProduto() {
    document.getElementById('produtoModalTitle').textContent = 'Novo produto';
    document.getElementById('pId').value = '';
    document.getElementById('pNome').value = '';
    document.getElementById('pCategoria').value = '';
    document.getElementById('pDescricao').value = '';
    document.getElementById('pImagemUrl').value = '';
    document.getElementById('pImagemArquivo').value = '';
    document.getElementById('pImagemPreview').style.display = 'none';
    document.getElementById('pImagemPlaceholder').textContent = 'P';
    document.getElementById('pImagemPlaceholder').style.display = 'block';
    document.getElementById('pImagemStatus').textContent = '';
    document.getElementById('pAtivo').checked = true;
    document.getElementById('pPermitirCombinar').checked = false;
    document.getElementById('pMaxSabores').value = 2;
    novosTamanhosState = [{ nome: '', preco: '' }];
    renderNovosTamanhosRows();
    onPermitirCombinarChange();
    document.getElementById('produtoModalBg').classList.add('show');
  }

  function editProduto(id) {
    const p = produtosAdminCache.find(x => x.id === id);
    if (!p) return;
    document.getElementById('produtoModalTitle').textContent = 'Editar produto';
    document.getElementById('pId').value = p.id;
    document.getElementById('pNome').value = p.nome;
    document.getElementById('pCategoria').value = p.categoria_id || '';
    document.getElementById('pDescricao').value = p.descricao || '';
    document.getElementById('pImagemUrl').value = p.imagem_url || '';
    document.getElementById('pImagemArquivo').value = '';
    document.getElementById('pImagemStatus').textContent = '';
    document.getElementById('pImagemPlaceholder').textContent = String(p.nome || 'P').trim().charAt(0).toUpperCase() || 'P';
    if (p.imagem_url) {
      document.getElementById('pImagemPreview').src = p.imagem_url;
      document.getElementById('pImagemPreview').style.display = 'block';
      document.getElementById('pImagemPlaceholder').style.display = 'none';
    } else {
      document.getElementById('pImagemPreview').style.display = 'none';
      document.getElementById('pImagemPlaceholder').style.display = 'block';
    }
    document.getElementById('pAtivo').checked = p.ativo;
    const precos = p.produto_precos || [];
    const grupo = gruposTamanhoCache.find(g => g.id === p.grupo_tamanho_id);
    const precoPorOpcao = new Map(precos.map(pp => [pp.opcao_tamanho_id, pp.preco]));
    novosTamanhosState = grupo?.opcoes_tamanho?.length
      ? grupo.opcoes_tamanho.map(opcao => ({ nome: opcao.nome, preco: precoPorOpcao.get(opcao.id) ?? '' }))
      : [{ nome: '', preco: precos.find(pp => !pp.opcao_tamanho_id)?.preco ?? '' }];
    document.getElementById('pPermitirCombinar').checked = Number(grupo?.max_sabores || 1) > 1;
    document.getElementById('pMaxSabores').value = Math.max(2, Number(grupo?.max_sabores || 2));
    renderNovosTamanhosRows();
    onPermitirCombinarChange();

    document.getElementById('produtoModalBg').classList.add('show');
  }

  function atualizarPlaceholderImagemProduto() {
    const nome = document.getElementById('pNome').value.trim();
    document.getElementById('pImagemPlaceholder').textContent = nome.charAt(0).toUpperCase() || 'P';
  }

  function closeProduto() { document.getElementById('produtoModalBg').classList.remove('show'); }

  async function submitProduto() {
    const id = document.getElementById('pId').value || null;
    const nome = document.getElementById('pNome').value.trim();
    if (!nome) { showToast('Faltou o nome', 'Informe o nome do produto.'); return; }
    const categoria_id = document.getElementById('pCategoria').value || null;
    const descricao = document.getElementById('pDescricao').value.trim() || null;
    const imagem_url = document.getElementById('pImagemUrl').value.trim() || null;
    const ativo = document.getElementById('pAtivo').checked;

    const permitirCombinar = document.getElementById('pPermitirCombinar').checked;
    const validacao = validarTamanhosProduto(novosTamanhosState, permitirCombinar, document.getElementById('pMaxSabores').value);
    if (validacao.erro) { showToast(...validacao.erro); return; }

    const { tamanhos, maxSabores } = validacao;
    const usaGrupo = tamanhos.length > 1 || Boolean(tamanhos[0].nome.trim());
    let grupo_tamanho_id = null;
    let precosParaSalvar = [];

    if (!usaGrupo) {
      precosParaSalvar = [{ opcao_tamanho_id: null, preco: tamanhos[0].preco }];
    } else {
      let grupo = permitirCombinar
        ? encontrarGrupoCompativel(categoria_id, tamanhos, maxSabores, id)
        : encontrarGrupoExclusivoAtual(id, tamanhos);
      if (!grupo) {
        try {
          grupo = await criarGrupoInterno(categoria_id, tamanhos, maxSabores);
        } catch (error) {
          showToast('Erro ao preparar tamanhos', error.message);
          return;
        }
      }
      grupo_tamanho_id = grupo.id;
      precosParaSalvar = grupo.opcoes_tamanho.map((opcao, i) => ({
        opcao_tamanho_id: opcao.id,
        preco: tamanhos[i].preco
      }));
    }

    const payload = { nome, categoria_id, grupo_tamanho_id, descricao, imagem_url, ativo, restaurante_id: restauranteId };

    let produtoId = id;
    if (id) {
      const { error } = await sb.from('produtos').update(payload).eq('id', id);
      if (error) { showToast('Erro ao salvar produto', error.message); return; }
      const { error: deleteErr } = await sb.from('produto_precos').delete().eq('produto_id', id);
      if (deleteErr) { showToast('Erro ao atualizar preços', deleteErr.message); return; }
    } else {
      const { data: novoProduto, error } = await sb.from('produtos').insert(payload).select().single();
      if (error) { showToast('Erro ao criar produto', error.message); return; }
      produtoId = novoProduto.id;
    }

    const { error: precoErr } = await sb.from('produto_precos')
      .insert(precosParaSalvar.map(p => ({ ...p, produto_id: produtoId })));
    if (precoErr) { showToast('Erro ao salvar preços', precoErr.message); return; }

    closeProduto();
    showToast('Produto salvo', nome);
    await loadProdutosAdmin();
    await loadProdutos();
  }

  async function uploadImagem(file, pasta) {
    const extensao = (file.name.split('.').pop() || 'jpg').toLowerCase();
    const nomeArquivo = `${restauranteId}/${pasta}/${Date.now()}_${Math.random().toString(36).slice(2, 8)}.${extensao}`;
    const { error } = await sb.storage.from('imagens').upload(nomeArquivo, file, {
      upsert: false,
      contentType: file.type
    });
    if (error) { showToast('Erro ao enviar imagem', error.message); return null; }
    const { data } = sb.storage.from('imagens').getPublicUrl(nomeArquivo);
    return data.publicUrl;
  }

  async function onImagemProdutoSelecionada(input) {
    const file = input.files[0];
    if (!file) return;
    if (!file.type.startsWith('image/')) { showToast('Arquivo inválido', 'Selecione um arquivo de imagem.'); return; }
    if (file.size > 5 * 1024 * 1024) { showToast('Imagem muito grande', 'Escolha uma imagem de até 5MB.'); return; }

    document.getElementById('pImagemPreview').src = URL.createObjectURL(file);
    document.getElementById('pImagemPreview').style.display = 'block';
    document.getElementById('pImagemPlaceholder').style.display = 'none';
    document.getElementById('pImagemStatus').textContent = 'Enviando imagem...';

    const url = await uploadImagem(file, 'produtos');
    if (url) {
      document.getElementById('pImagemUrl').value = url;
      document.getElementById('pImagemStatus').textContent = 'Imagem enviada ✓';
    } else {
      document.getElementById('pImagemStatus').textContent = 'Falha no envio, tente novamente.';
    }
  }
