const CACHE = 'motoplay-v3';
const SHELL = [
  '/',
  '/index.html',
  '/config.js',
  '/callback.html',
  '/manifest.json',
  '/assets/logo.png',
  '/assets/icon-180.png',
  '/assets/icon-192.png',
  '/assets/icon-512.png',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Non intercettare: WebSocket, POST, chrome-extension
  if (url.protocol === 'ws:' || url.protocol === 'wss:') return;
  if (e.request.method !== 'GET') return;

  // Risorse esterne: network first, fallback cache, fallback 503
  if (url.hostname !== self.location.hostname) {
    e.respondWith(
      fetch(e.request).catch(() =>
        caches.match(e.request).then(cached =>
          cached || new Response('', { status: 503, statusText: 'Offline' })
        )
      )
    );
    return;
  }

  // App shell: cache first, poi network
  e.respondWith(
    caches.match(e.request).then(cached => {
      const network = fetch(e.request).then(res => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      });
      return cached || network;
    })
  );
});
