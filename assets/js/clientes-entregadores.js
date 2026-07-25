// /assets/js/clientes-entregadores.js
// Logica de Clientes e Entregadores/Motoboys, extraida do index.html (Etapa 7).
// Dependem de globais do script principal: sb, restauranteId, clientesCache, entregadoresCache,
// VEICULO_LABEL, e das funcoes showToast/formatMoeda/formatData/diaComercialData.
// So chamadas apos o script principal rodar. Continuam globais (sem type=module).

  async function loadClientes() {
    const { data: clientes, error } = await sb.from('clientes')
      .select('id, nome, telefone')
      .eq('restaurante_id', restauranteId)
      .order('nome', { ascending: true });
    if (error) { showToast('Erro ao carregar clientes', error.message); return; }

    const { data: pedidosCliente } = await sb.from('pedidos')
      .select('cliente_id, total, criado_em')
      .eq('restaurante_id', restauranteId);

    const stats = {};
    (pedidosCliente || []).forEach(p => {
      if (!p.cliente_id) return;
      if (!stats[p.cliente_id]) stats[p.cliente_id] = { qtd: 0, total: 0, ultimo: null };
      stats[p.cliente_id].qtd += 1;
      stats[p.cliente_id].total += Number(p.total);
      if (!stats[p.cliente_id].ultimo || new Date(p.criado_em) > new Date(stats[p.cliente_id].ultimo)) {
        stats[p.cliente_id].ultimo = p.criado_em;
      }
    });

    clientesCache = (clientes || []).map(c => ({ ...c, stats: stats[c.id] || { qtd: 0, total: 0, ultimo: null } }));
    renderClientesTable();
  }

  function renderClientesTable() {
    const busca = (document.getElementById('clienteBusca')?.value || '').trim().toLowerCase();
    const filtrados = clientesCache.filter(c =>
      !busca || c.nome.toLowerCase().includes(busca) || (c.telefone || '').includes(busca)
    );

    const tbody = document.getElementById('clientesTableBody');
    if (filtrados.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state"><div class="ic">👥</div><h4>Nenhum cliente encontrado</h4></div></td></tr>`;
      return;
    }
    tbody.innerHTML = filtrados.map(c => `
      <tr>
        <td data-label="Nome"><b>${c.nome}</b></td>
        <td data-label="Telefone">${c.telefone || '—'}</td>
        <td data-label="Pedidos">${c.stats.qtd}</td>
        <td data-label="Total gasto">${formatMoeda(c.stats.total)}</td>
        <td data-label="Último pedido">${c.stats.ultimo ? formatData(c.stats.ultimo) : '—'}</td>
        <td data-label="Ações"><div class="row-actions"><button onclick='openClienteEdit(${JSON.stringify({ id: c.id, nome: c.nome, telefone: c.telefone })})'>Editar</button></div></td>
      </tr>`).join('');
  }

  function openClienteEdit(c) {
    document.getElementById('cliId').value = c.id;
    document.getElementById('cliNome').value = c.nome || '';
    document.getElementById('cliTelefone').value = c.telefone || '';
    document.getElementById('clienteModalBg').classList.add('show');
  }

  function closeClienteEdit() { document.getElementById('clienteModalBg').classList.remove('show'); }

  async function submitClienteEdit() {
    const id = document.getElementById('cliId').value;
    const nome = document.getElementById('cliNome').value.trim();
    const telefone = document.getElementById('cliTelefone').value.trim();
    if (!nome) { showToast('Faltou o nome', 'Informe o nome do cliente.'); return; }

    const { error } = await sb.from('clientes').update({ nome, telefone }).eq('id', id);
    if (error) { showToast('Erro ao salvar', error.message); return; }
    closeClienteEdit();
    showToast('Cliente atualizado', nome);
    await loadClientes();
  }

  // Colspan dos estados da tabela: 8 colunas para dono/gerente (coluna "Liberação de hoje"
  // visível), 7 para os demais papéis (classe sem-liberacao-diaria oculta a coluna).
  function colspanEntregadores() {
    const tabela = document.getElementById('tabelaEntregadores');
    return (tabela && tabela.classList.contains('sem-liberacao-diaria')) ? 7 : 8;
  }

  async function loadEntregadores() {
    const tbody = document.getElementById('entregadoresTableBody');
    if (tbody) tbody.innerHTML = `<tr><td colspan="${colspanEntregadores()}"><div class="empty-state"><div class="ic">⏳</div><h4>Carregando entregadores...</h4></div></td></tr>`;

    // FK explícita: existem DUAS relações usuarios↔motoboys (motoboys_id_fkey = cadastro,
    // motoboys_liberado_por_fkey = auditoria da liberação). Sem o nome, o PostgREST
    // recusa o embed com "more than one relationship was found".
    const { data, error } = await sb.from('usuarios')
      .select('id, nome, telefone, ativo, motoboys!motoboys_id_fkey ( veiculo, placa, disponivel, liberado_em, liberado_por )')
      .eq('restaurante_id', restauranteId)
      .eq('role', 'motoboy')
      .order('nome', { ascending: true });
    if (error) {
      console.error('Falha ao carregar entregadores:', error);
      entregadoresCache = [];
      if (tbody) tbody.innerHTML = `<tr><td colspan="${colspanEntregadores()}"><div class="empty-state"><div class="ic">⚠️</div><h4>Não foi possível carregar os entregadores</h4><p>Verifique sua conexão e tente novamente.</p></div></td></tr>`;
      showToast('Erro ao carregar entregadores', 'Não foi possível carregar os entregadores. Tente novamente.');
      return;
    }
    entregadoresCache = data || [];

    if (entregadoresCache.length > 0) {
      const dataHoje = diaComercialData();
      await Promise.all(entregadoresCache.map(async (m) => {
        const [{ count: hoje }, { count: total }] = await Promise.all([
          sb.from('pedidos').select('id', { count: 'exact', head: true }).eq('motoboy_id', m.id).eq('status', 'entregue').eq('data_pedido', dataHoje),
          sb.from('pedidos').select('id', { count: 'exact', head: true }).eq('motoboy_id', m.id).eq('status', 'entregue')
        ]);
        m.entregasHoje = hoje || 0;
        m.entregasTotal = total || 0;
      }));
    }

    renderEntregadoresTable();
  }

  function renderEntregadoresTable() {
    const tbody = document.getElementById('entregadoresTableBody');
    if (entregadoresCache.length === 0) {
      tbody.innerHTML = `<tr><td colspan="${colspanEntregadores()}"><div class="empty-state"><div class="ic">🚚</div><h4>Nenhum entregador cadastrado</h4></div></td></tr>`;
      return;
    }
    tbody.innerHTML = entregadoresCache.map(e => {
      const mb = e.motoboys || {};
      return `
      <tr>
        <td data-label="Nome"><b>${e.nome}</b></td>
        <td data-label="Telefone">${e.telefone || '—'}</td>
        <td data-label="Veículo / Placa">${VEICULO_LABEL[mb.veiculo] || mb.veiculo || '—'}${mb.placa ? ' · ' + mb.placa : ''}</td>
        <td data-label="Status"><span class="status-pill ${e.ativo ? 'ativo' : 'inativo'}">${e.ativo ? 'Conta ativa' : 'Conta desativada'}</span></td>
        <td class="col-liberacao-hoje" data-label="Liberação de hoje">${celulaLiberacaoHoje(e, mb)}</td>
        <td data-label="Disponível">${mb.disponivel ? '🟢 Sim' : '⚪ Não'}</td>
        <td data-label="Entregas">${e.entregasHoje ?? 0} / ${e.entregasTotal ?? 0}</td>
        <td data-label="Ações">
          <div class="row-actions">
            <button onclick='openEntregador(${JSON.stringify({ id: e.id, nome: e.nome, telefone: e.telefone, veiculo: mb.veiculo, placa: mb.placa })})'>Editar</button>
            <button onclick="toggleEntregadorAtivo('${e.id}', ${e.ativo})">${e.ativo ? 'Desativar conta' : 'Reativar conta'}</button>
            <button onclick="abrirResetSenhaEntregador('${e.id}', '${e.nome.replace(/'/g, "\\'")}')">Redefinir senha</button>
            <button class="danger" onclick="removerEntregador('${e.id}', '${e.nome.replace(/'/g, "\\'")}')">Remover</button>
          </div>
        </td>
      </tr>`;
    }).join('');
  }

  // "Liberação de hoje" — usa a mesma função de dia comercial já usada no painel só pra
  // renderizar o estado. A segurança real é a RPC (e, na próxima etapa, as policies).
  function liberacaoDiariaValida(liberadoEm) {
    return !!liberadoEm && new Date(liberadoEm) >= inicioDiaComercial();
  }

  function celulaLiberacaoHoje(e, mb) {
    if (!e.ativo) return `<span class="liberacao-status inativa">Conta desativada</span>`;

    if (liberacaoDiariaValida(mb.liberado_em)) {
      const horario = new Date(mb.liberado_em).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });
      return `
        <div class="liberacao-hoje">
          <span class="liberacao-status ligada">🟢 Ligado hoje</span>
          <span class="liberacao-horario">desde ${horario}</span>
          <button class="btn" onclick="toggleLiberacaoDiariaMotoboy('${e.id}', false, this)">Desligar hoje</button>
        </div>`;
    }

    return `
      <div class="liberacao-hoje">
        <span class="liberacao-status desligada">⚪ Não ligado hoje</span>
        <button class="btn primary" onclick="toggleLiberacaoDiariaMotoboy('${e.id}', true, this)">Ligar hoje</button>
      </div>`;
  }

  const liberacaoDiariaSalvandoIds = new Set();

  async function toggleLiberacaoDiariaMotoboy(motoboyId, liberar, btnEl) {
    if (liberacaoDiariaSalvandoIds.has(motoboyId)) return;
    if (currentUser?.role !== 'dono' && currentUser?.role !== 'gerente') return;

    if (!liberar && !confirm('Desligar este motoboy hoje? Ele perderá imediatamente o acesso às entregas até ser ligado novamente.')) return;

    liberacaoDiariaSalvandoIds.add(motoboyId);
    if (btnEl) btnEl.disabled = true;

    const { error } = await sb.rpc('definir_liberacao_diaria_motoboy', { p_motoboy_id: motoboyId, p_liberado: liberar });

    liberacaoDiariaSalvandoIds.delete(motoboyId);
    if (btnEl) btnEl.disabled = false;

    if (error) { showToast('Erro ao atualizar liberação', error.message); return; }

    showToast(
      liberar ? 'Motoboy ligado' : 'Motoboy desligado',
      liberar ? 'Ele já pode acessar as entregas de hoje.' : 'O acesso às entregas de hoje foi removido até a próxima liberação.'
    );
    await loadEntregadores();
  }

  function openEntregador(e) {
    document.getElementById('entregadorModalTitle').textContent = e ? 'Editar entregador' : 'Novo entregador';
    document.getElementById('entId').value = e ? e.id : '';
    document.getElementById('entNome').value = e ? e.nome : '';
    document.getElementById('entTelefone').value = e ? (e.telefone || '') : '';
    document.getElementById('entVeiculo').value = e ? (e.veiculo || 'moto') : 'moto';
    document.getElementById('entPlaca').value = e ? (e.placa || '') : '';
    document.getElementById('entSenha').value = '';
    // Senha só é definida na criação; editar entregador existente usa "Redefinir senha" separadamente.
    document.getElementById('entSenhaField').style.display = e ? 'none' : 'block';
    document.getElementById('entregadorModalBg').classList.add('show');
  }

  function closeEntregador() { document.getElementById('entregadorModalBg').classList.remove('show'); }

  // Mensagens controladas que a RPC criar_usuario_equipe emite de propósito para o usuário.
  // Qualquer outro erro (constraint, rede, bug) recebe mensagem genérica e vai só pro console.
  const MENSAGENS_RPC_EQUIPE = [
    'Você não tem permissão para criar usuários.',
    'Telefone é obrigatório (com DDD).',
    'Este telefone já está vinculado a outra conta de equipe.',
    'Já existe uma conta com este e-mail. Fale com o suporte do EAF Menu.',
    'Este telefone acabou de ser cadastrado. Atualize a tela e tente novamente.'
  ];
  function mensagemErroCriarEntregador(error) {
    const msg = error?.message || '';
    if (MENSAGENS_RPC_EQUIPE.includes(msg) || msg.includes('já faz parte da equipe deste restaurante')) {
      return msg;
    }
    return 'Não foi possível criar o entregador. Tente novamente.';
  }

  async function submitEntregador() {
    const id = document.getElementById('entId').value || null;
    const nome = document.getElementById('entNome').value.trim();
    const telefone = document.getElementById('entTelefone').value.trim();
    const veiculo = document.getElementById('entVeiculo').value;
    const placa = document.getElementById('entPlaca').value.trim() || null;
    if (!nome) { showToast('Faltou o nome', 'Informe o nome do entregador.'); return; }
    if (!telefone) { showToast('Faltou o telefone', 'Informe o telefone (usado pra login no App do Motoboy).'); return; }

    if (id) {
      // Edição: atualiza nome/telefone (usuarios) e veículo/placa (motoboys)
      const { error: errUsuario } = await sb.from('usuarios').update({ nome, telefone }).eq('id', id);
      if (errUsuario) {
        console.error('Falha ao atualizar entregador:', errUsuario);
        showToast('Erro ao salvar', 'Não foi possível salvar as alterações. Tente novamente.');
        return;
      }
      const { error: errMoto } = await sb.from('motoboys').update({ veiculo, placa }).eq('id', id);
      if (errMoto) {
        console.error('Falha ao atualizar veículo do entregador:', errMoto);
        showToast('Erro ao salvar veículo', 'Não foi possível salvar o veículo. Tente novamente.');
        return;
      }
      closeEntregador();
      showToast('Entregador atualizado', nome);
      await loadEntregadores();
      return;
    }

    const senha = document.getElementById('entSenha').value;
    if (!senha || senha.length < 8) { showToast('Senha muito curta', 'Defina uma senha com pelo menos 8 caracteres.'); return; }

    const { error } = await sb.rpc('criar_usuario_equipe', {
      p_nome: nome,
      p_telefone: telefone,
      p_email: null,
      p_role: 'motoboy',
      p_senha: senha,
      p_veiculo: veiculo,
      p_placa: placa
    });
    if (error) {
      console.error('Falha ao criar entregador:', error);
      showToast('Erro ao criar entregador', mensagemErroCriarEntregador(error));
      return;
    }

    closeEntregador();
    showToast('Entregador criado', `${nome} já pode entrar no App do Motoboy com o telefone e a senha definida.`);
    await loadEntregadores();
  }

  async function toggleEntregadorAtivo(id, ativoAtual) {
    const { error } = await sb.from('usuarios').update({ ativo: !ativoAtual }).eq('id', id);
    if (error) { showToast('Erro', error.message); return; }
    await loadEntregadores();
  }

  async function removerEntregador(id, nome) {
    if (!confirm(`Remover ${nome} da equipe de entrega? Isso apaga o acesso e a conta por completo — não dá pra desfazer.`)) return;
    const { error } = await sb.rpc('remover_usuario_equipe', { p_usuario_id: id });
    if (error) { showToast('Erro ao remover', error.message); return; }
    showToast('Entregador removido', nome);
    await loadEntregadores();
  }

  function abrirResetSenhaEntregador(id, nome) {    const novaSenha = prompt(`Nova senha de acesso para ${nome} (mín. 8 caracteres):`);
    if (novaSenha === null) return;
    if (novaSenha.trim().length < 8) { showToast('Senha muito curta', 'Use pelo menos 8 caracteres.'); return; }
    redefinirSenhaEntregador(id, novaSenha.trim(), nome);
  }

  async function redefinirSenhaEntregador(id, novaSenha, nome) {
    const { error } = await sb.rpc('redefinir_senha_usuario', { p_usuario_id: id, p_nova_senha: novaSenha });
    if (error) { showToast('Erro ao redefinir senha', error.message); return; }
    showToast('Senha redefinida', `Nova senha de ${nome} definida.`);
  }

  // Permissão do restaurante para o motoboy reorganizar a ordem das entregas na rota (só dono altera).
  // Não controla acesso a GPS/navegação nem à rota com várias entregas — essas ficam sempre disponíveis.
  let roteirizacaoSalvando = false;

  function renderRoteirizacaoSwitch() {
    const switchEl = document.getElementById('roteirizacaoSwitch');
    const labelEl = document.getElementById('roteirizacaoStatusLabel');
    if (!switchEl) return;
    const ativa = !!restauranteInfo?.roteirizacao_motoboy_ativa;
    switchEl.classList.toggle('on', ativa);
    if (labelEl) labelEl.textContent = ativa ? 'Ativada' : 'Desativada';
  }

  async function toggleRoteirizacaoMotoboy() {
    if (roteirizacaoSalvando || currentUser?.role !== 'dono') return;

    const ativoAtual = !!restauranteInfo?.roteirizacao_motoboy_ativa;
    const novoValor = !ativoAtual;
    if (ativoAtual && !confirm('Os motoboys continuarão usando a navegação, mas não poderão alterar a ordem das entregas. Continuar?')) return;

    roteirizacaoSalvando = true;
    const switchEl = document.getElementById('roteirizacaoSwitch');
    switchEl.disabled = true;

    const { error } = await sb.rpc('definir_roteirizacao_motoboy', { p_ativa: novoValor });

    switchEl.disabled = false;
    roteirizacaoSalvando = false;

    if (error) { showToast('Erro ao atualizar', error.message); return; }

    restauranteInfo.roteirizacao_motoboy_ativa = novoValor;
    renderRoteirizacaoSwitch();
    showToast('Roteirização atualizada', novoValor ? 'Os motoboys já podem reorganizar a ordem das entregas.' : 'Os motoboys não poderão mais alterar a ordem das entregas.');
  }
