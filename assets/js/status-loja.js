// /assets/js/status-loja.js
// Logica de status da loja (aberta/fechada) e horario de funcionamento, extraida do index.html (Etapa 13).
// Dependem de globais do script principal: horariosLojaAtual, statusLojaInterval.
// So chamadas apos o script principal rodar (iniciarStatusLoja e chamada dentro de boot()).
// Continuam globais (sem type=module).

  function agoraEmBrasiliaPainel() {
    const partes = new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/Sao_Paulo',
      weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false
    }).formatToParts(new Date());
    const mapaDia = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
    const diaSemana = mapaDia[partes.find(p => p.type === 'weekday').value];
    let hora = parseInt(partes.find(p => p.type === 'hour').value, 10);
    const minuto = parseInt(partes.find(p => p.type === 'minute').value, 10);
    if (hora === 24) hora = 0;
    return { diaSemana, minutosDoDia: hora * 60 + minuto };
  }

  function statusLojaDetalhado() {
    const horarios = horariosLojaAtual;
    if (!Array.isArray(horarios) || horarios.length === 0) {
      return { aberto: false, semConfiguracao: true, minutosRestantes: null, minutosParaAbrir: null };
    }

    const { diaSemana, minutosDoDia } = agoraEmBrasiliaPainel();
    const diaAnterior = (diaSemana + 6) % 7;
    const configHoje = horarios.find(h => h.dia === diaSemana);
    const configOntem = horarios.find(h => h.dia === diaAnterior);

    // Janela que começou ontem e cruza a meia-noite
    if (configOntem?.aberto && configOntem.abre && configOntem.fecha) {
      const [aH, aM] = configOntem.abre.split(':').map(Number);
      const [fH, fM] = configOntem.fecha.split(':').map(Number);
      const abreMin = aH * 60 + aM, fechaMin = fH * 60 + fM;
      if (fechaMin <= abreMin && minutosDoDia < fechaMin) {
        return { aberto: true, semConfiguracao: false, minutosRestantes: fechaMin - minutosDoDia, minutosParaAbrir: null };
      }
    }

    // Janela de hoje
    if (configHoje?.aberto && configHoje.abre && configHoje.fecha) {
      const [aH, aM] = configHoje.abre.split(':').map(Number);
      const [fH, fM] = configHoje.fecha.split(':').map(Number);
      const abreMin = aH * 60 + aM, fechaMin = fH * 60 + fM;
      const cruzaMeiaNoite = fechaMin <= abreMin;
      if (minutosDoDia >= abreMin && (cruzaMeiaNoite || minutosDoDia < fechaMin)) {
        const restantes = cruzaMeiaNoite ? (24 * 60 - minutosDoDia) + fechaMin : fechaMin - minutosDoDia;
        return { aberto: true, semConfiguracao: false, minutosRestantes: restantes, minutosParaAbrir: null };
      }
    }

    // Fechada agora: procura a próxima abertura nos próximos 7 dias
    for (let i = 0; i <= 7; i++) {
      const diaCheck = (diaSemana + i) % 7;
      const cfg = horarios.find(h => h.dia === diaCheck && h.aberto && h.abre);
      if (!cfg) continue;
      const [aH, aM] = cfg.abre.split(':').map(Number);
      const abreMin = aH * 60 + aM;
      if (i === 0 && minutosDoDia >= abreMin) continue;
      const minutosAteEsseDia = i * 24 * 60 + abreMin - minutosDoDia;
      if (minutosAteEsseDia > 0) {
        return { aberto: false, semConfiguracao: false, minutosRestantes: null, minutosParaAbrir: minutosAteEsseDia };
      }
    }
    return { aberto: false, semConfiguracao: false, minutosRestantes: null, minutosParaAbrir: null };
  }

  function atualizarStatusLoja() {
    const pill = document.getElementById('lojaStatusPill');
    const txt = document.getElementById('lojaStatusTxt');
    if (!pill || !txt) return;

    const info = statusLojaDetalhado();
    pill.className = 'pill-status ' + (info.aberto ? 'on' : 'off');

    if (info.semConfiguracao) {
      txt.textContent = 'Horário não configurado';
    } else if (info.aberto) {
      txt.textContent = (info.minutosRestantes != null && info.minutosRestantes <= 10)
        ? `Loja aberta · fecha em ${info.minutosRestantes} min`
        : 'Loja aberta';
    } else {
      txt.textContent = (info.minutosParaAbrir != null && info.minutosParaAbrir <= 10)
        ? `Loja fechada · abre em ${info.minutosParaAbrir} min`
        : 'Loja fechada';
    }
  }

  function iniciarStatusLoja() {
    atualizarStatusLoja();
    if (statusLojaInterval) clearInterval(statusLojaInterval);
    statusLojaInterval = setInterval(atualizarStatusLoja, 30 * 1000);
  }
