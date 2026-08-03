// EAF Menu — Service Worker do Restaurante
// Escopo restrito a /restaurante/ pelo local deste arquivo e pelo manifest.

const CACHE_PREFIX = 'eaf-restaurante-cache-';
const CACHE_NAME = 'eaf-restaurante-cache-v0.6.19';
const APP_SHELL = [
  '/restaurante/',
  '/manifest.json',
  '/assets/css/painel.css',
  '/assets/js/whatsapp.js',
  '/assets/js/utils.js',
  '/assets/js/sons.js',
  '/assets/js/auth.js',
  '/assets/js/pedidos-utils.js',
  '/assets/js/pedidos.js',
  '/assets/js/produtos-categorias.js',
  '/assets/js/promocoes.js',
  '/assets/js/clientes-entregadores.js',
  '/assets/js/financeiro-caixa.js',
  '/assets/js/relatorio-financeiro.js',
  '/assets/js/equipe.js',
  '/assets/js/marca.js',
  '/assets/js/recursos-planos.js',
  '/assets/js/pedido-manual.js',
  '/assets/js/status-loja.js',
  '/assets/js/notificacoes.js',
  '/assets/js/app-ui.js',
  '/assets/js/dia-comercial.js',
  '/icons/icon192.png',
  '/icons/icon512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  if (request.url.includes('supabase.co') || request.url.includes('/api/')) return;
  if (request.method !== 'GET') return;

  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy)).catch(() => {});
        }
        return response;
      })
      .catch(() => caches.match(request).then((cached) => cached || caches.match('/restaurante/')))
  );
});
