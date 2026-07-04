// EAF Menu — Service Worker
// Estratégia simples: cache do "app shell" (o próprio index.html + ícones),
// sempre tentando a rede primeiro para os dados (Supabase), e caindo pro
// cache só quando estiver offline. Isso evita mostrar pedidos desatualizados.

const CACHE_NAME = 'eaf-menu-cache-v0.1.6';
const APP_SHELL = [
  '/index.html',
  '/manifest.json',
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
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  // Nunca cachear chamadas de API/Supabase — sempre precisam ser em tempo real
  if (request.url.includes('supabase.co') || request.url.includes('/api/')) {
    return;
  }

  // Só lida com GET; navegação e assets estáticos
  if (request.method !== 'GET') return;

  event.respondWith(
    fetch(request)
      .then((response) => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(request, copy)).catch(() => {});
        return response;
      })
      .catch(() => caches.match(request).then((cached) => cached || caches.match('/index.html')))
  );
});
