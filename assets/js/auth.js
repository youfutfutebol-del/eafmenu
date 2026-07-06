// /assets/js/auth.js
// Funcoes de autenticacao e senha do painel, extraidas do index.html (Etapa 3 da fragmentacao).
// Dependem de variaveis globais declaradas no script principal (sb, currentUser) e da funcao boot().
// So sao chamadas via clique do usuario, depois que o script principal ja rodou - por isso e seguro
// carregar este arquivo ANTES do script principal. Continuam globais (sem type=module).

async function fazerLogin() {
  if (!sb) { setLoginMsg('Ainda carregando configuração, aguarde...', false); return; }

  const identificador = document.getElementById('identInput').value.trim();
  const senha = document.getElementById('senhaInput').value;
  if (!identificador || !senha) { setLoginMsg('Preencha telefone/e-mail e senha.', true); return; }

  setLoginMsg('Entrando...', false);
  document.getElementById('loginBtn').disabled = true;

  const { data: emailResolvido, error: resolveErr } = await sb.rpc('resolver_email_login', { p_identificador: identificador });

  if (resolveErr || !emailResolvido) {
    document.getElementById('loginBtn').disabled = false;
    setLoginMsg('Não encontramos uma conta com esse telefone ou e-mail.', true);
    return;
  }

  const { error } = await sb.auth.signInWithPassword({ email: emailResolvido, password: senha });

  document.getElementById('loginBtn').disabled = false;

  if (error) { setLoginMsg('Telefone/e-mail ou senha incorretos.', true); return; }

  await boot();
}

function setLoginMsg(msg, isError) {
  const el = document.getElementById('loginMsg');
  el.textContent = msg;
  el.className = 'login-msg' + (isError ? ' error' : '');
}

function abrirEsqueciSenha() {
  document.getElementById('stepLogin').style.display = 'none';
  document.getElementById('stepEsqueciSenha').style.display = 'block';
  document.getElementById('loginMsg').textContent = '';
}

function fecharEsqueciSenha() {
  document.getElementById('stepEsqueciSenha').style.display = 'none';
  document.getElementById('stepLogin').style.display = 'block';
  document.getElementById('loginMsg').textContent = '';
}

async function enviarRecuperacaoSenha() {
  const identificador = document.getElementById('recIdentInput').value.trim();
  if (!identificador) { setLoginMsg('Informe seu telefone ou e-mail cadastrado.', true); return; }

  document.getElementById('recBtn').disabled = true;
  const { data: emailResolvido, error: resolveErr } = await sb.rpc('resolver_email_login', { p_identificador: identificador });

  if (resolveErr || !emailResolvido) {
    document.getElementById('recBtn').disabled = false;
    setLoginMsg('Não encontramos uma conta com esse telefone ou e-mail.', true);
    return;
  }

  const { error } = await sb.auth.resetPasswordForEmail(emailResolvido, { redirectTo: location.origin + location.pathname });
  document.getElementById('recBtn').disabled = false;

  if (error) { setLoginMsg('Erro ao enviar o link: ' + error.message, true); return; }
  setLoginMsg('Se o telefone/e-mail estiver cadastrado, um link de redefinição foi enviado por e-mail.', false);
}

function mostrarTelaNovaSenhaRecuperacao() {
  document.getElementById('stepLogin').style.display = 'none';
  document.getElementById('stepEsqueciSenha').style.display = 'none';
  document.getElementById('stepNovaSenha').style.display = 'block';
  document.getElementById('loginMsg').textContent = '';
}

async function salvarNovaSenhaRecuperacao() {
  const nova = document.getElementById('novaSenhaRecInput').value;
  const conf = document.getElementById('novaSenhaRecConfirm').value;
  if (!nova || nova.length < 6) { setLoginMsg('A senha precisa ter pelo menos 6 caracteres.', true); return; }
  if (nova !== conf) { setLoginMsg('As senhas não coincidem.', true); return; }

  document.getElementById('novaSenhaRecBtn').disabled = true;
  const { error } = await sb.auth.updateUser({ password: nova });
  document.getElementById('novaSenhaRecBtn').disabled = false;

  if (error) { setLoginMsg('Erro ao salvar a senha: ' + error.message, true); return; }

  // Limpa o token da URL antes de entrar, senão um refresh de página cairia de novo nessa tela.
  history.replaceState(null, '', location.pathname);

  setLoginMsg('Senha redefinida! Entrando...', false);
  await boot();
}

  function abrirTrocarMinhaSenha() {
    document.getElementById('msNovaSenha').value = '';
    document.getElementById('msNovaSenhaConfirm').value = '';
    document.getElementById('minhaSenhaModalBg').classList.add('show');
  }

  function fecharTrocarMinhaSenha() { document.getElementById('minhaSenhaModalBg').classList.remove('show'); }

  async function submitTrocarMinhaSenha() {
    const nova = document.getElementById('msNovaSenha').value;
    const conf = document.getElementById('msNovaSenhaConfirm').value;
    if (!nova || nova.length < 4) { showToast('Senha muito curta', 'Use pelo menos 4 caracteres.'); return; }
    if (nova !== conf) { showToast('Senhas diferentes', 'A confirmação não bateu com a nova senha.'); return; }

    const { error } = await sb.auth.updateUser({ password: nova });
    if (error) { showToast('Erro ao trocar senha', error.message); return; }
    fecharTrocarMinhaSenha();
    showToast('Senha atualizada', 'Sua senha foi trocada com sucesso.');
  }

  async function logout() {
    await sb.auth.signOut();
    location.reload();
  }

  async function salvarSenhaPrimeiroAcesso() {
    const nova = document.getElementById('paNovaSenha').value;
    const conf = document.getElementById('paNovaSenhaConfirm').value;
    const msgEl = document.getElementById('paMsg');
    if (!nova || nova.length < 6) { msgEl.textContent = 'A senha precisa ter pelo menos 6 caracteres.'; msgEl.className = 'login-msg error'; return; }
    if (nova !== conf) { msgEl.textContent = 'As senhas não coincidem.'; msgEl.className = 'login-msg error'; return; }

    document.getElementById('paBtn').disabled = true;
    const { error: authErr } = await sb.auth.updateUser({ password: nova });
    if (authErr) {
      document.getElementById('paBtn').disabled = false;
      msgEl.textContent = 'Erro ao salvar: ' + authErr.message;
      msgEl.className = 'login-msg error';
      return;
    }

    await sb.from('usuarios').update({ primeiro_acesso: false }).eq('id', currentUser.id);
    document.getElementById('paBtn').disabled = false;
    await boot();
  }
