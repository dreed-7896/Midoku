import type { ChapterStateRow, DbLibrary, EntryRow, EntrySourceRow, InsertedRow, SplitRow, TabRow } from './db'
import { chapterKey, isSaved } from './downloads'
import { artFor, assetUrl, hoursSince, SChapter, toChapter } from './suwayomi'
import type { Chapter, ChapterVersion, CustomDetails, Entry, EntrySource, InsertedChapter, LibraryTab, PageLayout } from './types'

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
  segment: s.segment ?? 0,
  name: s.source_name ?? undefined,
})

/** Puts edited details over the server's; the server's are kept in `original`. */
export function applyCustom(e: Entry, custom: CustomDetails | undefined = e.custom): Entry {
  const o = e.original ?? { title: e.title, author: e.author, description: e.description, coverUrl: e.coverUrl }
  const c = custom ?? {}
  return {
    ...e,
    custom: c,
    original: o,
    title: c.title || o.title,
    author: c.author ?? o.author,
    description: c.description ?? o.description,
    coverUrl: c.cover || o.coverUrl,
  }
}

/** Ids for titles that have no source of their own (series made in Midoku). */
export const LOCAL = 'l'
const hashOf = (s: string) => [...s].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7)

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
    const base = {
      dbId: r.id,
      title: r.title,
      author: r.author,
      publishing: publishingOf(r.publishing),
      tabs: tabsOf.get(r.id) ?? [],
      tags: r.tags,
      description: r.description,
      parentId: r.parent_id ?? undefined,
      chapters: [],
      inLibrary: r.in_library,
      lastReadAgo: r.last_read_at ? hoursSince(Date.parse(r.last_read_at)) : undefined,
      updatedAgo: 1e6,
      addedOrder: r.added_at ? Date.parse(r.added_at) : 0,
      position: r.position ?? 0,
      renumber: !!r.renumber,
    }
    if (!rows.length) {
      // A series made in Midoku: it has titles inside it but no source of its own.
      appId.set(r.id, `${LOCAL}${r.id}`)
      list.push(applyCustom({ ...base, id: `${LOCAL}${r.id}`, art: artFor(hashOf(r.id)), sources: [], counts: { total: 0, unread: 0 } }, r.custom ?? {}))
      continue
    }
    if (main?.server_manga_id == null) continue
    const mangaId = main.server_manga_id
    appId.set(r.id, `s${mangaId}`)
    const readCount = read.get(r.id) ?? 0
    list.push(applyCustom({
      ...base,
      id: `s${mangaId}`,
      art: artFor(mangaId),
      coverPath: r.cover_path ?? undefined,
      coverUrl: assetUrl(r.cover_path),
      sources: [main, ...rows.filter((s) => s !== main)].map((s) => ({ ...toSource(s), main: s === main })),
      remote: { mangaId, sourceId: main.source_id, mangaUrl: main.manga_url, chaptersLoaded: false },
      counts: { total: readCount, unread: 0 },
    }, r.custom ?? {}))
  }
  return list.map((e) => (e.parentId ? { ...e, parentId: appId.get(e.parentId) } : e))
}

export const entryRow = (e: Entry, dbId: string, parentDbId: string | null = null): EntryRow => ({
  id: dbId,
  title: e.original?.title ?? e.title,
  author: e.original?.author ?? e.author,
  cover_path: e.coverPath ?? null,
  description: e.original?.description ?? e.description,
  custom: e.custom ?? {},
  position: e.position ?? 0,
  renumber: !!e.renumber,
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
  segment: s.segment ?? 0,
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
  preferred: !!c.preferred,
  position: c.order ?? null,
})

export type ChapterState = Pick<Chapter, 'page' | 'read' | 'bookmarked' | 'removed' | 'preferred' | 'order'> & { sourceId: string; sourceUrl?: string }
export const rowState = (r: ChapterStateRow): ChapterState =>
  ({ sourceId: r.source_id, sourceUrl: r.chapter_url, page: r.page, read: r.read, bookmarked: r.bookmarked, removed: r.removed, preferred: r.preferred, order: r.position == null ? undefined : Number(r.position) })

/** Shows a different version (physical chapter) of a slot. */
export const showVersion = (c: Chapter, v: ChapterVersion, preferred: boolean): Chapter =>
  ({ ...c, sourceId: v.sourceId, sourceUrl: v.url, remoteId: v.remoteId, title: v.title, preferred, pages: v.remoteId === c.remoteId ? c.pages : 0 })

/**
 * Puts saved reading state onto chapters. A slot holds one chapter per linked source; a state saved for
 * any of them applies, so switching the main source keeps what was read.
 */
