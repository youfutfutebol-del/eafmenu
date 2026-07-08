// /assets/js/marca.js
// Logica da aba Personalizar Marca, extraida do index.html (Etapa 11).
// Dependem de globais/funcoes do script principal: sb, restauranteId, restauranteSlugAtual,
// horariosSemanaState, horariosLojaAtual, DIAS_SEMANA, atualizarStatusLoja(), showToast e
// slugify (utils.js), uploadImagem (produtos-categorias.js, NAO duplicada aqui).
// So chamadas apos o script principal rodar. Continuam globais (sem type=module).

  function atualizarLinkCardapioPreview() {
    const slug = document.getElementById('mkSlug').value.trim();
    document.getElementById('mkLinkPreview').textContent = slug ? (location.origin + '/cliente/?r=' + slugify(slug)) : '—';
  }

  function copiarLinkCardapio() {
    const texto = document.getElementById('mkLinkPreview').textContent;
    if (!texto || texto === '—') { showToast('Defina o link primeiro', 'Preencha o campo "Link do cardápio" e salve.'); return; }
    navigator.clipboard.writeText(texto).then(() => showToast('Link copiado', texto));
  }

  function horariosSemanaPadrao() {
    return DIAS_SEMANA.map((_, dia) => ({ dia, aberto: false, abre: '18:00', fecha: '23:00' }));
  }

  function normalizarHorariosSemana(valorBanco) {
    const base = horariosSemanaPadrao();
    if (Array.isArray(valorBanco)) {
      valorBanco.forEach(item => {
        const idx = base.findIndex(d => d.dia === item.dia);
        if (idx >= 0) base[idx] = { dia: item.dia, aberto: !!item.aberto, abre: item.abre || '18:00', fecha: item.fecha || '23:00' };
      });
    }
    return base;
  }

  function renderHorariosGrid() {
    const wrap = document.getElementById('horariosGrid');
    wrap.innerHTML = horariosSemanaState.map((d, i) => `
      <div class="horario-dia-row ${d.aberto ? '' : 'fechado'}">
        <span class="horario-dia-nome">${DIAS_SEMANA[d.dia]}</span>
        <button type="button" class="switch ${d.aberto ? 'on' : ''}" onclick="toggleDiaAberto(${i})" aria-label="Abrir/fechar ${DIAS_SEMANA[d.dia]}"></button>
        ${d.aberto
          ? `<div class="horario-dia-tempos">
               <input type="time" value="${d.abre}" onchange="atualizarHorarioDia(${i}, 'abre', this.value)">
               <span>até</span>
               <input type="time" value="${d.fecha}" onchange="atualizarHorarioDia(${i}, 'fecha', this.value)">
             </div>`
          : `<span class="horario-dia-fechado-label">Fechado nesse dia</span>`
        }
      </div>`).join('');
  }

  function toggleDiaAberto(idx) {
    horariosSemanaState[idx].aberto = !horariosSemanaState[idx].aberto;
    renderHorariosGrid();
  }

  function atualizarHorarioDia(idx, campo, valor) {
    horariosSemanaState[idx][campo] = valor;
  }

  async function loadMarca() {
    const { data, error } = await sb.from('restaurantes')
      .select('id, nome, slug, logo_url, cor_destaque, whatsapp, endereco, instagram, horarios_semana')
      .eq('id', restauranteId)
      .single();
    if (error) { showToast('Erro ao carregar dados da marca', error.message); return; }

    document.getElementById('mkNome').value = data.nome || '';
    document.getElementById('mkSlug').value = data.slug || '';
    document.getElementById('mkLogoUrl').value = data.logo_url || '';
    document.getElementById('mkLogoStatus').textContent = '';
    document.getElementById('mkLogoArquivo').value = '';
    if (data.logo_url) {
      document.getElementById('mkLogoPreview').src = data.logo_url;
      document.getElementById('mkLogoPreview').style.display = 'block';
      document.getElementById('mkLogoPlaceholder').style.display = 'none';
    } else {
      document.getElementById('mkLogoPreview').style.display = 'none';
      document.getElementById('mkLogoPlaceholder').style.display = 'block';
    }
    document.getElementById('mkCor').value = data.cor_destaque || '#E5342A';
    document.getElementById('mkWhatsapp').value = data.whatsapp || '';
    document.getElementById('mkEndereco').value = data.endereco || '';
    document.getElementById('mkInstagram').value = data.instagram || '';

    horariosSemanaState = normalizarHorariosSemana(data.horarios_semana);
    renderHorariosGrid();

    atualizarLinkCardapioPreview();
  }

  async function submitMarca() {
    const nome = document.getElementById('mkNome').value.trim();
    if (!nome) { showToast('Faltou o nome', 'Informe o nome do restaurante.'); return; }
    const slugDigitado = document.getElementById('mkSlug').value.trim();
    const slugFinal = slugDigitado ? slugify(slugDigitado) : null;

    const payload = {
      nome,
      slug: slugFinal,
      logo_url: document.getElementById('mkLogoUrl').value.trim() || null,
      cor_destaque: document.getElementById('mkCor').value || null,
      whatsapp: document.getElementById('mkWhatsapp').value.trim() || null,
      endereco: document.getElementById('mkEndereco').value.trim() || null,
      instagram: document.getElementById('mkInstagram').value.trim() || null,
      horarios_semana: horariosSemanaState
    };

    const { error } = await sb.from('restaurantes').update(payload).eq('id', restauranteId);
    if (error) {
      if (error.message && error.message.toLowerCase().includes('duplicate')) {
        showToast('Link já está em uso', 'Esse link (slug) já pertence a outro restaurante. Escolha outro.');
      } else {
        showToast('Erro ao salvar', error.message);
      }
      return;
    }
    document.getElementById('restauranteNome').textContent = nome;
    document.getElementById('mkSlug').value = slugFinal || '';
    restauranteSlugAtual = slugFinal;
    horariosLojaAtual = horariosSemanaState;
    atualizarStatusLoja();
    atualizarLinkCardapioPreview();
    showToast('Marca atualizada', 'As alterações já valem para o cardápio público.');
  }

  async function onLogoMarcaSelecionado(input) {
    const file = input.files[0];
    if (!file) return;
    if (!file.type.startsWith('image/')) { showToast('Arquivo inválido', 'Selecione um arquivo de imagem.'); return; }
    if (file.size > 5 * 1024 * 1024) { showToast('Imagem muito grande', 'Escolha uma imagem de até 5MB.'); return; }

    document.getElementById('mkLogoPreview').src = URL.createObjectURL(file);
    document.getElementById('mkLogoPreview').style.display = 'block';
    document.getElementById('mkLogoPlaceholder').style.display = 'none';
    document.getElementById('mkLogoStatus').textContent = 'Enviando imagem...';

    const url = await uploadImagem(file, 'marca');
    if (url) {
      document.getElementById('mkLogoUrl').value = url;
      document.getElementById('mkLogoStatus').textContent = 'Imagem enviada ✓ — clique em "Salvar alterações" pra confirmar.';
    } else {
      document.getElementById('mkLogoStatus').textContent = 'Falha no envio, tente novamente.';
    }
  }
