// /assets/js/auth.js
// Funcoes de autenticacao e senha do painel, extraidas do index.html (Etapa 3 da fragmentacao).
// Dependem de variaveis globais declaradas no script principal (sb, currentUser) e da funcao boot().
// So sao chamadas via clique do usuario, depois que o script principal ja rodou - por isso e seguro
// carregar este arquivo ANTES do script principal. Continuam globais (sem type=module).

const SESSION_GUARD_PANEL_KEY = 'eaf_painel_session_guard';
const SESSION_MAX_MS = 12 * 60 * 60 * 1000;
const SESSION_IDLE_MS = 2 * 60 * 60 * 1000;
const SESSION_CHECK_MS = 60 * 1000;
let sessionGuardStarted = false;
let sessionGuardExpiring = false;
let sessionGuardLastPersist = 0;

function lerSessionGuardPainel() {
  try { return JSON.parse(localStorage.getItem(SESSION_GUARD_PANEL_KEY) || '{}'); }
  catch (e) { return {}; }
}

function salvarSessionGuardPainel(meta) {
  localStorage.setItem(SESSION_GUARD_PANEL_KEY, JSON.stringify(meta));
}

function prepararSessionGuardPainel(forcarNovoLogin) {
  const agora = Date.now();
  const meta = forcarNovoLogin ? {} : lerSessionGuardPainel();
  salvarSessionGuardPainel({
    loginAt: meta.loginAt || agora,
    lastActivityAt: meta.lastActivityAt || agora
  });
}

function registrarAtividadePainel() {
  if (!sessionGuardStarted || sessionGuardExpiring) return;
  const agora = Date.now();
  const meta = lerSessionGuardPainel();
  meta.loginAt = meta.loginAt || agora;
  meta.lastActivityAt = agora;
  if (agora - sessionGuardLastPersist > 15000) {
    salvarSessionGuardPainel(meta);
    sessionGuardLastPersist = agora;
  }
}

async function expirarSessaoPainel() {
  if (sessionGuardExpiring) return;
  sessionGuardExpiring = true;
  try {
    localStorage.removeItem(SESSION_GUARD_PANEL_KEY);
    await sb.auth.signOut();
  } catch (e) {}
  location.reload();
}

async function avaliarSessaoPainel() {
  if (!sessionGuardStarted || sessionGuardExpiring || !sb) return;
  const agora = Date.now();
  const meta = lerSessionGuardPainel();
  if (!meta.loginAt || !meta.lastActivityAt) {
    prepararSessionGuardPainel(false);
    return;
  }

  if (agora - meta.loginAt >= SESSION_MAX_MS) {
    await expirarSessaoPainel();
    return;
  }

  if (agora - meta.lastActivityAt >= SESSION_IDLE_MS) {
    const continuar = confirm('Sua sessão vai expirar por segurança. Deseja continuar?');
    if (continuar) registrarAtividadePainel();
    else await expirarSessaoPainel();
  }
}

function iniciarControleSessaoPainel() {
  if (sessionGuardStarted) return;
  const appAberto = document.getElementById('app')?.hidden === false;
  if (!appAberto || !currentUser) return;

  prepararSessionGuardPainel(false);
  sessionGuardStarted = true;

  ['click', 'touchstart', 'keydown', 'mousemove'].forEach(evt => {
    window.addEventListener(evt, registrarAtividadePainel, { passive: true });
  });
  window.addEventListener('focus', async () => {
    await avaliarSessaoPainel();
    if (sessionGuardExpiring) return;
    registrarAtividadePainel();
  });
  document.addEventListener('visibilitychange', async () => {
    if (document.visibilityState === 'visible') {
      await avaliarSessaoPainel();
      if (sessionGuardExpiring) return;
      registrarAtividadePainel();
    }
  });
  setInterval(avaliarSessaoPainel, SESSION_CHECK_MS);
}

setInterval(iniciarControleSessaoPainel, 1000);

