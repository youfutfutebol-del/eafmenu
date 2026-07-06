// /assets/js/dia-comercial.js
// Logica do 'dia comercial' (corte as 07:00), numeracao/reset diario de pedidos, extraida do index.html (Etapa 15).
// Dependem de globais/funcoes do script principal: HORA_RESET_PEDIDOS, diaComercialAtualKey,
// resetPedidosInterval, loadPedidos() (pedidos.js), showToast/formatHoraCurta (utils.js).
// So chamadas apos o script principal rodar. Continuam globais (sem type=module).

  function inicioDiaComercial(refDate) {
    const agora = refDate || new Date();
    const inicio = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate(), HORA_RESET_PEDIDOS, 0, 0, 0);
    if (agora.getHours() < HORA_RESET_PEDIDOS) {
      inicio.setDate(inicio.getDate() - 1);
    }
    return inicio;
  }

  function diaComercialKey(refDate) {
    return inicioDiaComercial(refDate).toISOString();
  }

  // Retorna a data (YYYY-MM-DD) do dia comercial atual — usada como chave do contador diário de pedidos.
  function diaComercialData(refDate) {
    const inicio = inicioDiaComercial(refDate);
    const y = inicio.getFullYear();
    const m = String(inicio.getMonth() + 1).padStart(2, '0');
    const d = String(inicio.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  function atualizarSubtituloPedidos() {
    const el = document.getElementById('pedidosSubtitle');
    if (!el) return;
    const inicio = inicioDiaComercial();
    el.textContent = 'Pedidos desde as ' + formatHoraCurta(inicio) + ' de hoje · reinicia automaticamente às ' + String(HORA_RESET_PEDIDOS).padStart(2,'0') + 'h';
  }

  function iniciarResetDiarioPedidos() {
    diaComercialAtualKey = diaComercialKey();
    atualizarSubtituloPedidos();
    if (resetPedidosInterval) clearInterval(resetPedidosInterval);
    resetPedidosInterval = setInterval(async () => {
      const chaveAgora = diaComercialKey();
      if (chaveAgora !== diaComercialAtualKey) {
        diaComercialAtualKey = chaveAgora;
        atualizarSubtituloPedidos();
        await loadPedidos();
        showToast('Painel reiniciado', 'Um novo dia comercial começou às ' + String(HORA_RESET_PEDIDOS).padStart(2,'0') + 'h.');
      }
    }, 60 * 1000);
  }
