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

  async function loadEntregadores() {
    const { data, error } = await sb.from('usuarios')
      .select('id, nome, telefone, ativo, motoboys ( veiculo, placa, disponivel )')
      .eq('restaurante_id', restauranteId)
      .eq('role', 'motoboy')
      .order('nome', { ascending: true });
    if (error) { showToast('Erro ao carregar entregadores', error.message); return; }
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
      tbody.innerHTML = `<tr><td colspan="7"><div class="empty-state"><div class="ic">🚚</div><h4>Nenhum entregador cadastrado</h4></div></td></tr>`;
      return;
    }
    tbody.innerHTML = entregadoresCache.map(e => {
      const mb = e.motoboys || {};
      return `
      <tr>
        <td data-label="Nome"><b>${e.nome}</b></td>
        <td data-label="Telefone">${e.telefone || '—'}</td>
        <td data-label="Veículo / Placa">${VEICULO_LABEL[mb.veiculo] || mb.veiculo || '—'}${mb.placa ? ' · ' + mb.placa : ''}</td>
        <td data-label="Status"><span class="status-pill ${e.ativo ? 'ativo' : 'inativo'}">${e.ativo ? 'Ativo' : 'Desligado'}</span></td>
        <td data-label="Disponível">${mb.disponivel ? '🟢 Sim' : '⚪ Não'}</td>
        <td data-label="Entregas">${e.entregasHoje ?? 0} / ${e.entregasTotal ?? 0}</td>
        <td data-label="Ações">
          <div class="row-actions">
            <button onclick='openEntregador(${JSON.stringify({ id: e.id, nome: e.nome, telefone: e.telefone, veiculo: mb.veiculo, placa: mb.placa })})'>Editar</button>
            <button onclick="toggleEntregadorAtivo('${e.id}', ${e.ativo})">${e.ativo ? 'Desligar acesso' : 'Liberar acesso'}</button>
            <button onclick="abrirResetSenhaEntregador('${e.id}', '${e.nome.replace(/'/g, "\\'")}')">Redefinir senha</button>
            <button class="danger" onclick="removerEntregador('${e.id}', '${e.nome.replace(/'/g, "\\'")}')">Remover</button>
          </div>
        </td>
      </tr>`;
    }).join('');
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
      if (errUsuario) { showToast('Erro ao salvar', errUsuario.message); return; }
      const { error: errMoto } = await sb.from('motoboys').update({ veiculo, placa }).eq('id', id);
      if (errMoto) { showToast('Erro ao salvar veículo', errMoto.message); return; }
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
    if (error) { showToast('Erro ao criar entregador', error.message); return; }

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
