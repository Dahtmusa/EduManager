/* EduManager Cloud — service worker (FULLY ONLINE mode)
   No offline caching. Every request goes straight to the network so the app
   always shows live cloud data and the newest code. Any old caches from
   previous versions are deleted on activate. A pass-through fetch handler is
   kept only so the app stays installable as a home-screen app.
   If the device is offline, requests fail by design — the app requires a
   live internet connection. */
self.addEventListener('install', e => { self.skipWaiting(); });

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    try { const ks = await caches.keys(); await Promise.all(ks.map(k => caches.delete(k))); } catch (_) {}
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;          // let non-GET go straight to network
  e.respondWith(fetch(req));                  // network-only, never cache
});
