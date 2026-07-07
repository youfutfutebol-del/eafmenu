// /assets/js/sons.js
// Sistema de sons compartilhado entre admin, motoboy e cliente.
// Usa arquivos MP3 reais (não beep sintetizado). Sem dependências externas,
// sem import/export, sem type="module" — funções ficam globais como as demais do projeto.

function tocarSomRepetido(caminho, vezes, intervaloMs) {
  intervaloMs = intervaloMs || 700;
  for (let i = 0; i < vezes; i++) {
    setTimeout(() => {
      const audio = new Audio(caminho);
      // .play() pode ser bloqueado pelo navegador antes de qualquer interação do usuário
      // (login já costuma contar como interação) — falha silenciosa, sem quebrar a tela.
      audio.play().catch(() => {});
    }, i * intervaloMs);
  }
}

// Admin: toca 3 vezes quando chega pedido novo vindo do cliente/cardápio (nunca em pedido manual).
function tocarNovoPedido() {
  tocarSomRepetido('/assets/sounds/novo-pedido.mp3', 3);
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
