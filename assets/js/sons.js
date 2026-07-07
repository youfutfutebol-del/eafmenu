// assets/js/sons.js
// Helper compartilhado de audio para Admin, Motoboy e Cliente.
// Sem base64, sem dependencia externa. So toca arquivos MP3 reais.

(function () {
  let audioDesbloqueado = false;

  // Chave usada no localStorage para o controle de som (usada quando nao existir um controle proprio na tela)
  const CHAVE_SOM = 'eaf_som_ativado';

  function isSoundOn() {
    if (typeof window.soundOn === 'boolean') return window.soundOn;

    const valor = localStorage.getItem(CHAVE_SOM);
    // padrao: som ligado, a menos que o usuario tenha desligado explicitamente
    return valor !== 'false';
  }

  function setSoundOn(ligado) {
    localStorage.setItem(CHAVE_SOM, ligado ? 'true' : 'false');
  }

  // Desbloqueio de audio no mobile: navegadores bloqueiam autoplay ate
  // o usuario interagir com a pagina. Toca um dos arquivos reais em volume 0
  // e imediatamente pausa - libera o contexto de audio sem o usuario ouvir nada.
  function desbloquearAudio() {
    if (audioDesbloqueado) return;

    try {
      const audio = new Audio('/assets/sounds/novo-pedido.mp3');
      audio.volume = 0;
      const promessa = audio.play();

      if (promessa && typeof promessa.then === 'function') {
        promessa
          .then(() => {
            audio.pause();
            audio.currentTime = 0;
            audio.volume = 1;
          })
          .catch(() => {});
      }
    } catch (e) {
      // ignora - apenas tentativa de desbloqueio
    }

    audioDesbloqueado = true;
  }

  document.addEventListener('click', desbloquearAudio, { once: true });
  document.addEventListener('touchstart', desbloquearAudio, { once: true });

  /**
   * Toca um arquivo de audio uma vez.
   * Nunca lanca erro para fora - falha de audio nao pode quebrar o app.
   */
  function tocarAudioArquivo(caminho, volume) {
    if (!isSoundOn()) return;
    try {
      const audio = new Audio(caminho);
      audio.volume = typeof volume === 'number' ? volume : 1.0;
      const promessa = audio.play();
      if (promessa && typeof promessa.catch === 'function') {
        promessa.catch((err) => {
          console.warn('[sons] nao foi possivel tocar audio:', caminho, err.message);
        });
      }
    } catch (err) {
      console.warn('[sons] erro ao tocar audio:', caminho, err.message);
    }
  }

  /**
   * Toca um arquivo N vezes com intervalos definidos (em ms).
   * Ex: tocarRepetido('a.mp3', [0, 550, 1100])
   */
  function tocarRepetido(caminho, intervalosMs, volume) {
    if (!isSoundOn()) return;
    intervalosMs.forEach((atraso) => {
      setTimeout(() => tocarAudioArquivo(caminho, volume), atraso);
    });
  }

  // ---- Funcoes especificas por contexto ----

  function tocarNovoPedido() {
    tocarRepetido('/assets/sounds/novo-pedido.mp3', [0, 550, 1100]);
  }

  function tocarNovaEntregaMotoboy() {
    tocarRepetido('/assets/sounds/nova-entrega.mp3', [0, 450]);
    try {
      if (navigator.vibrate) {
        navigator.vibrate([250, 100, 250]);
      }
    } catch (e) {
      // ignora - vibracao nao suportada
    }
  }

  function tocarSaiuEntregaCliente() {
    tocarAudioArquivo('/assets/sounds/saiu-entrega.mp3');
  }

  // Exposto globalmente para uso simples em pedidos.js / motoboy / cliente
  window.tocarAudioArquivo = tocarAudioArquivo;
  window.tocarNovoPedido = tocarNovoPedido;
  window.tocarNovaEntregaMotoboy = tocarNovaEntregaMotoboy;
  window.tocarSaiuEntregaCliente = tocarSaiuEntregaCliente;
  window.isSoundOn = isSoundOn;
  window.setSoundOn = setSoundOn;
})();
