// Status da loja no painel. A fonte de verdade é status_publico_restaurante.
// Depende das globais sb, restauranteSlugAtual e statusLojaInterval.

  let statusLojaServidorPainelCarregando = false;

  function agendarStatusLojaPainel(status) {
    if (statusLojaInterval) clearTimeout(statusLojaInterval);
    let esperaMs = 60 * 1000;
    if (status?.proxima_mudanca && status?.servidor_agora) {
      const duracaoServidor = Date.parse(status.proxima_mudanca) - Date.parse(status.servidor_agora);
      if (Number.isFinite(duracaoServidor)) esperaMs = Math.max(1000, duracaoServidor + 1000);
    }
    statusLojaInterval = setTimeout(atualizarStatusLoja, esperaMs);
  }

  function renderizarStatusLojaPainel(status) {
    const pill = document.getElementById('lojaStatusPill');
    const txt = document.getElementById('lojaStatusTxt');
    if (!pill || !txt) return;

    const aberto = status?.aberto === true;
    pill.className = 'pill-status ' + (aberto ? 'on' : 'off');

    if (!status) {
      txt.textContent = 'Status da loja indisponível';
    } else if (status.motivo === 'aberto_24h') {
      txt.textContent = 'Loja aberta · 24 horas';
    } else if (aberto) {
      txt.textContent = 'Loja aberta';
    } else if (status.motivo === 'fechado') {
      txt.textContent = `Loja fechada · ${status.mensagem || 'Fechada no momento'}`;
    } else if (status.motivo === 'sem_configuracao') {
      txt.textContent = 'Horário não configurado';
    } else if (status.motivo === 'horario_invalido') {
      txt.textContent = 'Horário inválido';
    } else {
      txt.textContent = 'Status da loja indisponível';
    }
  }

  async function atualizarStatusLoja() {
    if (statusLojaServidorPainelCarregando || !sb || !restauranteSlugAtual) return null;
    statusLojaServidorPainelCarregando = true;
    try {
      const { data, error } = await sb.rpc('status_publico_restaurante', {
        p_slug: restauranteSlugAtual
      });
      if (error) throw error;
      const status = Array.isArray(data) ? data[0] : data;
      if (!status || typeof status.aberto !== 'boolean') throw new Error('Resposta inválida do status da loja.');
      renderizarStatusLojaPainel(status);
      agendarStatusLojaPainel(status);
      return status;
    } catch (erro) {
      console.warn('Status da loja indisponível:', erro);
      renderizarStatusLojaPainel(null);
      agendarStatusLojaPainel(null);
      return null;
    } finally {
      statusLojaServidorPainelCarregando = false;
    }
  }

  function iniciarStatusLoja() {
    atualizarStatusLoja();
  }

  window.addEventListener('focus', () => atualizarStatusLoja());
