// App-shell cache: built assets are cache-first, page loads fall back to the cached shell offline.
// __VERSION__ is replaced at build time, so every deploy ships a changed worker the app can offer as an update.
const VERSION = '__VERSION__'
const CACHE = `midoku-${VERSION}`
const SHELL = ['/', '/manifest.webmanifest', '/icon.svg', ...[] /* __ASSETS__ */]
// Kept across deploys: downloaded chapters, cached covers/icons, and the app's offline data (cache.ts).
const DOWNLOADS = 'midoku-downloads'
const IMAGES = 'midoku-images'
const KEEP = new Set([CACHE, DOWNLOADS, IMAGES, 'midoku-data'])
const MAX_IMAGES = 800

self.addEventListener('install', (event) => {
  // No skipWaiting here: the new worker waits until the person taps Restart.
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)))
})

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k.startsWith('midoku-') && !KEEP.has(k)).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)

  // Suwayomi images. Downloaded pages come from the device; covers and icons are shown from the cache
  // at once and refreshed in the background, so they also show offline. Other pages go to the network.
  if (url.origin !== location.origin && url.pathname.startsWith('/api/v1/')) {
    const coverOrIcon = /\/thumbnail$|\/icon\//.test(url.pathname)
    event.respondWith((async () => {
      const saved = await (await caches.open(DOWNLOADS)).match(req.url)
      if (saved) return saved
      if (!coverOrIcon) return fetch(req)
      const cache = await caches.open(IMAGES)
      const hit = await cache.match(req.url)
      const refresh = fetch(req).then(async (res) => {
        if (res.ok) {
          await cache.put(req.url, res.clone())
          trimImages(cache)
        }
        return res
      })
      if (hit) {
        event.waitUntil(refresh.catch(() => {}))
        return hit
      }
      return refresh
    })())
    return
  }
  if (url.origin === location.origin && url.pathname.startsWith('/api/')) return

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone()
          caches.open(CACHE).then((c) => c.put('/', copy))
          return res
        })
        .catch(() => caches.match('/')),
    )
    return
  }

  if (url.origin === location.origin || url.hostname.endsWith('gstatic.com') || url.hostname.endsWith('googleapis.com')) {
    event.respondWith(
      caches.match(req).then((hit) =>
        hit ||
        fetch(req).then((res) => {
          if (res.ok || res.type === 'opaque') {
            const copy = res.clone()
            caches.open(CACHE).then((c) => c.put(req, copy))
          }
          return res
        }),
      ),
    )
  }
})

let trimming = false
/** Keeps the cover cache to MAX_IMAGES entries, dropping the oldest. */
async function trimImages(cache) {
  if (trimming) return
  trimming = true
  try {
    const keys = await cache.keys()
    for (const k of keys.slice(0, Math.max(0, keys.length - MAX_IMAGES))) await cache.delete(k)
  } finally {
    trimming = false
  }
}
