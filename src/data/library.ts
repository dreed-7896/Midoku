import type { ChapterStateRow, DbLibrary, EntryRow, EntrySourceRow, TabRow } from './db'
import { chapterKey, isSaved } from './downloads'
import { artFor, assetUrl, hoursSince, SChapter, toChapter } from './suwayomi'
import type { Chapter, Entry, EntrySource, LibraryTab } from './types'

/** Pure mapping between Midoku's database rows, Suwayomi data and the app's model. */

export const toTab = (r: TabRow): LibraryTab =>
  r.kind === 'smart' ? { id: r.id, kind: 'smart', name: r.name, filters: r.filters ?? { statuses: [], newOnly: false } } : { id: r.id, kind: r.kind, name: r.name } as LibraryTab

export const tabRow = (t: LibraryTab, position: number): TabRow =>
  ({ id: t.id, kind: t.kind, name: t.name, filters: t.kind === 'smart' ? t.filters : null, position })

const publishingOf = (p: string): Entry['publishing'] => (p === 'Completed' || p === 'Hiatus' ? p : 'Ongoing')

const toSource = (s: EntrySourceRow): EntrySource => ({
  sourceId: s.source_id,
  mangaId: s.server_manga_id ?? undefined,
  mangaUrl: s.manga_url,
  chapters: 0,
  following: s.following,
  main: s.is_main,
  name: s.source_name ?? undefined,
})

/** Library titles as stored; chapter totals are filled in from the server afterwards. */
export function entriesFromDb(lib: DbLibrary): Entry[] {
  const sourcesOf = new Map<string, EntrySourceRow[]>()
  for (const s of lib.sources) sourcesOf.set(s.entry_id, [...(sourcesOf.get(s.entry_id) ?? []), s])
  const tabsOf = new Map<string, string[]>()
  for (const t of lib.entryTabs) tabsOf.set(t.entry_id, [...(tabsOf.get(t.entry_id) ?? []), t.tab_id])
  const read = new Map(lib.progress.map((p) => [p.entry_id, p.read_count]))
  const appId = new Map<string, string>()
  const list: Entry[] = []
  for (const r of lib.entries) {
    const rows = sourcesOf.get(r.id) ?? []
    const main = rows.find((s) => s.is_main) ?? rows[0]
    if (main?.server_manga_id == null) continue
    const mangaId = main.server_manga_id
    appId.set(r.id, `s${mangaId}`)
    const readCount = read.get(r.id) ?? 0
    list.push({
      id: `s${mangaId}`,
      dbId: r.id,
      title: r.title,
      author: r.author,
      art: artFor(mangaId),
      coverPath: r.cover_path ?? undefined,
      coverUrl: assetUrl(r.cover_path),
      publishing: publishingOf(r.publishing),
      tabs: tabsOf.get(r.id) ?? [],
      tags: r.tags,
      description: r.description,
      sources: [main, ...rows.filter((s) => s !== main)].map((s) => ({ ...toSource(s), main: s === main })),
      parentId: r.parent_id ?? undefined,
      chapters: [],
      inLibrary: r.in_library,
      lastReadAgo: r.last_read_at ? hoursSince(Date.parse(r.last_read_at)) : undefined,
      updatedAgo: 1e6,
      addedOrder: r.added_at ? Date.parse(r.added_at) : 0,
      remote: { mangaId, sourceId: main.source_id, mangaUrl: main.manga_url, chaptersLoaded: false },
      counts: { total: readCount, unread: 0 },
    })
  }
  return list.map((e) => (e.parentId ? { ...e, parentId: appId.get(e.parentId) } : e))
}

export const entryRow = (e: Entry, dbId: string, parentDbId: string | null = null): EntryRow => ({
  id: dbId,
  title: e.title,
  author: e.author,
  cover_path: e.coverPath ?? null,
  description: e.description,
  tags: e.tags,
  publishing: e.publishing,
  parent_id: parentDbId,
  in_library: e.inLibrary,
  last_read_at: null,
})

