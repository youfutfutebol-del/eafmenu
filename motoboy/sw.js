// Service worker minimalista do PWA do Motoboy.
// Propositalmente sem cache agressivo: o app ainda está em desenvolvimento
// ativo, e cache de conteúdo antigo causaria mais confusão do que ajuda.
// Isso só permite que o navegador reconheça o app como instalável (PWA).

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  // Passthrough: sempre busca da rede, sem interceptar/cachear respostas.
  event.respondWith(fetch(event.request));
});
