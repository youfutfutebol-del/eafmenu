// /assets/js/app-ui.js
// Funcoes pequenas de interface/PWA (drawer mobile, abrir apps irmaos, som, instalacao,
// service worker), extraidas do index.html (Etapa 14).
// Dependem de globais do script principal: restauranteSlugAtual, soundOn, deferredInstallPrompt,
// switchView() e showToast (utils.js). So chamadas apos o script principal rodar,
// exceto os listeners/registro de SW, que sao seguros de rodar no carregamento do proprio arquivo
// (nao dependem de sb/currentUser/estado do restaurante). Continuam globais (sem type=module).

  function openDrawer() {
    document.getElementById('sidebarEl').classList.add('open');
    document.getElementById('drawerOverlay').classList.add('show');
  }

  function closeDrawer() {
    document.getElementById('sidebarEl').classList.remove('open');
    document.getElementById('drawerOverlay').classList.remove('show');
  }

  function abrirPwaMotoboy() {
    window.open('/motoboy/', '_blank');
  }

  function abrirPwaCliente() {
    if (!restauranteSlugAtual) {
      showToast('Configure o link primeiro', 'Vá em Personalizar Marca e defina o link (slug) do seu cardápio antes de abrir o app do cliente.');
      switchView('marca');
      return;
    }
    window.open('/cliente/?r=' + restauranteSlugAtual, '_blank');
  }

  function abrirSuporteEafFlow() {
    abrirWhatsapp('5541984213488', 'Olá, preciso de suporte ou tenho uma dúvida sobre o EAF Menu.');
  }

  function toggleSound() {
    soundOn = !soundOn;

    if (typeof setSoundOn === 'function') {
      setSoundOn(soundOn);
    }

    document.getElementById('soundSwitch')?.classList.toggle('on', soundOn);
  }

  function jaEstaInstalado() {
    return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  }

  function ehIOS() {
    return /iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) && !window.MSStream;
  }

  async function installApp() {
    if (deferredInstallPrompt) {
      deferredInstallPrompt.prompt();
      const { outcome } = await deferredInstallPrompt.userChoice;
      deferredInstallPrompt = null;
      document.getElementById('installBtnLogin')?.classList.remove('show');
      document.getElementById('installBtnApp')?.classList.remove('show');
      if (outcome === 'accepted') showToast('App instalado', 'O EAF Menu já está na sua tela inicial.');
      return;
    }

    if (ehIOS()) {
      alert('Pra instalar no iPhone:\n\n1. Toque no ícone de Compartilhar (o quadrado com uma seta ↑) na barra do Safari\n2. Escolha "Adicionar à Tela de Início"\n3. Toque em "Adicionar"');
    } else {
      alert('Toque no menu do navegador (⋮ ou similar) e escolha "Adicionar à tela inicial" ou "Instalar app".');
    }
  }

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
  });

  window.addEventListener('appinstalled', () => {
    document.getElementById('installBtnLogin')?.classList.remove('show');
    document.getElementById('installBtnApp')?.classList.remove('show');
  });

  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch((err) => console.warn('SW falhou:', err));
    });
  }

  // Botão temporário de teste de som real — só em ambiente local, remover depois de validar em produção.
  if (location.hostname === 'localhost') {
    const btnTestarSom = document.getElementById('btnTestarSomDev');
    if (btnTestarSom) btnTestarSom.style.display = 'inline-flex';
  }