export const sourceRow = (dbId: string, s: EntrySource): EntrySourceRow => ({
  entry_id: dbId,
  source_id: s.sourceId,
  manga_url: s.mangaUrl!,
  server_manga_id: s.mangaId ?? null,
  source_name: s.name ?? null,
  following: s.following,
  is_main: !!s.main,
})

export const stateRow = (dbId: string, c: Chapter): ChapterStateRow => ({
  entry_id: dbId,
  source_id: c.sourceId,
  chapter_url: c.sourceUrl!,
  chapter_number: c.number,
  page: c.page,
  read: c.read,
  bookmarked: c.bookmarked,
  removed: !!c.removed,
})

export type ChapterState = Pick<Chapter, 'page' | 'read' | 'bookmarked' | 'removed'> & { sourceId: string; sourceUrl?: string }
export const rowState = (r: ChapterStateRow): ChapterState =>
  ({ sourceId: r.source_id, sourceUrl: r.chapter_url, page: r.page, read: r.read, bookmarked: r.bookmarked, removed: r.removed })

/**
 * Puts saved reading state onto chapters. A slot holds one chapter per linked source; a state saved for
 * any of them applies, so switching the main source keeps what was read.
 */
export function applyStates(chapters: Chapter[], states: ChapterState[]): Chapter[] {
  const byKey = new Map(states.filter((s) => s.sourceUrl).map((s) => [chapterKey(s.sourceId, s.sourceUrl!), s]))
  if (!byKey.size) return chapters
  return chapters.map((c) => {
    const keys = c.alts?.length ? c.alts.map((a) => chapterKey(a.sourceId, a.url)) : c.sourceUrl ? [chapterKey(c.sourceId, c.sourceUrl)] : []
    const s = keys.map((k) => byKey.get(k)).find(Boolean)
    return s ? { ...c, page: s.page, read: s.read, bookmarked: s.bookmarked, removed: s.removed || undefined } : c
  })
}

export const statesOf = (chapters: Chapter[]): ChapterState[] =>
  chapters.filter((c) => c.sourceUrl).map((c) => ({ sourceId: c.sourceId, sourceUrl: c.sourceUrl, page: c.page, read: c.read, bookmarked: c.bookmarked, removed: c.removed }))

/** Marks chapters saved on this device. */
export const withDownloads = (chapters: Chapter[]): Chapter[] =>
  chapters.map((c) => {
    const d = !!c.sourceUrl && isSaved(chapterKey(c.sourceId, c.sourceUrl))
    return d === c.downloaded ? c : { ...c, downloaded: d }
  })

const slotKey = (n: number) => n.toFixed(3)

/**
 * Chapters from every linked source merged into one list: chapters with the same number share a slot
 * (shown as versions), and the main source's chapter is the one read. Sources earlier in the list win.
 */
export function mergeChapters(lists: { sourceId: string; chapters: SChapter[] }[]): Chapter[] {
  const slots = new Map<string, Chapter>()
  for (const { sourceId, chapters } of lists) {
    for (const raw of chapters) {
      const c = toChapter(raw, sourceId)
      const key = raw.chapterNumber >= 0 ? slotKey(raw.chapterNumber) : `${sourceId}:${raw.id}`
      const alt = { sourceId, url: raw.url, remoteId: raw.id }
      const slot = slots.get(key)
      if (slot) {
        slot.alts = [...(slot.alts ?? []), alt]
        slot.versions = slot.alts.length
      } else {
        slots.set(key, { ...c, alts: [alt], versions: 1 })
      }
    }
  }
  return [...slots.values()]
}

/** Library snapshot kept for offline launches. */
export interface LibrarySnapshot { entries: Entry[]; tabs: LibraryTab[] }
export const snapshotOf = (entries: Entry[], tabs: LibraryTab[]): LibrarySnapshot => ({
  entries: entries.filter((e) => e.dbId).map((e) => ({ ...e, chapters: [], remote: e.remote && { ...e.remote, chaptersLoaded: false } })),
  tabs,
})
