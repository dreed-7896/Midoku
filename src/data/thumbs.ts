import { chapterKey, getSaved, savedPageUrl } from './downloads'
import { shownPages } from './library'
import { cachedPageList, keepPageList } from './pageCache'
import { fetchImage, getPages, serverKey } from './suwayomi'
import type { Chapter } from './types'

/**
 * Chapter thumbnails, like native Midoku: a page of the chapter (the first, the first of a part, or one the
 * person picked) shrunk to 240 px wide and cropped to 2:3, kept in Cache Storage so it's made once per device.
 * Made only for chapters on screen, two at a time.
 */
const CACHE = 'midoku-thumbs'
const W = 240, H = 360
const urls = new Map<string, string>()
const pending = new Map<string, Promise<string | undefined>>()
const pageLists = new Map<number, Promise<string[]>>()
let active = 0
const waiting: (() => void)[] = []

const cacheUrl = (key: string) => `https://thumbs.midoku.invalid/${encodeURIComponent(key)}`

/** Which page of the whole chapter the thumbnail shows. */
export function thumbPage(c: Chapter): number {
  const m = c.thumb?.match(/^page:(\d+)$/)
  if (m) return Number(m[1])
  return c.range ? c.range[0] : 1
}

/** The key a chapter's thumbnail is stored under; changes when another page is picked. */
export const thumbKey = (c: Chapter) => (c.sourceUrl ? `${chapterKey(c.sourceId, c.sourceUrl)}#${thumbPage(c)}` : '')

/** Where a chapter's page list is kept on the device (the addresses include the server). */
export const pageListKey = (c: Chapter) => `${serverKey()}|${c.sourceUrl ? chapterKey(c.sourceId, c.sourceUrl) : c.remoteId}`

/**
 * Page addresses of a chapter: from the device when downloaded, else the list kept from the last few days
 * (pageCache.ts), else from the server. `fresh` asks the server again (and keeps the new list).
 */
export function chapterPages(c: Chapter, fresh = false): Promise<string[]> {
  const saved = c.sourceUrl ? getSaved(chapterKey(c.sourceId, c.sourceUrl)) : undefined
  if (saved) return Promise.resolve(saved.pages)
  if (!c.remoteId) return Promise.resolve([])
  const key = pageListKey(c)
  if (!fresh) {
    const kept = cachedPageList(key)
    if (kept) return Promise.resolve(kept)
  }
  let p = fresh ? undefined : pageLists.get(c.remoteId)
  if (!p) {
    p = getPages(c.remoteId).then((list) => { keepPageList(key, list); return list })
    p.catch(() => pageLists.delete(c.remoteId!))
    pageLists.set(c.remoteId, p)
  }
  return p
}

/** The pages a chapter (or part of one) shows, as whole-chapter page numbers. */
export const partPages = (c: Chapter, total: number) => (c.range ? shownPages(c, total) : Array.from({ length: total }, (_, i) => i + 1))

async function slot() {
  if (active >= 2) await new Promise<void>((r) => waiting.push(r))
  active++
}
function done() {
  active--
  waiting.shift()?.()
}

async function shrink(blob: Blob): Promise<Blob> {
  const bmp = await createImageBitmap(blob)
  const h = Math.max(1, Math.round((bmp.height * W) / Math.max(1, bmp.width)))
  const canvas = document.createElement('canvas')
  canvas.width = W
  canvas.height = Math.min(H, h)
  canvas.getContext('2d')!.drawImage(bmp, 0, 0, W, h)
  bmp.close()
  return new Promise((res, rej) => canvas.toBlob((b) => (b ? res(b) : rej(new Error('No thumbnail'))), 'image/jpeg', 0.72))
}

/** Returns a thumbnail already made on this device, without asking the server. */
export async function cachedThumb(c: Chapter): Promise<string | undefined> {
  const key = thumbKey(c)
  if (!key) return undefined
  if (urls.has(key)) return urls.get(key)
  const hit = await caches.open(CACHE).then((cache) => cache.match(cacheUrl(key))).catch(() => undefined)
  if (!hit) return undefined
  const u = URL.createObjectURL(await hit.blob())
  urls.set(key, u)
  return u
}

/** Makes (or finds) a chapter's thumbnail. */
export function chapterThumb(c: Chapter): Promise<string | undefined> {
  const key = thumbKey(c)
  if (!key || !c.remoteId) return Promise.resolve(undefined)
  const known = pending.get(key)
  if (known) return known
  const job = (async () => {
    const have = await cachedThumb(c)
    if (have) return have
    await slot()
    try {
      const pages = await chapterPages(c)
      const src = pages[thumbPage(c) - 1] ?? pages[0]
      if (!src) return undefined
      const local = c.sourceUrl && getSaved(chapterKey(c.sourceId, c.sourceUrl)) ? await savedPageUrl(src) : undefined
      const blob = local ? await fetch(local).then((r) => r.blob()) : await fetchImage(src)
      if (local) URL.revokeObjectURL(local)
      const small = await shrink(blob)
      await caches.open(CACHE).then((cache) => cache.put(cacheUrl(key), new Response(small, { headers: { 'Content-Type': 'image/jpeg' } }))).catch(() => {})
      const u = URL.createObjectURL(small)
      urls.set(key, u)
      return u
    } finally {
      done()
    }
  })()
  pending.set(key, job)
  job.catch(() => {}).finally(() => pending.delete(key))
  return job
}

/** Forgets made thumbnails (all of a title's chapters, or all). They're made again when shown. */
export async function resetThumbs(chapters?: Chapter[]) {
  const cache = await caches.open(CACHE).catch(() => undefined)
  if (!chapters) {
    urls.forEach((u) => URL.revokeObjectURL(u)); urls.clear()
    await caches.delete(CACHE).catch(() => {})
    return
  }
  const prefixes = chapters.filter((c) => c.sourceUrl).map((c) => `${chapterKey(c.sourceId, c.sourceUrl!)}#`)
  for (const [k, u] of urls) if (prefixes.some((p) => k.startsWith(p))) { URL.revokeObjectURL(u); urls.delete(k) }
  if (!cache) return
  for (const req of await cache.keys()) {
    const k = decodeURIComponent(new URL(req.url).pathname.slice(1))
    if (prefixes.some((p) => k.startsWith(p))) await cache.delete(req)
  }
}

/** Shrinks a picked picture to a thumbnail-sized JPEG data URL (kept in the database). */
export async function pictureThumb(file: File): Promise<string> {
  const small = await shrink(file)
  return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = () => rej(r.error); r.readAsDataURL(small) })
}