function erroConflitoTelefoneLogin(error) {
  const mensagem = String(error?.message || '').toLowerCase();
  return mensagem.includes('telefone')
    && (mensagem.includes('conflito') || mensagem.includes('mais de uma conta') || mensagem.includes('múltiplas contas'));
}

async function fazerLogin() {
  if (!sb) { setLoginMsg('Ainda carregando configuração, aguarde...', false); return; }

  const identificador = document.getElementById('identInput').value.trim();
  const senha = document.getElementById('senhaInput').value;
  if (!identificador || !senha) { setLoginMsg('Preencha telefone/e-mail e senha.', true); return; }

  setLoginMsg('Entrando...', false);
  const loginBtn = document.getElementById('loginBtn');
  if (loginBtn.disabled) return;
  loginBtn.disabled = true;
  try {
    const { data, error } = await sb.functions.invoke('login-seguro', {
      body: { identificador, senha, contexto: 'restaurante' }
    });
    if (error || data?.ok !== true || !data?.session?.access_token || !data?.session?.refresh_token) {
      setLoginMsg('Não foi possível entrar. Confira os dados informados.', true);
      return;
    }
    const { error: sessionError } = await sb.auth.setSession({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token
    });
    if (sessionError) {
      console.warn('Não foi possível estabelecer a sessão do painel:', sessionError);
      setLoginMsg('Não foi possível entrar. Confira os dados informados.', true);
      return;
    }

    prepararSessionGuardPainel(true);
    await bootSeguro();
  } catch (error) {
    console.warn('Falha técnica no login seguro do painel:', error);
    setLoginMsg('Não foi possível entrar. Confira os dados informados.', true);
  } finally {
    loginBtn.disabled = false;
  }
}

function setLoginMsg(msg, isError) {
  const el = document.getElementById('loginMsg');
  el.textContent = msg;
  el.className = 'login-msg' + (isError ? ' error' : '');
}

function abrirRecuperacaoEafFlow() {
  abrirWhatsapp(
    '5541984213488',
    'Olá! Sou responsável por um restaurante que utiliza o EAF Menu e esqueci minha senha de acesso. Preciso de ajuda para redefinir. Nome do restaurante:'
  );
}

function abrirModalSuporteSenha() {
  document.getElementById('modalSuporteSenha').classList.add('show');
}

function fecharModalSuporteSenha() {
  document.getElementById('modalSuporteSenha').classList.remove('show');
}

document.addEventListener('keydown', event => {
  if (event.key === 'Escape') fecharModalSuporteSenha();
});

function mostrarTelaNovaSenhaRecuperacao() {
  showScreen(APP_SCREEN.LOGIN);
  document.getElementById('stepLogin').style.display = 'none';
  document.getElementById('stepNovaSenha').style.display = 'block';
  document.getElementById('loginMsg').textContent = '';
}

