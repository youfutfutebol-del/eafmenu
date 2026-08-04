// /assets/js/equipe.js
// Logica da aba Gestao de Equipe, extraida do index.html (Etapa 10).
// Dependem de globais do script principal: sb, restauranteId, currentUser, equipeCache,
// convitesCache, ROLE_LABEL, e da funcao showToast (utils.js). So chamadas apos o script
// principal rodar. Continuam globais (sem type=module).

  let equipeAcaoEmAndamento = false;

  async function autorizarAcaoEquipe(botao, contexto = {}) {
    const resultado = await RecursosPlanos.autorizar('gestao_equipe', botao, {
      restauranteNome: restauranteInfo?.nome || '', nomeFallback: 'Gestão de Equipe', ...contexto
    });
    if (!resultado.permitido && resultado.motivo === 'erro') {
      showToast('Não foi possível verificar o recurso', 'Tente novamente antes de continuar.');
    }
    return resultado;
  }

  function tratarNegativaEquipe(error) {
    if (!RecursosPlanos.registrarNegativa(error, 'gestao_equipe')) return false;
    showToast('Gestão de Equipe indisponível', 'Esta ação não está disponível no pacote atual.');
    return true;
  }

  async function loadEquipe() {
    // Motoboy não aparece aqui — é criado e gerenciado em Entregadores (Motoboys).
    const { data: usuarios, error } = await sb.from('usuarios')
      .select('id, nome, email, telefone, role, ativo')
      .eq('restaurante_id', restauranteId)
      .neq('role', 'motoboy')
      .order('nome', { ascending: true });
    if (error) { showToast('Erro ao carregar equipe', error.message); return; }
    equipeCache = usuarios || [];

    const { data: convites, error: convErr } = await sb.from('convites_equipe')
      .select('id, nome, email, role')
      .eq('restaurante_id', restauranteId)
      .order('nome', { ascending: true });
    if (!convErr) convitesCache = convites || [];

    renderEquipeTable();
  }

  function renderEquipeTable() {
    const tbody = document.getElementById('equipeTableBody');
    if (equipeCache.length === 0) {
      tbody.innerHTML = `<tr><td colspan="5"><div class="empty-state"><div class="ic">🛡️</div><h4>Nenhum membro cadastrado</h4></div></td></tr>`;
    } else {
      tbody.innerHTML = equipeCache.map(u => `
        <tr>
          <td data-label="Nome"><b>${escapeHtml(u.nome)}</b></td>
          <td data-label="Telefone">${escapeHtml(u.telefone || u.email || '—')}</td>
          <td data-label="Cargo"><span class="status-pill ativo">${escapeHtml(ROLE_LABEL[u.role] || u.role)}</span></td>
          <td data-label="Status">
            <span class="status-pill ${u.ativo ? 'ativo' : 'inativo'}">${u.ativo ? 'Ativo' : 'Desativado'}</span>
          </td>
          <td data-label="Ações">
            <div class="row-actions">
              <select data-action="mudar-role" data-id="${escapeHtml(u.id)}" style="border:1px solid var(--border); border-radius:7px; padding:5px 8px; font-size:11.5px;" ${u.id === currentUser.id ? 'disabled' : ''}>
                ${Object.keys(ROLE_LABEL).map(r => `<option value="${escapeHtml(r)}" ${r === u.role ? 'selected' : ''}>${escapeHtml(ROLE_LABEL[r])}</option>`).join('')}
              </select>
              ${u.id === currentUser.id ? '' : `<button data-action="toggle-ativo" data-id="${escapeHtml(u.id)}" data-ativo="${u.ativo}">${u.ativo ? 'Desligar acesso' : 'Liberar acesso'}</button>`}
              ${podeRedefinirSenhaEquipe(u) ? `<button data-action="reset-senha" data-id="${escapeHtml(u.id)}">Redefinir senha</button>` : ''}
              ${u.id === currentUser.id ? '' : `<button class="danger" data-action="remover" data-id="${escapeHtml(u.id)}">Remover</button>`}
            </div>
          </td>
        </tr>`).join('');
    }

    const tbodyConv = document.getElementById('convitesTableBody');
    if (convitesCache.length === 0) {
      tbodyConv.innerHTML = `<tr><td colspan="4"><div class="empty-state"><div class="ic">✉️</div><h4>Nenhum convite pendente</h4></div></td></tr>`;
    } else {
      tbodyConv.innerHTML = convitesCache.map(c => `
        <tr>
          <td data-label="Nome"><b>${escapeHtml(c.nome)}</b></td>
          <td data-label="E-mail">${escapeHtml(c.email)}</td>
          <td data-label="Cargo"><span class="status-pill inativo">${escapeHtml(ROLE_LABEL[c.role] || c.role)}</span></td>
          <td data-label="Ações"><div class="row-actions"><button class="danger" data-action="cancelar-convite" data-id="${escapeHtml(c.id)}">Cancelar convite</button></div></td>
        </tr>`).join('');
    }
  }

  function podeRedefinirSenhaEquipe(usuario) {
    if (!usuario || usuario.id === currentUser.id) return false;
    if (currentUser.role === 'dono') return ['gerente', 'atendente'].includes(usuario.role);
    return currentUser.role === 'gerente' && usuario.role === 'atendente';
  }

  function registroEquipePorId(id) {
    return equipeCache.find(usuario => String(usuario.id) === String(id));
  }

  document.getElementById('equipeTableBody')?.addEventListener('click', event => {
    const alvo = event.target.closest('[data-action][data-id]');
    if (!alvo) return;
    const usuario = registroEquipePorId(alvo.dataset.id);
    if (!usuario) return;
    if (alvo.dataset.action === 'toggle-ativo') toggleAtivoUsuario(usuario.id, usuario.ativo, alvo);
    if (alvo.dataset.action === 'reset-senha' && podeRedefinirSenhaEquipe(usuario)) abrirResetSenhaEquipe(usuario.id, usuario.nome, alvo);
    if (alvo.dataset.action === 'remover') removerMembro(usuario.id, usuario.nome, alvo);
  });
  document.getElementById('equipeTableBody')?.addEventListener('change', event => {
    const alvo = event.target.closest('[data-action="mudar-role"][data-id]');
    if (alvo) mudarRole(alvo.dataset.id, alvo.value, alvo);
  });
  document.getElementById('convitesTableBody')?.addEventListener('click', event => {
    const alvo = event.target.closest('[data-action="cancelar-convite"][data-id]');
    if (alvo) cancelarConvite(alvo.dataset.id, alvo);
  });

  async function toggleAtivoUsuario(id, ativoAtual, origem) {
    const autorizacao = await autorizarAcaoEquipe(origem);
    if (!autorizacao.permitido) return;
    const { error } = await sb.from('usuarios').update({ ativo: !ativoAtual }).eq('id', id);
    if (error) { if (!tratarNegativaEquipe(error)) showToast('Erro ao atualizar acesso', error.message); return; }
    showToast(ativoAtual ? 'Acesso desligado' : 'Acesso liberado', '');
    await loadEquipe();
  }

  async function openMembro(origem) {
    const autorizacao = await autorizarAcaoEquipe(origem);
    if (!autorizacao.permitido) return;
    document.getElementById('mbNome').value = '';
    document.getElementById('mbTelefone').value = '';
    document.getElementById('mbEmail').value = '';
    document.getElementById('mbSenha').value = '';
    const roleSelect = document.getElementById('mbRole');
    // Gerente não pode criar outro gerente ou dono (regra também aplicada no banco).
    [...roleSelect.options].forEach(opt => {
      opt.disabled = (currentUser.role === 'gerente' && opt.value === 'dono');
    });
    roleSelect.value = 'atendente';
    document.getElementById('membroModalBg').classList.add('show');
  }

  function closeMembro() { document.getElementById('membroModalBg').classList.remove('show'); }

  async function submitMembro(origem) {
    if (equipeAcaoEmAndamento) return;
    const nome = document.getElementById('mbNome').value.trim();
    const telefone = document.getElementById('mbTelefone').value.trim();
    const telefoneNormalizado = normalizarTelefoneAcesso(telefone);
    const email = document.getElementById('mbEmail').value.trim().toLowerCase();
    const senha = document.getElementById('mbSenha').value;
    const role = document.getElementById('mbRole').value;
    const submitBtn = document.getElementById('mbSubmitBtn');
    if (!nome) { showToast('Faltou o nome', 'Informe o nome da pessoa.'); return; }
    if (!telefone) { showToast('Faltou o telefone', 'Informe o telefone da pessoa (usado para o login).'); return; }
    if (telefoneNormalizado.length < 10) { showToast('Telefone inválido', 'Informe um telefone com DDD e pelo menos 10 dígitos.'); return; }
    if (!senha || senha.length < 8) { showToast('Senha muito curta', 'Defina uma senha com pelo menos 8 caracteres.'); return; }
    if (submitBtn?.disabled) return;
    equipeAcaoEmAndamento = true;
    if (submitBtn) submitBtn.disabled = true;
    try {
      const autorizacao = await autorizarAcaoEquipe(origem);
      if (!autorizacao.permitido) return;
      const { error } = await sb.rpc('criar_usuario_equipe', {
        p_nome: nome,
        p_telefone: telefoneNormalizado,
        p_email: email || null,
        p_role: role,
        p_senha: senha
      });

      if (error) {
        if (error.message === 'Este telefone já está vinculado a outra conta de acesso.') {
          showToast('Telefone já utilizado', error.message);
          return;
        }
        if (tratarNegativaEquipe(error)) return;
        console.error('Falha ao criar usuário da equipe:', error);
        showToast('Erro ao criar usuário', 'Não foi possível criar o usuário. Tente novamente.');
        return;
      }

      closeMembro();
      showToast(`Usuário "${nome}" criado`, `Login: ${telefoneNormalizado} · Senha: a que você definiu`);
      await loadEquipe();
    } catch (error) {
      console.error('Exceção ao criar usuário da equipe:', error);
      showToast('Erro ao criar usuário', 'Não foi possível criar o usuário. Tente novamente.');
    } finally {
      equipeAcaoEmAndamento = false;
      if (submitBtn) submitBtn.disabled = false;
    }
  }

  async function mudarRole(id, novoRole, origem) {
    const autorizacao = await autorizarAcaoEquipe(origem);
    if (!autorizacao.permitido) { await loadEquipe(); return; }
    const { error } = await sb.from('usuarios').update({ role: novoRole }).eq('id', id);
    if (error) { if (!tratarNegativaEquipe(error)) showToast('Erro ao mudar cargo', error.message); await loadEquipe(); return; }
    showToast('Cargo atualizado', '');
    await loadEquipe();
  }

  async function removerMembro(id, nome, origem) {
    const autorizacao = await autorizarAcaoEquipe(origem);
    if (!autorizacao.permitido) return;
    if (!confirm(`Remover ${nome} da equipe? Isso apaga o acesso e a conta por completo — não dá pra desfazer.`)) return;
    const { error } = await sb.rpc('remover_usuario_equipe', { p_usuario_id: id });
    if (error) { if (!tratarNegativaEquipe(error)) showToast('Erro ao remover', error.message); return; }
    showToast('Membro removido', nome);
    await loadEquipe();
  }

  async function cancelarConvite(id, origem) {
    const autorizacao = await autorizarAcaoEquipe(origem);
    if (!autorizacao.permitido) return;
    const { error } = await sb.from('convites_equipe').delete().eq('id', id);
    if (error) { if (!tratarNegativaEquipe(error)) showToast('Erro ao cancelar', error.message); return; }
    showToast('Convite cancelado', '');
    await loadEquipe();
  }

  async function abrirResetSenhaEquipe(id, nome, origem) {
    const autorizacao = await autorizarAcaoEquipe(origem);
    if (autorizacao.permitido) abrirResetSenhaUsuario(id, nome, 'gestao_equipe', origem);
  }
