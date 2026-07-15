// /assets/js/produtos-categorias.js
// Logica de Produtos, Categorias, Grupos de Tamanho e upload de imagem de produto, extraida do index.html (Etapa 6).
// Dependem de globais do script principal: sb, restauranteId, categoriasCache, gruposTamanhoCache,
// produtosAdminCache, tipoPrecoAtual, camposTamanhoAtivos, novosTamanhosState, e das funcoes
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
    fillGrupoTamanhoSelect();
  }

  function fillGrupoTamanhoSelect() {
    const sel = document.getElementById('pGrupoTamanho');
    sel.innerHTML = '<option value="">Selecione um grupo de tamanho...</option>' +
      gruposTamanhoCache.map(g => `<option value="${g.id}">${g.nome}</option>`).join('') +
      '<option value="__novo__">+ Criar novo grupo de tamanho</option>';
  }

  async function loadProdutosAdmin() {
    const { data, error } = await sb.from('produtos')
      .select(`
        id, nome, descricao, imagem_url, ativo, categoria_id,
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
          .map(pp => `<span class="price-tag">${escapeHtml(pp.opcoes_tamanho?.nome || 'Único')}: <b>${escapeHtml(formatMoeda(pp.preco))}</b></span>`)
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

  function setTipoPreco(tipo) {
    tipoPrecoAtual = tipo;
    document.getElementById('btnPrecoUnico').classList.toggle('active', tipo === 'unico');
    document.getElementById('btnPrecoTamanhos').classList.toggle('active', tipo === 'tamanhos');
    document.getElementById('blocoPrecoUnico').style.display = tipo === 'unico' ? 'block' : 'none';
    document.getElementById('blocoPrecoTamanhos').style.display = tipo === 'tamanhos' ? 'block' : 'none';
  }

  function onGrupoTamanhoChange() {
    const val = document.getElementById('pGrupoTamanho').value;
    document.getElementById('camposPrecoTamanhos').innerHTML = '';
    camposTamanhoAtivos = [];
    document.getElementById('grupoMaxSaboresExistenteWrap').style.display = 'none';

    if (val === '__novo__') {
      document.getElementById('novoGrupoFields').style.display = 'block';
      document.getElementById('pNovoGrupoNome').value = '';
      document.getElementById('pNovoGrupoMaxSabores').value = 1;
      novosTamanhosState = [];
      addNovoTamanhoRow();
      addNovoTamanhoRow();
    } else {
      document.getElementById('novoGrupoFields').style.display = 'none';
      novosTamanhosState = [];
      if (val) {
        const grupo = gruposTamanhoCache.find(g => g.id === val);
        camposTamanhoAtivos = (grupo?.opcoes_tamanho || []).map(o => ({ id: o.id, nome: o.nome }));
        renderCamposPreco();
        document.getElementById('grupoMaxSaboresExistenteWrap').style.display = 'block';
        document.getElementById('pGrupoMaxSaboresExistente').value = grupo?.max_sabores || 1;
      }
    }
  }

  function addNovoTamanhoRow(nome, preco) {
    novosTamanhosState.push({ nome: nome || '', preco: preco || '' });
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
      wrap.innerHTML = `<p class="novos-tamanhos-empty">Nenhum tamanho ainda. Clique em "+ adicionar tamanho".</p>`;
      return;
    }
    wrap.innerHTML = novosTamanhosState.map((t, i) => `
      <div class="novo-tamanho-row">
        <input class="nome" placeholder="Ex: 30cm" value="${t.nome}" oninput="atualizarNovoTamanho(${i}, 'nome', this.value)">
        <input class="preco" type="number" step="0.01" min="0" placeholder="0,00" value="${t.preco}" oninput="atualizarNovoTamanho(${i}, 'preco', this.value)">
        <button type="button" class="remove" onclick="removeNovoTamanhoRow(${i})" title="Remover">✕</button>
      </div>`).join('');
  }

  function renderCamposPreco(precoExistente) {
    const wrap = document.getElementById('camposPrecoTamanhos');
    wrap.innerHTML = camposTamanhoAtivos.map((t, i) => {
      const valorAtual = precoExistente ? (precoExistente[t.id] ?? '') : '';
      return `<div class="size-price-row"><span>${t.nome}</span><input type="number" step="0.01" min="0" class="precoTamanhoInput" data-idx="${i}" value="${valorAtual}" placeholder="0,00"></div>`;
    }).join('');
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
    document.getElementById('pPrecoUnico').value = '';
    document.getElementById('pGrupoTamanho').value = '';
    document.getElementById('novoGrupoFields').style.display = 'none';
    document.getElementById('grupoMaxSaboresExistenteWrap').style.display = 'none';
    document.getElementById('pNovoGrupoNome').value = '';
    document.getElementById('novosTamanhosRows').innerHTML = '';
    document.getElementById('camposPrecoTamanhos').innerHTML = '';
    camposTamanhoAtivos = [];
    novosTamanhosState = [];
    setTipoPreco('unico');
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
    document.getElementById('novoGrupoFields').style.display = 'none';
    document.getElementById('grupoMaxSaboresExistenteWrap').style.display = 'none';
    novosTamanhosState = [];

    const precos = p.produto_precos || [];
    const comTamanho = precos.some(pp => pp.opcao_tamanho_id);

    if (!comTamanho) {
      setTipoPreco('unico');
      document.getElementById('pPrecoUnico').value = precos[0]?.preco ?? '';
    } else {
      setTipoPreco('tamanhos');
      const opcaoIds = precos.map(pp => pp.opcao_tamanho_id).filter(Boolean);
      const grupo = gruposTamanhoCache.find(g => g.opcoes_tamanho.some(o => opcaoIds.includes(o.id)));
      if (grupo) {
        document.getElementById('pGrupoTamanho').value = grupo.id;
        camposTamanhoAtivos = grupo.opcoes_tamanho.map(o => ({ id: o.id, nome: o.nome }));
        const precoPorOpcao = {};
        precos.forEach(pp => { if (pp.opcao_tamanho_id) precoPorOpcao[pp.opcao_tamanho_id] = pp.preco; });
        renderCamposPreco(precoPorOpcao);
        document.getElementById('grupoMaxSaboresExistenteWrap').style.display = 'block';
        document.getElementById('pGrupoMaxSaboresExistente').value = grupo.max_sabores || 1;
      }
    }

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

    let grupo_tamanho_id = null;
    let precosParaSalvar = [];

    if (tipoPrecoAtual === 'unico') {
      const preco = parseFloat(document.getElementById('pPrecoUnico').value);
      if (!preco || preco <= 0) { showToast('Preço inválido', 'Informe um preço maior que zero.'); return; }
      precosParaSalvar = [{ opcao_tamanho_id: null, preco }];
    } else {
      let grupoSelecionado = document.getElementById('pGrupoTamanho').value;

      if (grupoSelecionado === '__novo__') {
        const novoNome = document.getElementById('pNovoGrupoNome').value.trim();
        if (!novoNome) { showToast('Faltou o nome do grupo', 'Dê um nome ao grupo de tamanho (ex: Tamanho da Pizza).'); return; }
        const novoMaxSabores = Math.max(1, parseInt(document.getElementById('pNovoGrupoMaxSabores').value || '1', 10));

        const tamanhosValidos = novosTamanhosState
          .map(t => ({ nome: (t.nome || '').trim(), preco: parseFloat(t.preco) }))
          .filter(t => t.nome);

        if (tamanhosValidos.length === 0) { showToast('Adicione os tamanhos', 'Clique em "+ adicionar tamanho" e preencha o nome de cada um (ex: 30cm, 35cm, 40cm).'); return; }
        if (tamanhosValidos.some(t => !t.preco || t.preco <= 0)) { showToast('Preço inválido', 'Informe um preço maior que zero para cada tamanho.'); return; }

        const { data: grupo, error: grupoErr } = await sb.from('grupos_tamanho')
          .insert({ nome: novoNome, restaurante_id: restauranteId, max_sabores: novoMaxSabores }).select().single();
        if (grupoErr) { showToast('Erro ao criar grupo', grupoErr.message); return; }
        grupo_tamanho_id = grupo.id;

        const { data: opcoesInseridas, error: opcErr } = await sb.from('opcoes_tamanho')
          .insert(tamanhosValidos.map((t, i) => ({ grupo_id: grupo.id, nome: t.nome, ordem: i })))
          .select();
        if (opcErr) { showToast('Erro ao criar tamanhos', opcErr.message); return; }

        const opcoesOrdenadas = opcoesInseridas.slice().sort((a, b) => a.ordem - b.ordem);
        precosParaSalvar = opcoesOrdenadas.map((o, i) => ({ opcao_tamanho_id: o.id, preco: tamanhosValidos[i].preco }));

        await loadGruposTamanho();
      } else if (grupoSelecionado) {
        grupo_tamanho_id = grupoSelecionado;
        const inputs = [...document.querySelectorAll('.precoTamanhoInput')];
        if (inputs.length === 0) { showToast('Faltaram os preços', 'Preencha o preço de cada tamanho.'); return; }
        precosParaSalvar = inputs.map((inp, i) => {
          const preco = parseFloat(inp.value);
          return { opcao_tamanho_id: camposTamanhoAtivos[i].id, preco };
        });
        if (precosParaSalvar.some(p => !p.preco || p.preco <= 0)) { showToast('Preço inválido', 'Todos os tamanhos precisam de um preço maior que zero.'); return; }

        const maxSaboresEditado = Math.max(1, parseInt(document.getElementById('pGrupoMaxSaboresExistente').value || '1', 10));
        const { error: grupoUpdateErr } = await sb.from('grupos_tamanho').update({ max_sabores: maxSaboresEditado }).eq('id', grupoSelecionado);
        if (grupoUpdateErr) { showToast('Erro ao atualizar sabores do grupo', grupoUpdateErr.message); return; }
        await loadGruposTamanho();
      } else {
        showToast('Selecione um grupo', 'Escolha ou crie um grupo de tamanho.');
        return;
      }
    }

    const payload = { nome, categoria_id, grupo_tamanho_id, descricao, imagem_url, ativo, restaurante_id: restauranteId };

    let produtoId = id;
    if (id) {
      const { error } = await sb.from('produtos').update(payload).eq('id', id);
      if (error) { showToast('Erro ao salvar produto', error.message); return; }
      await sb.from('produto_precos').delete().eq('produto_id', id);
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
