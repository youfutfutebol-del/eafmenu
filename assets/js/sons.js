// /assets/js/sons.js
// Sistema de sons compartilhado entre admin, motoboy e cliente.
// Usa arquivos MP3 reais (não beep sintetizado). Sem dependências externas,
// sem import/export, sem type="module" — funções ficam globais como as demais do projeto.

function tocarSomRepetido(caminho, vezes, intervaloMs) {
  intervaloMs = intervaloMs || 700;
  const tentativas = [];
  for (let i = 0; i < vezes; i++) {
    tentativas.push(new Promise((resolve) => {
      setTimeout(() => {
        // Tudo dentro do try: .play() pode ser bloqueado pelo navegador antes de
        // qualquer interação do usuário, e new Audio()/.play() também podem lançar
        // de forma síncrona em navegadores mais restritos — nenhum dos dois casos
        // pode deixar a Promise pendente, sempre resolve pra quem chamou reagir.
        try {
          const audio = new Audio(caminho);
          Promise.resolve(audio.play())
            .then(() => resolve(true))
            .catch(() => resolve(false));
        } catch (e) {
          resolve(false);
        }
      }, i * intervaloMs);
    }));
  }
  return Promise.all(tentativas);
}

// Admin: alerta de pedido novo (nunca em pedido manual). Uma trava evita duas
// sequências de 3 toques sobrepostas (ex.: dois INSERTs do Realtime chegando
// juntos, ou clique repetido em "Testar Alerta").
let alertaNovoPedidoTocando = false;

async function dispararAlertaNovoPedido() {
  if (alertaNovoPedidoTocando) return null;
  alertaNovoPedidoTocando = true;
  try {
    const resultados = await tocarSomRepetido('/assets/sounds/novo-pedido.mp3', 3);
    return resultados.some(Boolean);
  } finally {
    alertaNovoPedidoTocando = false;
  }
}

function tocarNovoPedido() {
  if (typeof soundOn !== 'undefined' && !soundOn) {
    atualizarStatusSom('desligado');
    return;
  }
  dispararAlertaNovoPedido().then((tocou) => {
    if (tocou === null) return; // já tinha uma sequência rodando, não sobrepõe
    atualizarStatusSom(tocou ? 'ativo' : 'bloqueado');
  });
}

// Botão "Testar Alerta": confirma quando o som funcionou, avisa quando o navegador
// bloqueou, e o próprio clique serve como interação pra liberar áudio depois.
async function testarAlertaSom() {
  const tocou = await dispararAlertaNovoPedido();
  if (tocou === null) {
    if (typeof showToast === 'function') showToast('Aguarde', 'O alerta já está tocando.');
    return;
  }
  if (tocou) {
    atualizarStatusSom((typeof soundOn === 'undefined' || soundOn) ? 'ativo' : 'desligado');
    if (typeof showToast === 'function') showToast('Som funcionando', 'Esse é o alerta que toca quando chega um pedido novo.');
  } else {
    atualizarStatusSom('bloqueado');
    if (typeof showToast === 'function') showToast('Áudio bloqueado pelo navegador', 'Clique em "Testar Alerta" de novo ou permita som para este site nas configurações do navegador.');
  }
}

const SOM_PEDIDOS_PREF_KEY = 'eafmenu_som_pedidos_ligado';

function lerPreferenciaSom() {
  try {
    const salvo = localStorage.getItem(SOM_PEDIDOS_PREF_KEY);
    return salvo === null ? true : salvo === '1';
  } catch (e) {
    return true;
  }
}

function setSoundOn(ligado) {
  try { localStorage.setItem(SOM_PEDIDOS_PREF_KEY, ligado ? '1' : '0'); } catch (e) {}
  // Ligar o switch não toca nada nem confirma o áudio — só volta a permitir o
  // alerta. "Som ativo" só aparece depois de uma reprodução real bem-sucedida
  // (ver tocarNovoPedido/testarAlertaSom).
  atualizarStatusSom(ligado ? 'bloqueado' : 'desligado');
}

function atualizarStatusSom(estado) {
  const texto = document.getElementById('soundStatusTxt');
  if (!texto) return;
  const legendas = { ativo: 'Som ativo', desligado: 'Som desligado', bloqueado: 'Toque para ativar o som' };
  texto.textContent = legendas[estado] || legendas.ativo;
  texto.className = 'sound-toggle__status sound-toggle__status--' + estado;
}

// Motoboy: toca 2 vezes + vibra quando uma entrega nova é atribuída a ele
// (nunca ao só abrir o app com entregas que já existiam).
function tocarNovaEntregaMotoboy() {
  tocarSomRepetido('/assets/sounds/nova-entrega.mp3', 2);
  if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
}

// Cliente: toca 1 vez quando o pedido dele muda especificamente para "saiu para entrega".
function tocarSaiuEntregaCliente() {
  tocarSomRepetido('/assets/sounds/saiu-entrega.mp3', 1);
}
