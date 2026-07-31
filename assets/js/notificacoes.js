let notificacoesCache = [];
let monitorEstadoRestauranteTimer = null;
let monitorNotificacoesTimer = null;
let carregamentoNotificacoesEmAndamento = null;
let monitorNotificacoesVisibilidadeRegistrado = false;

function abrirPaywallMotoboy() {
  document.getElementById('moduloMotoboyModalBg')?.classList.add('show');
}

function abrirModuloMotoboy() {
  if (!restauranteInfo?.modulo_motoboy_ativo) {
    abrirPaywallMotoboy();
    return;
  }
  abrirPwaMotoboy();
}

async function consultarEstadoRestauranteAtual() {
  const { data, error } = await sb.rpc('estado_acesso_restaurante_atual');
  if (error || !data?.[0]) return null;
  return data[0];
}

function iniciarMonitorEstadoRestaurante() {
  clearInterval(monitorEstadoRestauranteTimer);
  monitorEstadoRestauranteTimer = setInterval(async () => {
    const estado = await consultarEstadoRestauranteAtual();
    if (!estado) return;
    if (estado.pausado && currentScreen !== APP_SCREEN.SUSPENDED) {
      pararMonitorNotificacoes();
      showScreen(APP_SCREEN.SUSPENDED);
      return;
    }
    if (!estado.pausado && currentScreen === APP_SCREEN.SUSPENDED) {
      await bootSeguro();
      return;
    }
    if (restauranteInfo) restauranteInfo.modulo_motoboy_ativo = estado.modulo_motoboy_ativo === true;
  }, 15000);
}

async function carregarNotificacoes() {
  if (!currentUser || currentUser.role === 'motoboy' || currentScreen === APP_SCREEN.SUSPENDED) return;
  if (carregamentoNotificacoesEmAndamento) return carregamentoNotificacoesEmAndamento;
  carregamentoNotificacoesEmAndamento = (async () => {
    const { data, error } = await sb.rpc('listar_notificacoes_restaurante');
    if (error) {
      console.warn('Não foi possível carregar notificações:', error);
      return;
    }
    notificacoesCache = data || [];
    renderContadorNotificacoes();
    if (document.getElementById('notificacoesModalBg')?.classList.contains('show')) {
      renderNotificacoes();
    }
  })().finally(() => {
    carregamentoNotificacoesEmAndamento = null;
  });
  return carregamentoNotificacoesEmAndamento;
}

function iniciarMonitorNotificacoes() {
  if (!currentUser || currentUser.role === 'motoboy' || currentScreen === APP_SCREEN.SUSPENDED) return;
  pararMonitorNotificacoes();
  monitorNotificacoesTimer = setInterval(() => void carregarNotificacoes(), 60000);
  if (!monitorNotificacoesVisibilidadeRegistrado) {
    document.addEventListener('visibilitychange', atualizarNotificacoesAoVoltar);
    monitorNotificacoesVisibilidadeRegistrado = true;
  }
}

function atualizarNotificacoesAoVoltar() {
  if (document.visibilityState === 'visible') void carregarNotificacoes();
}

function pararMonitorNotificacoes() {
  clearInterval(monitorNotificacoesTimer);
  monitorNotificacoesTimer = null;
  if (monitorNotificacoesVisibilidadeRegistrado) {
    document.removeEventListener('visibilitychange', atualizarNotificacoesAoVoltar);
    monitorNotificacoesVisibilidadeRegistrado = false;
  }
}

function renderContadorNotificacoes() {
  const total = notificacoesCache.filter(n => !n.lida).length;
  ['notifContador', 'notifContadorMobile'].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = total > 99 ? '99+' : String(total);
    el.hidden = total === 0;
  });
}

async function abrirNotificacoes() {
  document.getElementById('notificacoesModalBg')?.classList.add('show');
  renderNotificacoes();
  await carregarNotificacoes();
}

function renderNotificacoes() {
  const wrap = document.getElementById('notificacoesLista');
  if (!wrap) return;
  if (!notificacoesCache.length) {
    wrap.innerHTML = '<div class="empty-state">Nenhuma notificação recebida.</div>';
    return;
  }
  wrap.innerHTML = notificacoesCache.map(n => `
    <article class="notification-item notification-item--${escapeHtml(n.tipo)} ${n.lida ? '' : 'unread'}">
      <div class="notification-item__header">
        <strong>${escapeHtml(n.titulo)}</strong>
        <span>${new Date(n.publicada_em).toLocaleString('pt-BR')}</span>
      </div>
      <p>${escapeHtml(n.mensagem)}</p>
      ${n.lida ? '<small>Lida</small>' : `<button class="btn" onclick="marcarNotificacaoLida('${escapeHtml(n.id)}', this)">Marcar como lida</button>`}
    </article>
  `).join('');
}

async function marcarNotificacaoLida(id, botao) {
  if (botao.disabled) return;
  botao.disabled = true;
  const { error } = await sb.rpc('marcar_notificacao_restaurante_lida', { p_notificacao_id:id });
  if (error) {
    botao.disabled = false;
    showToast('Não foi possível marcar como lida', 'Tente novamente.');
    return;
  }
  const alvo = notificacoesCache.find(n => n.id === id);
  if (alvo) alvo.lida = true;
  renderContadorNotificacoes();
  renderNotificacoes();
}