export function applyStates(chapters: Chapter[], states: ChapterState[]): Chapter[] {
  const byKey = new Map(states.filter((s) => s.sourceUrl).map((s) => [chapterKey(s.sourceId, s.sourceUrl!), s]))
  if (!byKey.size) return chapters
  return chapters.map((c) => {
    const keys = c.alts?.length ? c.alts.map((a) => chapterKey(a.sourceId, a.url)) : c.sourceUrl ? [chapterKey(c.sourceId, c.sourceUrl)] : []
    // A version picked by hand is the one shown; otherwise the state of whichever version has one.
    const picked = c.alts?.find((a) => byKey.get(chapterKey(a.sourceId, a.url))?.preferred)
    const shown = picked && (picked.sourceId !== c.sourceId || picked.url !== c.sourceUrl) ? showVersion(c, picked, true) : picked ? { ...c, preferred: true } : c
    const s = (picked && byKey.get(chapterKey(picked.sourceId, picked.url))) || keys.map((k) => byKey.get(k)).find(Boolean)
    if (!s) return shown
    const moved = s.order != null ? { order: s.order, number: s.order, sourceNumber: c.sourceNumber ?? c.number } : {}
    return { ...shown, page: s.page, read: s.read, bookmarked: s.bookmarked, removed: s.removed || undefined, ...moved }
  })
}

export const statesOf = (chapters: Chapter[]): ChapterState[] =>
  chapters.filter((c) => c.sourceUrl).map((c) => ({ sourceId: c.sourceId, sourceUrl: c.sourceUrl, page: c.page, read: c.read, bookmarked: c.bookmarked, removed: c.removed, preferred: c.preferred, order: c.order }))

/** Marks chapters saved on this device. */
export const withDownloads = (chapters: Chapter[]): Chapter[] =>
  chapters.map((c) => {
    const d = !!c.sourceUrl && isSaved(chapterKey(c.sourceId, c.sourceUrl))
    return d === c.downloaded ? c : { ...c, downloaded: d }
  })

const slotKey = (n: number) => n.toFixed(3)

type SourceChapters = { sourceId: string; name?: string; segment?: number; chapters: SChapter[] }

/**
 * Chapters from every linked source merged into one list: chapters with the same number share a slot
 * (shown as versions), and the main source's chapter is the one read. Sources earlier in the list win.
 * Merged titles have segments (one per title merged in): each is merged on its own and they follow each
 * other, numbered by position. `renumber` names them Chapter 1, Chapter 2… instead of the sources' names.
 */
export function mergeChapters(lists: SourceChapters[], renumber = false): Chapter[] {
  const segments = [...new Set(lists.map((l) => l.segment ?? 0))].sort((a, b) => a - b)
  if (segments.length < 2 && !renumber) return mergeSegment(lists)
  const out = segments.flatMap((seg) => mergeSegment(lists.filter((l) => (l.segment ?? 0) === seg)).sort((a, b) => a.number - b.number))
  return out.map((c, i) => ({ ...c, number: i + 1, label: renumber ? `Chapter ${i + 1}` : c.label }))
}

