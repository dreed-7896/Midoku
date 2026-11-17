import { getSettings } from './settings'

/**
 * Keeps what the reader fetched on this device for a while, so reopening a chapter (and its thumbnails
 * and Pages grid) doesn't go to the server again:
 * - page lists (the addresses of a chapter's pages), for a few days, in localStorage;
 * - page images, in Cache Storage `midoku-pages`, up to a size set in Settings → Storage (oldest go first).
 * Downloaded chapters don't use this; they are kept separately (downloads.ts).
 */

const LISTS = 'midoku.pageLists'
const LIST_DAYS = 3
const MAX_LISTS = 400

type Lists = Record<string, { pages: string[]; at: number }>
let lists: Lists | null = null
const loadLists = (): Lists => {
  if (lists) return lists
  try { lists = JSON.parse(localStorage.getItem(LISTS) ?? '{}') as Lists } catch { lists = {} }
  return lists
}
const saveLists = () => {
  const all = loadLists()
  const keys = Object.keys(all)
  if (keys.length > MAX_LISTS) keys.sort((a, b) => all[a].at - all[b].at).slice(0, keys.length - MAX_LISTS).forEach((k) => delete all[k])
  try { localStorage.setItem(LISTS, JSON.stringify(all)) } catch { /* full or private mode: kept for this session */ }
}

/** A chapter's page list kept from the last few days, if any. Keys include the server, as the addresses do. */
export function cachedPageList(key: string): string[] | undefined {
  const hit = loadLists()[key]
  if (!hit) return undefined
  if (hit.at < Date.now() - LIST_DAYS * 86_400_000) { delete loadLists()[key]; saveLists(); return undefined }
  return hit.pages
}
export function keepPageList(key: string, pages: string[]) {
  if (!pages.length) return
  loadLists()[key] = { pages, at: Date.now() }
  saveLists()
}
export function forgetPageList(key: string) {
  delete loadLists()[key]
  saveLists()
}

// Page images

export const PAGES_CACHE = 'midoku-pages'
const INDEX = 'midoku.pageIndex'
type Index = Record<string, { size: number; at: number }>
let index: Index | null = null
const loadIndex = (): Index => {
  if (index) return index
  try { index = JSON.parse(localStorage.getItem(INDEX) ?? '{}') as Index } catch { index = {} }
  return index
}
let saveTimer: ReturnType<typeof setTimeout> | undefined
const saveIndex = () => {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => { try { localStorage.setItem(INDEX, JSON.stringify(loadIndex())) } catch { /* kept for this session */ } }, 500)
}

/** Bytes the kept page images take. */
export const pageCacheBytes = () => Object.values(loadIndex()).reduce((n, x) => n + x.size, 0)
const budget = () => getSettings().pageCacheMB * 1e6

/** A kept page image as a blob, if this device has it. */
export async function cachedPage(url: string): Promise<Blob | undefined> {
  if (!budget() || !loadIndex()[url]) return undefined
  try {
    const res = await (await caches.open(PAGES_CACHE)).match(url)
    if (!res) { delete loadIndex()[url]; saveIndex(); return undefined }
    loadIndex()[url].at = Date.now()
    saveIndex()
    return await res.blob()
  } catch {
    return undefined
  }
}

/** Keeps a page image; the oldest ones are dropped once the kept images pass the size set in Settings. */
export async function keepPage(url: string, blob: Blob) {
  const max = budget()
  if (!max || blob.size > max / 4) return
  try {
    const cache = await caches.open(PAGES_CACHE)
    await cache.put(url, new Response(blob, { headers: { 'Content-Type': blob.type || 'image/jpeg' } }))
    const idx = loadIndex()
    idx[url] = { size: blob.size, at: Date.now() }
    let total = pageCacheBytes()
    if (total > max) {
      for (const [k, v] of Object.entries(idx).sort((a, b) => a[1].at - b[1].at)) {
        if (total <= max * 0.9) break
        if (k === url) continue
        await cache.delete(k)
        delete idx[k]
        total -= v.size
      }
    }
    saveIndex()
  } catch {
    // Storage full or unavailable: the page just isn't kept.
  }
}

/** Removes every kept page image and page list. */
export async function clearPageCache() {
  index = {}
  lists = {}
  try { localStorage.removeItem(INDEX); localStorage.removeItem(LISTS) } catch { /* nothing kept */ }
  await caches.delete(PAGES_CACHE).catch(() => false)
}
