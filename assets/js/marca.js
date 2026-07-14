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
      .select('id, nome, slug, logo_url, cor_destaque, whatsapp, endereco, instagram, horarios_semana, prazo_entrega_min_minutos, prazo_entrega_max_minutos')
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
    document.getElementById('mkPrazoEntregaMin').value = data.prazo_entrega_min_minutos == null ? '' : String(data.prazo_entrega_min_minutos);
    document.getElementById('mkPrazoEntregaMax').value = data.prazo_entrega_max_minutos == null ? '' : String(data.prazo_entrega_max_minutos);

    horariosSemanaState = normalizarHorariosSemana(data.horarios_semana);
    renderHorariosGrid();

    atualizarLinkCardapioPreview();
  }

  function validarPrazosEntrega(minimoId = 'mkPrazoEntregaMin', maximoId = 'mkPrazoEntregaMax') {
    const minimoDigitado = document.getElementById(minimoId).value.trim();
    const maximoDigitado = document.getElementById(maximoId).value.trim();

    if (!minimoDigitado && !maximoDigitado) {
      return { valido: true, minimo: null, maximo: null };
    }
    if (!minimoDigitado || !maximoDigitado) {
      return { valido: false, mensagem: 'Preencha os dois prazos de entrega ou deixe os dois campos vazios.' };
    }
    if (!/^\d+$/.test(minimoDigitado) || !/^\d+$/.test(maximoDigitado)) {
      return { valido: false, mensagem: 'Informe os prazos em minutos usando somente números inteiros.' };
    }

    const minimo = Number(minimoDigitado);
    const maximo = Number(maximoDigitado);
    if (!Number.isInteger(minimo) || !Number.isInteger(maximo) || minimo < 0 || maximo < 0 || minimo > 120 || maximo > 120) {
      return { valido: false, mensagem: 'Os prazos devem ser números inteiros entre 0 e 120 minutos.' };
    }
    if (minimo > maximo) {
      return { valido: false, mensagem: 'O prazo mínimo não pode ser maior que o prazo máximo.' };
    }

    return { valido: true, minimo, maximo };
  }

  function formatarPrazoEntregaBotao(minimo, maximo) {
    if (minimo == null || maximo == null) return '⏱ Definir prazo';
    if (minimo === 0 && maximo === 0) return '⏱ Imediata';
    if (minimo === maximo) return `⏱ ${minimo} min`;
    return `⏱ ${minimo}–${maximo} min`;
  }

  function atualizarBotaoPrazoEntrega() {
    const botao = document.getElementById('btnPrazoEntregaPedidos');
    if (!botao) return;
    botao.textContent = formatarPrazoEntregaBotao(
      restauranteInfo?.prazo_entrega_min_minutos,
      restauranteInfo?.prazo_entrega_max_minutos
    );
  }

  async function notificarConfiguracaoPublicaAtualizada() {
    if (!sb || !restauranteId) return;

    const channel = sb.channel(`restaurante-publico:${restauranteId}`);

    try {
      const resposta = await channel.send({
        type: 'broadcast',
        event: 'configuracao_atualizada',
        payload: {
          restaurante_id: restauranteId
        }
      });

      if (resposta !== 'ok') {
        console.warn('Broadcast da configuração pública não confirmado:', resposta);
      }
    } catch (erro) {
      console.warn('Não foi possível notificar o cardápio aberto:', erro);
    } finally {
      sb.removeChannel(channel);
    }
  }

  function abrirPrazoEntregaPedidos() {
    if (currentUser?.role !== 'dono') {
      showToast('Acesso restrito', 'Somente o dono pode alterar o prazo de entrega.');
      return;
    }
    document.getElementById('pedidoPrazoEntregaMin').value = restauranteInfo?.prazo_entrega_min_minutos == null
      ? ''
      : String(restauranteInfo.prazo_entrega_min_minutos);
    document.getElementById('pedidoPrazoEntregaMax').value = restauranteInfo?.prazo_entrega_max_minutos == null
      ? ''
      : String(restauranteInfo.prazo_entrega_max_minutos);
    document.getElementById('pedidoPrazoRetirada').value = restauranteInfo?.prazo_retirada_min_minutos == null
      ? ''
      : String(restauranteInfo.prazo_retirada_min_minutos);
    document.getElementById('pedidoPrazoModalBg').classList.add('show');
  }

  function fecharPrazoEntregaPedidos() {
    document.getElementById('pedidoPrazoModalBg').classList.remove('show');
  }

  function validarPrazoRetirada() {
    const valorDigitado = document.getElementById('pedidoPrazoRetirada').value.trim();
    if (!valorDigitado) return { valido: true, valor: null };

    if (!/^\d+$/.test(valorDigitado)) {
      return { valido: false };
    }

    const valor = Number(valorDigitado);
    if (!Number.isInteger(valor) || valor < 0 || valor > 120) {
      return { valido: false };
    }

    return { valido: true, valor };
  }

  async function salvarPrazoEntregaPedidos() {
    const prazosEntrega = validarPrazosEntrega('pedidoPrazoEntregaMin', 'pedidoPrazoEntregaMax');
    if (!prazosEntrega.valido) {
      showToast('Prazo de entrega inválido', prazosEntrega.mensagem);
      return;
    }
    const prazoRetirada = validarPrazoRetirada();
    if (!prazoRetirada.valido) {
      showToast('Prazo de retirada inválido', 'Informe o prazo de retirada em minutos, usando um número inteiro entre 0 e 120.');
      return;
    }

    const payload = {
      prazo_entrega_min_minutos: prazosEntrega.minimo,
      prazo_entrega_max_minutos: prazosEntrega.maximo,
      prazo_retirada_min_minutos: prazoRetirada.valor,
      prazo_retirada_max_minutos: prazoRetirada.valor
    };
    const { error } = await sb.from('restaurantes').update(payload).eq('id', restauranteId);
    if (error) {
      showToast('Erro ao salvar prazo', error.message);
      return;
    }

    await notificarConfiguracaoPublicaAtualizada();

    restauranteInfo = { ...(restauranteInfo || {}), ...payload };
    atualizarBotaoPrazoEntrega();
    document.getElementById('mkPrazoEntregaMin').value = prazosEntrega.minimo == null ? '' : String(prazosEntrega.minimo);
    document.getElementById('mkPrazoEntregaMax').value = prazosEntrega.maximo == null ? '' : String(prazosEntrega.maximo);
    fecharPrazoEntregaPedidos();
    showToast('Prazo de entrega atualizado.', 'O novo prazo já aparece no cardápio do cliente.');
  }

  async function submitMarca() {
    const nome = document.getElementById('mkNome').value.trim();
    if (!nome) { showToast('Faltou o nome', 'Informe o nome do restaurante.'); return; }
    const slugDigitado = document.getElementById('mkSlug').value.trim();
    const slugFinal = slugDigitado ? slugify(slugDigitado) : null;
    const prazosEntrega = validarPrazosEntrega();
    if (!prazosEntrega.valido) {
      showToast('Prazo de entrega inválido', prazosEntrega.mensagem);
      return;
    }

    const payload = {
      nome,
      slug: slugFinal,
      logo_url: document.getElementById('mkLogoUrl').value.trim() || null,
      cor_destaque: document.getElementById('mkCor').value || null,
      whatsapp: document.getElementById('mkWhatsapp').value.trim() || null,
      endereco: document.getElementById('mkEndereco').value.trim() || null,
      instagram: document.getElementById('mkInstagram').value.trim() || null,
      prazo_entrega_min_minutos: prazosEntrega.minimo,
      prazo_entrega_max_minutos: prazosEntrega.maximo,
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
    await notificarConfiguracaoPublicaAtualizada();
    document.getElementById('restauranteNome').textContent = nome;
    document.getElementById('mkSlug').value = slugFinal || '';
    restauranteSlugAtual = slugFinal;
    restauranteInfo = {
      ...(restauranteInfo || {}),
      prazo_entrega_min_minutos: prazosEntrega.minimo,
      prazo_entrega_max_minutos: prazosEntrega.maximo
    };
    atualizarBotaoPrazoEntrega();
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