function mergeSegment(lists: SourceChapters[]): Chapter[] {
  const slots = new Map<string, Chapter>()
  for (const { sourceId, name, chapters } of lists) {
    for (const raw of chapters) {
      const c = toChapter(raw, sourceId)
      const key = raw.chapterNumber >= 0 ? slotKey(raw.chapterNumber) : `${sourceId}:${raw.id}`
      const alt: ChapterVersion = { sourceId, url: raw.url, remoteId: raw.id, name: [name ?? sourceId, raw.scanlator].filter(Boolean).join(' · '), title: c.title }
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

// Inserted chapters

export const insertedFromRow = (r: InsertedRow): InsertedChapter => ({
  id: r.id, sourceId: r.source_id, mangaUrl: r.manga_url, chapterUrl: r.chapter_url, remoteId: r.server_chapter_id ?? undefined,
  number: Number(r.number), label: r.label, fromTitle: r.from_title, mode: r.mode === 'version' ? 'version' : 'chapter',
})
export const insertedRow = (dbId: string, i: InsertedChapter): InsertedRow => ({
  id: i.id, entry_id: dbId, source_id: i.sourceId, manga_url: i.mangaUrl, chapter_url: i.chapterUrl,
  server_chapter_id: i.remoteId ?? null, number: i.number, label: i.label, from_title: i.fromTitle, mode: i.mode ?? 'chapter',
})

const insertedChapter = (i: InsertedChapter): Chapter => ({
  id: `i${i.id}`, insertId: i.id, number: i.number, label: i.label, title: i.fromTitle, insertedFrom: i.fromTitle, date: '',
  pages: 0, page: 0, read: false, bookmarked: false, downloaded: false, isNew: false, versions: 1,
  sourceId: i.sourceId, sourceUrl: i.chapterUrl, remoteId: i.remoteId, layout: Math.abs(Math.round(i.number * 7)) % 4,
})

const ownVersion = (c: Chapter): ChapterVersion => ({ sourceId: c.sourceId, url: c.sourceUrl ?? '', remoteId: c.remoteId ?? 0, name: c.sourceId, title: c.title })

/**
 * Puts inserted chapters into a chapter list (keeping the state of ones already there). Pasted versions
 * join the chapter with the same number as another version; without one they are chapters of their own.
 */
export function withInserted(chapters: Chapter[], inserted: InsertedChapter[] = []): Chapter[] {
  const ids = new Set(inserted.map((i) => i.id))
  const out = chapters.filter((c) => !c.insertId || ids.has(c.insertId)).map((c) => {
    if (!c.alts?.some((a) => a.insertId && !ids.has(a.insertId))) return c
    const alts = c.alts.filter((a) => !a.insertId || ids.has(a.insertId))
    const reading = alts.find((a) => a.url === c.sourceUrl && a.sourceId === c.sourceId)
    const back = reading ? c : showVersion(c, alts[0], false)
    return { ...back, alts, versions: alts.length }
  })
  const have = new Set(out.flatMap((c) => [c.insertId, ...(c.alts?.map((a) => a.insertId) ?? [])]).filter(Boolean))
  for (const i of inserted) {
    if (have.has(i.id)) continue
    if (i.mode === 'version' && i.remoteId) {
      const k = out.findIndex((c) => !c.insertId && Math.abs(c.number - i.number) < 1e-6)
      if (k >= 0) {
        const c = out[k]
        const alts = [...(c.alts ?? [ownVersion(c)]), { sourceId: i.sourceId, url: i.chapterUrl, remoteId: i.remoteId, name: i.fromTitle || i.sourceId, title: i.label, insertId: i.id }]
        out[k] = { ...c, alts, versions: alts.length }
        continue
      }
    }
    out.push(insertedChapter(i))
  }
  return out
}

// Split chapters: shown as parts, while reading state stays on the whole (physical) chapter.

export const PART = '~'
export const physicalIdOf = (id: string) => id.split(PART)[0]

/** Page ranges of the parts, given the first page of every part after the first. */
export function partRanges(pages: number, breaks: number[]): [number, number][] {
  const starts = [1, ...breaks.filter((b) => b > 1 && (!pages || b <= pages)).sort((a, b) => a - b)]
  return starts.map((s, i) => [s, (starts[i + 1] ?? (pages || Number.MAX_SAFE_INTEGER) + 1) - 1])
}

/** A stored layout; copies saved before pages could be left out hold just the breaks. */
export const layoutOf = (v: PageLayout | number[] | undefined): PageLayout | undefined =>
  !v ? undefined : Array.isArray(v) ? { breaks: v, skip: [] } : v

/** Physical page numbers a chapter (or part) shows, out of `total` pages. */
export function shownPages(c: Pick<Chapter, 'range' | 'skip'>, total: number): number[] {
  const [a, b] = c.range ?? [1, total]
  const skip = new Set(c.skip ?? [])
  const out: number[] = []
  for (let n = a; n <= Math.min(b, total); n++) if (!skip.has(n)) out.push(n)
  return out
}

export function expandSplits(chapters: Chapter[], splits?: Record<string, PageLayout | number[]>): Chapter[] {
  if (!splits || !Object.keys(splits).length) return chapters
  return chapters.flatMap((c) => {
    const layout = c.sourceUrl ? layoutOf(splits[chapterKey(c.sourceId, c.sourceUrl)]) : undefined
    if (!layout || (!layout.breaks.length && !layout.skip.length)) return [c]
    const skip = layout.skip
    // Where the chapter's saved page sits among the shown pages of a range.
    const placed = (range: [number, number]): Pick<Chapter, 'page' | 'pages' | 'read' | 'part'> => {
      if (!c.pages) return { pages: 0, read: c.read, page: !c.read && c.page >= range[0] ? c.page - range[0] + 1 : 0, part: `From page ${range[0]}` }
      const shown = shownPages({ range, skip }, c.pages)
      const last = shown[shown.length - 1] ?? range[1]
      return {
        part: shown.length ? `Pages ${shown[0]}–${last}${shown.length < last - shown[0] + 1 ? ` · ${shown.length}` : ''}` : 'No pages',
        pages: shown.length,
        read: c.read || (c.page > 0 && c.page >= last),
        page: c.read || c.page < range[0] || c.page >= last ? 0 : shown.filter((n) => n <= c.page).length,
      }
    }
    if (!layout.breaks.length) {
      const range: [number, number] = [1, c.pages || Number.MAX_SAFE_INTEGER]
      return [{ ...c, range, skip, ...placed(range), read: c.read, part: undefined }]
    }
    const ranges = partRanges(c.pages, layout.breaks)
    return ranges.map(([a, b], i): Chapter => ({
      ...c,
      id: `${c.id}${PART}${i + 1}`,
      physicalId: c.id,
      range: [a, b],
      skip,
      number: c.number + i / 1000,
      label: `${c.label} · ${i + 1}/${ranges.length}`,
      ...placed([a, b]),
    }))
  })
}
