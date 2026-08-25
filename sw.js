/* EduManager Cloud — service worker (FULLY ONLINE, transparent)
   This worker does NOT intercept any network requests. Every request goes
   straight to the network exactly as if there were no service worker, so it
   can never interfere with loading the app or reaching the cloud database.
   It only deletes any caches left over from older versions. */
self.addEventListener('install', () => { self.skipWaiting(); });

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    try { const ks = await caches.keys(); await Promise.all(ks.map(k => caches.delete(k))); } catch (_) {}
    await self.clients.claim();
  })());
});
/* No 'fetch' handler on purpose → the browser handles all requests normally. */
