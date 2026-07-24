// EAF Menu — Service Worker
// Estratégia simples: cache do "app shell" (o próprio index.html + ícones),
// sempre tentando a rede primeiro para os dados (Supabase), e caindo pro
// cache só quando estiver offline. Isso evita mostrar pedidos desatualizados.

const CACHE_PREFIX = 'eaf-menu-cache-';
const CACHE_NAME = 'eaf-menu-cache-v0.6.6';
const APP_SHELL = [
  '/index.html',
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
  '/assets/js/pedido-manual.js',
  '/assets/js/status-loja.js',
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
      Promise.all(keys.filter((k) => k.startsWith(CACHE_PREFIX) && k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Nunca cachear chamadas de API/Supabase — sempre precisam ser em tempo real
  if (request.url.includes('supabase.co') || request.url.includes('/api/')) {
    return;
  }

  // Os PWAs filhos mantêm service workers e caches próprios.
  if (url.origin === self.location.origin && /^\/(admin|cliente|motoboy)\//.test(url.pathname)) return;

  // Só lida com GET; navegação e assets estáticos
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
      .catch(() => caches.match(request).then((cached) => cached || caches.match('/index.html')))
  );
});