async function salvarNovaSenhaRecuperacao() {
  const nova = document.getElementById('novaSenhaRecInput').value;
  const conf = document.getElementById('novaSenhaRecConfirm').value;
  if (!nova || nova.length < 8) { setLoginMsg('A senha precisa ter pelo menos 8 caracteres.', true); return; }
  if (nova !== conf) { setLoginMsg('As senhas não coincidem.', true); return; }

  const botao = document.getElementById('novaSenhaRecBtn');
  if (botao.disabled) return;
  botao.disabled = true;
  try {
    const { error } = await sb.auth.updateUser({ password: nova });
    if (error) {
      console.warn('Falha técnica ao salvar senha recuperada:', error);
      setLoginMsg('Não foi possível salvar a nova senha. Tente novamente.', true);
      return;
    }
    document.getElementById('novaSenhaRecInput').value = '';
    document.getElementById('novaSenhaRecConfirm').value = '';

    // Limpa o token da URL antes de entrar, senão um refresh de página cairia de novo nessa tela.
    history.replaceState(null, '', location.pathname);

    setLoginMsg('Senha redefinida! Entrando...', false);
    await bootSeguro();
  } catch (error) {
    console.warn('Exceção técnica ao salvar senha recuperada:', error);
    setLoginMsg('Não foi possível salvar a nova senha. Tente novamente.', true);
  } finally {
    botao.disabled = false;
  }
}

  function abrirTrocarMinhaSenha() {
    document.getElementById('msNovaSenha').value = '';
    document.getElementById('msNovaSenhaConfirm').value = '';
    document.getElementById('minhaSenhaModalBg').classList.add('show');
  }

  function fecharTrocarMinhaSenha() {
    const nova = document.getElementById('msNovaSenha');
    const confirmacao = document.getElementById('msNovaSenhaConfirm');
    nova.value = '';
    confirmacao.value = '';
    nova.type = 'password';
    confirmacao.type = 'password';
    document.getElementById('minhaSenhaModalBg').classList.remove('show');
  }

  async function submitTrocarMinhaSenha() {
    const botao = document.getElementById('btnTrocarMinhaSenha');
    if (botao?.disabled) return;
    const nova = document.getElementById('msNovaSenha').value;
    const conf = document.getElementById('msNovaSenhaConfirm').value;
    if (!nova || nova.length < 8) { showToast('Senha muito curta', 'Use pelo menos 8 caracteres.'); return; }
    if (nova !== conf) { showToast('Senhas diferentes', 'A confirmação não bateu com a nova senha.'); return; }

    if (botao) botao.disabled = true;
    try {
      const { error } = await sb.auth.updateUser({ password: nova });
      if (error) {
        console.warn('Falha técnica ao trocar a própria senha:', error);
        showToast('Senha não atualizada', 'Não foi possível atualizar a senha. Tente novamente.');
        return;
      }
      document.getElementById('msNovaSenha').value = '';
      document.getElementById('msNovaSenhaConfirm').value = '';
      fecharTrocarMinhaSenha();
      showToast('Senha atualizada', 'Sua senha foi trocada com sucesso.');
    } catch (error) {
      console.warn('Exceção técnica ao trocar a própria senha:', error);
      showToast('Senha não atualizada', 'Não foi possível atualizar a senha. Tente novamente.');
    } finally {
      if (botao) botao.disabled = false;
    }
  }

  async function logout() {
    if (typeof pararMonitorNotificacoes === 'function') pararMonitorNotificacoes();
    localStorage.removeItem(SESSION_GUARD_PANEL_KEY);
    await sb.auth.signOut();
    location.reload();
  }

  let resetSenhaUsuarioAlvoId = null;
  let resetSenhaUsuarioRecursoCodigo = null;
  let resetSenhaUsuarioFocoOrigem = null;

  function abrirResetSenhaUsuario(id, nome, recursoCodigo, focoOrigem) {
    resetSenhaUsuarioAlvoId = id;
    resetSenhaUsuarioRecursoCodigo = recursoCodigo || null;
    resetSenhaUsuarioFocoOrigem = focoOrigem || document.activeElement;
    document.getElementById('resetSenhaUsuarioNome').textContent = nome || 'Usuário';
    document.getElementById('resetSenhaUsuarioNova').value = '';
    document.getElementById('resetSenhaUsuarioConfirm').value = '';
    document.getElementById('resetSenhaUsuarioMostrar').checked = false;
    alternarVisibilidadeResetSenhaUsuario(false);
    document.getElementById('resetSenhaUsuarioModalBg').classList.add('show');
  }

  function fecharResetSenhaUsuario() {
    const focoRetorno = resetSenhaUsuarioFocoOrigem;
    resetSenhaUsuarioAlvoId = null;
    resetSenhaUsuarioRecursoCodigo = null;
    resetSenhaUsuarioFocoOrigem = null;
    document.getElementById('resetSenhaUsuarioNome').textContent = '';
    document.getElementById('resetSenhaUsuarioNova').value = '';
    document.getElementById('resetSenhaUsuarioConfirm').value = '';
    document.getElementById('resetSenhaUsuarioModalBg').classList.remove('show');
    if (focoRetorno?.isConnected && focoRetorno.getClientRects().length && !focoRetorno.disabled) focoRetorno.focus();
  }

  function alternarVisibilidadeResetSenhaUsuario(mostrar) {
    const tipo = mostrar ? 'text' : 'password';
    document.getElementById('resetSenhaUsuarioNova').type = tipo;
    document.getElementById('resetSenhaUsuarioConfirm').type = tipo;
  }

  async function confirmarResetSenhaUsuario() {
    const id = resetSenhaUsuarioAlvoId;
    const nova = document.getElementById('resetSenhaUsuarioNova').value;
    const confirmacao = document.getElementById('resetSenhaUsuarioConfirm').value;
    const botao = document.getElementById('resetSenhaUsuarioConfirmar');
    if (!id) return;
    if (nova.length < 8) { showToast('Senha muito curta', 'Use pelo menos 8 caracteres.'); return; }
    if (nova !== confirmacao) { showToast('Senhas diferentes', 'A confirmação não coincide com a nova senha.'); return; }
    if (botao.disabled) return;
    botao.disabled = true;
    try {
      if (resetSenhaUsuarioRecursoCodigo) {
        const autorizacao = await RecursosPlanos.autorizar(resetSenhaUsuarioRecursoCodigo, botao, {
          restauranteNome: restauranteInfo?.nome || '',
          nomeFallback: 'Gestão de Equipe',
          focoRetorno: botao
        });
        if (!autorizacao.permitido) {
          if (autorizacao.motivo === 'erro') {
            showToast('Não foi possível verificar o recurso', 'Tente novamente antes de continuar.');
          }
          return;
        }
      }
      const { error } = await sb.rpc('redefinir_senha_usuario', { p_usuario_id: id, p_nova_senha: nova });
      if (error) {
        if (resetSenhaUsuarioRecursoCodigo && RecursosPlanos.registrarNegativa(error, resetSenhaUsuarioRecursoCodigo)) {
          showToast('Gestão de Equipe indisponível', 'A senha não foi alterada.');
          return;
        }
        console.warn('Falha técnica ao redefinir senha de usuário:', error);
        showToast('Senha não redefinida', 'Não foi possível redefinir a senha. Tente novamente.');
        return;
      }
      fecharResetSenhaUsuario();
      showToast('Senha redefinida', 'Senha redefinida. As sessões anteriores foram encerradas.');
    } catch (error) {
      console.warn('Exceção técnica ao redefinir senha de usuário:', error);
      showToast('Senha não redefinida', 'Não foi possível redefinir a senha. Tente novamente.');
    } finally {
      botao.disabled = false;
    }
  }

  async function salvarSenhaPrimeiroAcesso() {
    const nova = document.getElementById('paNovaSenha').value;
    const conf = document.getElementById('paNovaSenhaConfirm').value;
    const msgEl = document.getElementById('paMsg');
    if (!nova || nova.length < 8) { msgEl.textContent = 'A senha precisa ter pelo menos 8 caracteres.'; msgEl.className = 'login-msg error'; return; }
    if (nova !== conf) { msgEl.textContent = 'As senhas não coincidem.'; msgEl.className = 'login-msg error'; return; }

    const botao = document.getElementById('paBtn');
    if (botao.disabled) return;
    botao.disabled = true;
    try {
      const { error: authErr } = await sb.auth.updateUser({ password: nova });
      if (authErr) throw authErr;

      const { error: perfilErr } = await sb.from('usuarios')
        .update({ primeiro_acesso: false })
        .eq('id', currentUser.id);
      if (perfilErr) throw perfilErr;

      document.getElementById('paNovaSenha').value = '';
      document.getElementById('paNovaSenhaConfirm').value = '';
      await bootSeguro();
    } catch (error) {
      console.warn('Falha técnica ao concluir o primeiro acesso:', error);
      msgEl.textContent = 'Não foi possível concluir o primeiro acesso. Tente novamente.';
      msgEl.className = 'login-msg error';
    } finally {
      botao.disabled = false;
    }
  }
