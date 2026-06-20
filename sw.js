/* EduManager Cloud — service worker
   Strategy:
   - HTML/navigation: NETWORK-FIRST. When online you always get the freshest app
     (so GitHub/Netlify updates appear automatically); when offline you get the
     last cached page. This is what makes updates auto-apply without breaking offline.
   - Other GET assets (CDN libs, icon): CACHE-FIRST so the app runs fully offline
     after the first online visit.
   - Supabase API calls are never cached (always go to the network).
   Bump CACHE below if you ever need to force-clear caches for everyone. */
const CACHE = 'emc-cache-v4';
const CORE = ['./', './index.html', './manifest.json', './icon.svg'];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE).catch(() => {})));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.map(k => (k === CACHE ? null : caches.delete(k)))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (_) { return; }

  // Never cache the cloud database — always network.
  if (url.hostname.indexOf('supabase') !== -1) return;

  const isHTML = req.mode === 'navigate' ||
    (req.headers.get('accept') || '').indexOf('text/html') !== -1;

  if (isHTML) {
    // network-first → fresh app when online, cached app when offline
    e.respondWith(
      fetch(req)
        .then(r => { const cp = r.clone(); caches.open(CACHE).then(c => c.put('./index.html', cp)); return r; })
        .catch(() => caches.match('./index.html').then(r => r || caches.match('./')))
    );
    return;
  }

  // cache-first for static assets / CDN libraries
  e.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;
      return fetch(req).then(r => {
        if (r && r.status === 200) { const cp = r.clone(); caches.open(CACHE).then(c => c.put(req, cp)); }
        return r;
      }).catch(() => cached);
    })
  );
});
