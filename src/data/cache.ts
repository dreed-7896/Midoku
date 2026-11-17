/**
 * Small JSON store on top of Cache Storage, for what the app needs offline: the last library snapshot
 * and each opened title with its chapters. Cache Storage holds far more than localStorage and
 * survives service worker updates (the worker only clears its own versioned shell cache).
 */
const DATA = 'midoku-data'
const path = (key: string) => `/__data/${encodeURIComponent(key)}`

export async function readJSON<T>(key: string): Promise<T | undefined> {
  try {
    const res = await (await caches.open(DATA)).match(path(key))
    return res ? ((await res.json()) as T) : undefined
  } catch {
    return undefined
  }
}

export async function writeJSON(key: string, value: unknown) {
  try {
    await (await caches.open(DATA)).put(path(key), new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } }))
  } catch {
    // Storage full or unavailable: the app keeps working online.
  }
}

export async function clearData() {
  try { await caches.delete(DATA) } catch { /* nothing to clear */ }
}

/** True when a failure looks like "no connection" rather than a real error. */
export function isOffline(e: unknown): boolean {
  if (typeof navigator !== 'undefined' && !navigator.onLine) return true
  const msg = e instanceof Error ? e.message : String(e)
  return e instanceof TypeError || /failed to fetch|networkerror|load failed|can't reach|network request failed/i.test(msg)
}

// Opened titles: a copy is kept for a few days after the title was last opened, so it can be read
// offline; titles with downloaded chapters keep theirs as long as the downloads exist.

const ENTRY_DAYS = 3
const ENTRY_PREFIX = 'entry/'
interface SavedEntry<T> { openedAt: number; entry: T }

export const writeEntryCopy = <T>(id: string, entry: T, openedAt: number) =>
  writeJSON(ENTRY_PREFIX + id, { openedAt, entry } satisfies SavedEntry<T>)

export async function readEntryCopy<T>(id: string, keep = false): Promise<T | undefined> {
  const saved = await readJSON<SavedEntry<T>>(ENTRY_PREFIX + id)
  if (!saved?.entry) return undefined
  return keep || Date.now() - saved.openedAt < ENTRY_DAYS * 86_400_000 ? saved.entry : undefined
}

/** Drops copies of titles not opened for ENTRY_DAYS, except the ids in keep (titles with downloads). */
export async function pruneEntryCopies(keep: Set<string>) {
  try {
    const cache = await caches.open(DATA)
    const prefix = path(ENTRY_PREFIX)
    for (const req of await cache.keys()) {
      const key = new URL(req.url).pathname
      if (!key.startsWith(prefix)) continue
      const id = decodeURIComponent(key.slice('/__data/'.length)).slice(ENTRY_PREFIX.length)
      if (keep.has(id)) continue
      const saved = (await (await cache.match(req))?.json().catch(() => null)) as SavedEntry<unknown> | null
      if (!saved || Date.now() - saved.openedAt >= ENTRY_DAYS * 86_400_000) await cache.delete(req)
    }
  } catch { /* nothing to prune */ }
}
