import { useEffect, useSyncExternalStore } from 'react'
import { loadPageUpdates, loadReadMarks } from './db'
import { type Store } from './store'
import { getRecentChapters, toChapter } from './suwayomi'
import type { Entry } from './types'

/** A new chapter, or new pages in a chapter, of a library title. */
export interface Update {
  key: string
  entryId: string
  label: string
  detail: string
  at: number
  read: boolean
  pages?: { before: number; now: number }
  chapterId?: string
  sourceId?: string
  url?: string
}

const DAY = 86_400_000
const SEEN_KEY = 'midoku.updatesSeenAt'

/**
 * The Updates feed, shared by Home (badge and preview) and the Updates screen. Loaded once per session
 * and again after each update check; "seen" is when Updates was last opened on this device.
 */
interface Feed { items: Update[] | null; error?: string; seenAt: number; loading: boolean }
let feed: Feed = { items: null, seenAt: readSeen(), loading: false }
const listeners = new Set<() => void>()
const emit = (patch: Partial<Feed>) => { feed = { ...feed, ...patch }; listeners.forEach((l) => l()) }

function readSeen() {
  try {
    const v = Number(localStorage.getItem(SEEN_KEY))
    if (v) return v
    // First run: start from now, so the badge doesn't count months of old chapters.
    localStorage.setItem(SEEN_KEY, String(Date.now()))
  } catch { /* in memory only */ }
  return Date.now()
}
export function markUpdatesSeen() {
  const now = Date.now()
  try { localStorage.setItem(SEEN_KEY, String(now)) } catch { /* in memory only */ }
  emit({ seenAt: now })
}

async function fetchFeed(store: Store): Promise<Update[]> {
  const library = store.entries.filter((e) => e.inLibrary)
  if (store.server.status === 'off') {
    return library.flatMap((e) => e.chapters.filter((c) => c.isNew).map((c): Update => ({
      key: `${e.id}/${c.id}`, entryId: e.id, label: c.label, detail: c.title, at: Date.now() - e.updatedAgo * 3_600_000, read: c.read, chapterId: c.id,
    }))).sort((a, b) => b.at - a.at)
  }
  // Newest chapters of every followed source in one query, then Midoku's read marks for them.
  const byManga = new Map<number, Entry>()
  for (const e of library) for (const s of e.sources) if (s.following && s.mangaId != null) byManga.set(s.mangaId, e)
  const [recent, grown] = await Promise.all([getRecentChapters([...byManga.keys()]), loadPageUpdates()])
  const marks = await loadReadMarks(recent.map((c) => c.url))
  const readSet = new Set(marks.filter((m) => m.read).map((m) => `${m.entry_id}|${m.source_id}|${m.chapter_url}`))
  const out: Update[] = []
  for (const c of recent) {
    const e = byManga.get(c.mangaId)
    const at = Number(c.uploadDate)
    if (!e || !(at > 0)) continue
    const sourceId = e.sources.find((s) => s.mangaId === c.mangaId)?.sourceId ?? ''
    const ch = toChapter(c, sourceId)
    out.push({ key: `c${c.id}`, entryId: e.id, label: ch.label, detail: ch.title, at, read: readSet.has(`${e.dbId}|${sourceId}|${c.url}`), sourceId, url: c.url })
  }
  for (const g of grown) {
    const e = library.find((x) => x.dbId === g.entry_id)
    if (!e) continue
    // Opened since the pages arrived: already seen.
    const read = !!g.read_at && Date.parse(g.read_at) > Date.parse(g.pages_grew_at)
    out.push({
      key: `p${g.entry_id}/${g.chapter_url}`, entryId: e.id, label: g.chapter_label || 'Chapter', detail: `${g.pages_before} → ${g.pages} pages`,
      at: Date.parse(g.pages_grew_at), read, pages: { before: g.pages_before, now: g.pages }, sourceId: g.source_id, url: g.chapter_url,
    })
  }
  return out.filter((u) => u.at > Date.now() - 60 * DAY).sort((a, b) => b.at - a.at)
}

let running: Promise<void> | null = null
/** An update check ran since the feed was loaded. */
let checkedSince = false
export function reloadUpdates(store: Store) {
  if (running) return running
  emit({ loading: true, error: undefined })
  running = fetchFeed(store)
    .then((items) => emit({ items, loading: false }))
    .catch((e: Error) => emit({ error: e.message, loading: false }))
    .finally(() => { running = null })
  return running
}

/**
 * The feed, loaded when first used and after every update check. Read marks follow what's been read
 * since: a chapter read in this session counts as read here too.
 */
export function useUpdates(store: Store) {
  const f = useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l) }, () => feed)
  const ready = store.server.status !== 'loading' && store.server.status !== 'signin'
  const checking = !!store.updating
  useEffect(() => {
    if (checking) { checkedSince = true; return }
    if (ready && (!feed.items || checkedSince)) { checkedSince = false; void reloadUpdates(store) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, checking])
  const readNow = (u: Update) => {
    const e = store.entry(u.entryId)
    // A chapter can be one version of a slot (linked sources): its read mark is the slot's.
    const c = e?.chapters.find((x) => (u.chapterId ? x.id === u.chapterId
      : (x.sourceId === u.sourceId && x.sourceUrl === u.url) || !!x.alts?.some((a) => a.sourceId === u.sourceId && a.url === u.url)))
    if (!c) return u.read
    return u.pages ? !c.newPages && (u.read || c.read) : c.read
  }
  const items = f.items?.map((u) => ({ ...u, read: readNow(u) })) ?? null
  const unseen = items?.filter((u) => u.at > f.seenAt && !u.read).length ?? 0
  return { items, error: f.error, loading: f.loading, seenAt: f.seenAt, unseen }
}
