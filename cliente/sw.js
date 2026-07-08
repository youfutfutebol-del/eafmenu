const CACHE_NAME = 'eaf-cliente-v0.1.8';
const APP_SHELL = [
  '/cliente/',
  '/cliente/index.html',
  '/cliente/manifest.json',
  '/assets/js/whatsapp.js',
  '/icons/icon192.png',
  '/icons/icon512.png'
];
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).catch(() => {})
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
  const url = new URL(event.request.url);
  // nunca cachear chamadas de API ou Supabase — sempre dados frescos (pedidos, cardápio, status)
  if (
    url.pathname.startsWith('/api/') ||
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('viacep.com.br')
  ) {
    event.respondWith(fetch(event.request));
    return;
  }
  // app shell: network-first, cai pro cache se estiver offline
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone)).catch(() => {});
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
