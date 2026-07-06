// /assets/js/equipe.js
// Logica da aba Gestao de Equipe, extraida do index.html (Etapa 10).
// Dependem de globais do script principal: sb, restauranteId, currentUser, equipeCache,
// convitesCache, ROLE_LABEL, e da funcao showToast (utils.js). So chamadas apos o script
// principal rodar. Continuam globais (sem type=module).

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
          <td data-label="Nome"><b>${u.nome}</b></td>
          <td data-label="Telefone">${u.telefone || u.email || '—'}</td>
          <td data-label="Cargo"><span class="status-pill ativo">${ROLE_LABEL[u.role] || u.role}</span></td>
          <td data-label="Status">
            <span class="status-pill ${u.ativo ? 'ativo' : 'inativo'}">${u.ativo ? 'Ativo' : 'Desativado'}</span>
          </td>
          <td data-label="Ações">
            <div class="row-actions">
              <select onchange="mudarRole('${u.id}', this.value)" style="border:1px solid var(--border); border-radius:7px; padding:5px 8px; font-size:11.5px;" ${u.id === currentUser.id ? 'disabled' : ''}>
                ${Object.keys(ROLE_LABEL).map(r => `<option value="${r}" ${r === u.role ? 'selected' : ''}>${ROLE_LABEL[r]}</option>`).join('')}
              </select>
              ${u.id === currentUser.id ? '' : `<button onclick="toggleAtivoUsuario('${u.id}', ${u.ativo})">${u.ativo ? 'Desligar acesso' : 'Liberar acesso'}</button>`}
              ${(u.id !== currentUser.id && currentUser.role === 'dono') ? `<button onclick="abrirResetSenhaEquipe('${u.id}', '${u.nome.replace(/'/g, "\\'")}')">Redefinir senha</button>` : ''}
              ${u.id === currentUser.id ? '' : `<button class="danger" onclick="removerMembro('${u.id}', '${u.nome.replace(/'/g, "\\'")}')">Remover</button>`}
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
          <td data-label="Nome"><b>${c.nome}</b></td>
          <td data-label="E-mail">${c.email}</td>
          <td data-label="Cargo"><span class="status-pill inativo">${ROLE_LABEL[c.role] || c.role}</span></td>
          <td data-label="Ações"><div class="row-actions"><button class="danger" onclick="cancelarConvite('${c.id}')">Cancelar convite</button></div></td>
        </tr>`).join('');
    }
  }

  function abrirResetSenhaEquipe(id, nome) {
    const novaSenha = prompt(`Nova senha de acesso para ${nome} (mín. 4 caracteres):`);
    if (novaSenha === null) return;
    if (novaSenha.trim().length < 4) { showToast('Senha muito curta', 'Use pelo menos 4 caracteres.'); return; }
    redefinirSenhaEquipe(id, novaSenha.trim(), nome);
  }

  async function redefinirSenhaEquipe(id, novaSenha, nome) {
    const { error } = await sb.rpc('redefinir_senha_usuario', { p_usuario_id: id, p_nova_senha: novaSenha });
    if (error) { showToast('Erro ao redefinir senha', error.message); return; }
    showToast('Senha redefinida', `Nova senha de ${nome} definida.`);
  }

  async function toggleAtivoUsuario(id, ativoAtual) {
    const { error } = await sb.from('usuarios').update({ ativo: !ativoAtual }).eq('id', id);
    if (error) { showToast('Erro ao atualizar acesso', error.message); return; }
    showToast(ativoAtual ? 'Acesso desligado' : 'Acesso liberado', '');
    await loadEquipe();
  }

  function openMembro() {
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

  async function submitMembro() {
    const nome = document.getElementById('mbNome').value.trim();
    const telefone = document.getElementById('mbTelefone').value.trim();
    const email = document.getElementById('mbEmail').value.trim().toLowerCase();
    const senha = document.getElementById('mbSenha').value;
    const role = document.getElementById('mbRole').value;
    if (!nome) { showToast('Faltou o nome', 'Informe o nome da pessoa.'); return; }
    if (!telefone) { showToast('Faltou o telefone', 'Informe o telefone da pessoa (usado para o login).'); return; }
    if (!senha || senha.length < 4) { showToast('Senha muito curta', 'Defina uma senha com pelo menos 4 caracteres.'); return; }

    const { data, error } = await sb.rpc('criar_usuario_equipe', {
      p_nome: nome,
      p_telefone: telefone,
      p_email: email || null,
      p_role: role,
      p_senha: senha
    });

    if (error) { showToast('Erro ao criar usuário', error.message); return; }

    closeMembro();
    showToast(`Usuário "${nome}" criado`, `Login: ${telefone} · Senha: a que você definiu`);
    await loadEquipe();
  }

  async function mudarRole(id, novoRole) {
    const { error } = await sb.from('usuarios').update({ role: novoRole }).eq('id', id);
    if (error) { showToast('Erro ao mudar cargo', error.message); await loadEquipe(); return; }
    showToast('Cargo atualizado', '');
    await loadEquipe();
  }

  async function removerMembro(id, nome) {
    if (!confirm(`Remover ${nome} da equipe? Isso apaga o acesso e a conta por completo — não dá pra desfazer.`)) return;
    const { error } = await sb.rpc('remover_usuario_equipe', { p_usuario_id: id });
    if (error) { showToast('Erro ao remover', error.message); return; }
    showToast('Membro removido', nome);
    await loadEquipe();
  }

  async function cancelarConvite(id) {
    const { error } = await sb.from('convites_equipe').delete().eq('id', id);
    if (error) { showToast('Erro ao cancelar', error.message); return; }
    showToast('Convite cancelado', '');
    await loadEquipe();
  }
