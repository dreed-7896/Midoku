import { useSyncExternalStore } from 'react'
import { authHeaders, getPages } from './suwayomi'

/**
 * Chapters saved on this device for offline reading. Page images go into Cache Storage keyed by their
 * server URL (the service worker and the reader both read them from there); the list of saved chapters
 * and their page URLs is kept in localStorage. Chapters are identified by source + chapter url, so a
 * download stays valid when the server's ids change.
 */
const CACHE = 'midoku-downloads'
const KEY = 'midoku.downloads'

export interface SavedChapter {
  entryId: string
  title: string
  label: string
  pages: string[]
  bytes: number
  at: number
}
export interface DownloadJob { key: string; entryId: string; title: string; label: string; remoteId: number }

export const chapterKey = (sourceId: string, url: string) => `${sourceId}|${url}`

let saved: Record<string, SavedChapter> = (() => { try { return JSON.parse(localStorage.getItem(KEY) ?? '{}') } catch { return {} } })()
let queue: DownloadJob[] = []
/** Share of pages fetched for the chapter being downloaded, 0–1. */
let active: { key: string; progress: number } | null = null
let failed: Record<string, string> = {}

interface Snapshot { saved: Record<string, SavedChapter>; queued: Set<string>; active: { key: string; progress: number } | null; failed: Record<string, string> }
let snapshot: Snapshot = { saved, queued: new Set(), active, failed }
const listeners = new Set<() => void>()
function emit() {
  snapshot = { saved, queued: new Set(queue.map((j) => j.key)), active, failed }
  listeners.forEach((l) => l())
}
function persist() {
  try { localStorage.setItem(KEY, JSON.stringify(saved)) } catch { /* the cached pages stay; the list lasts this session */ }
}

export const useDownloads = () => useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l) }, () => snapshot)
export const getSaved = (key: string): SavedChapter | undefined => saved[key]
export const isSaved = (key: string) => !!saved[key]
export const getSavedList = () => Object.values(saved)

/** Adds chapters to the download queue (already saved or queued ones are skipped). */
export function download(jobs: DownloadJob[]) {
  const skip = new Set([...queue.map((j) => j.key), ...Object.keys(saved), active?.key ?? ''])
  const fresh = jobs.filter((j) => !skip.has(j.key))
  if (!fresh.length) return 0
  fresh.forEach((j) => delete failed[j.key])
  queue.push(...fresh)
  // Ask the browser not to clear downloads under storage pressure.
  navigator.storage?.persist?.().catch(() => {})
  emit()
  void work()
  return fresh.length
}

export function cancel(key: string) {
  queue = queue.filter((j) => j.key !== key)
  emit()
}

let working = false
async function work() {
  if (working) return
  working = true
  try {
    while (queue.length) {
      const job = queue.shift()!
      active = { key: job.key, progress: 0 }
      emit()
      try {
        await saveChapter(job)
      } catch (e) {
        failed = { ...failed, [job.key]: (e as Error).message }
      }
      active = null
      emit()
    }
  } finally {
    working = false
  }
}

async function saveChapter(job: DownloadJob) {
  const pages = await getPages(job.remoteId)
  const cache = await caches.open(CACHE)
  let done = 0
  let bytes = 0
  const next = [...pages]
  const worker = async () => {
    while (next.length) {
      const url = next.shift()!
      if (!(await cache.match(url))) {
        const res = await fetch(url, { headers: authHeaders() })
        if (!res.ok) throw new Error(`Page failed (${res.status})`)
        const blob = await res.blob()
        bytes += blob.size
        await cache.put(url, new Response(blob, { headers: { 'content-type': res.headers.get('content-type') ?? 'image/jpeg' } }))
      }
      done++
      active = { key: job.key, progress: done / pages.length }
      emit()
    }
  }
  await Promise.all([worker(), worker(), worker()])
  saved = { ...saved, [job.key]: { entryId: job.entryId, title: job.title, label: job.label, pages, bytes, at: Date.now() } }
  persist()
}

export async function removeDownload(key: string) {
  const s = saved[key]
  if (!s) return
  const { [key]: _gone, ...rest } = saved
  saved = rest
  persist()
  emit()
  try {
    const cache = await caches.open(CACHE)
    await Promise.all(s.pages.map((u) => cache.delete(u)))
  } catch { /* pages already gone */ }
}

export async function removeAllDownloads() {
  queue = []
  saved = {}
  persist()
  emit()
  try { await caches.delete(CACHE) } catch { /* nothing saved */ }
}

/** A saved page as a blob URL (the caller revokes it). */
export async function savedPageUrl(url: string): Promise<string | undefined> {
  try {
    const res = await (await caches.open(CACHE)).match(url)
    return res ? URL.createObjectURL(await res.blob()) : undefined
  } catch {
    return undefined
  }
}

export const savedBytes = () => Object.values(saved).reduce((n, s) => n + s.bytes, 0)
