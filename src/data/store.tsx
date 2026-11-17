import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { isOffline, pruneEntryCopies, readEntryCopy, readJSON, writeEntryCopy, writeJSON } from './cache'
import {
  DbLibrary, deleteEntrySource, deleteInserted, mergeEntryRows, deleteSplit, deleteTabRow, flushWrites, loadEntryExtras, loadLibrary, onWriteError, saveChapterStates,
  notePageGrowth, saveEntry, saveEntrySource, saveInserted, saveSplit, saveTabs, setEntryTab, updateEntry, updateEntrySource, useAuth,
} from './db'
import type { ChapterStateRow } from './db'
import { chapterKey, download, DownloadJob, getSavedList, removeDownload, useDownloads } from './downloads'
import {
  applyCustom, applyStates, entriesFromDb, LOCAL, entryRow, expandSplits, insertedFromRow, shownPages, insertedRow, LibrarySnapshot, mergeChapters, physicalIdOf, rowState, showVersion,
  sourceRow, stateRow, statesOf, tabRow, toTab, withDownloads, withInserted,
} from './library'
import { ENTRIES, LIBRARY_TABS, SOURCES } from './mock'
import { recordLocalHistory } from './history'
import { useSettings } from './settings'
import { assetUrl, getChapters, getManga, getPages, getMangaSummaries, hoursSince, resolveManga, SChapter, SManga, toChapter, toEntry } from './suwayomi'
import type { Chapter, CustomDetails, ReaderMode, Entry, EntrySource, InsertedChapter, LibraryFilters, LibraryTab, PageLayout, Source, Status } from './types'

/*
 * Where things live:
 * - Sample data (no server address): kept on this device in localStorage.
 * - With a Suwayomi server: Suwayomi only supplies titles, chapters, pages and extensions and is never written to.
 *   The library, tabs, sources, reading progress and chapter marks live in Midoku's database (Supabase).
 * - Offline: the last library and every opened title are kept in Cache Storage (cache.ts), changes wait in
 *   the write queue (db.ts) and downloaded chapters are read from the device (downloads.ts).
 */

// Sample data layout on this device

interface SavedLayout { tabs: LibraryTab[]; memberships?: Record<string, string[]> }
const LAYOUT_KEY = 'midoku.library'
const SAMPLE_SCOPE = 'sample'

function loadSampleLayout(): SavedLayout | undefined {
  try {
    return JSON.parse(localStorage.getItem(LAYOUT_KEY) ?? '{}')[SAMPLE_SCOPE]
  } catch {
    return undefined
  }
}
function saveSampleLayout(layout: SavedLayout) {
  try {
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ [SAMPLE_SCOPE]: layout }))
  } catch {
    // Storage can be unavailable (private mode); the layout then lasts for this session only.
  }
}

function sampleState() {
  const saved = loadSampleLayout()
  const m = saved?.memberships
  return {
    tabs: saved?.tabs ?? LIBRARY_TABS,
    entries: m ? ENTRIES.map((e) => (m[e.id] ? { ...e, tabs: m[e.id] } : e)) : ENTRIES,
  }
}

const DEVICE_TABS = LIBRARY_TABS.filter((t) => t.kind === 'reading' || t.kind === 'all')

/** New chapters are looked for when the app opens, at most this often. */
const UPDATE_EVERY_MS = 6 * 3_600_000
const UPDATED_KEY = 'midoku.updatedAt'
/** When each title was last opened in this session; its offline copy is kept 3 days from then. */
const openedAt = new Map<string, number>()

const lastUpdateCheck = () => { try { return Number(localStorage.getItem(UPDATED_KEY)) || 0 } catch { return 0 } }

const newestUpload = (lists: { chapters: SChapter[] }[]) =>
  Math.max(0, ...lists.flatMap((l) => l.chapters.map((c) => Number(c.uploadDate) || 0)))

/** Details from the server for a library title: cover, chapter totals, newest upload. */
function enrich(e: Entry, m: SManga): Entry {
  const total = m.chapters?.totalCount ?? 0
  const read = e.counts ? e.counts.total - e.counts.unread : 0
  const cover = assetUrl(m.thumbnailUrl) || e.original?.coverUrl
  return applyCustom({
    ...e,
    original: e.original && { ...e.original, coverUrl: cover },
    coverUrl: e.original ? e.coverUrl : cover,
    updatedAgo: hoursSince(m.latestUploadedChapter?.uploadDate) ?? e.updatedAgo,
    sources: e.sources.map((x) => (x.main ? { ...x, chapters: total, name: m.source?.displayName ?? x.name, iconUrl: m.source?.iconUrl ? assetUrl(m.source.iconUrl) : x.iconUrl } : x)),
    counts: e.chapters.length ? e.counts : { total: Math.max(total, read), unread: Math.max(0, total - read) },
  })
}

// Store

type ServerState =
  /** Sample data, no server address. */
  | { status: 'off' }
  /** A server is set but the app password has not been entered. */
  | { status: 'signin' }
  | { status: 'loading' | 'ready' }
  /** where: the library (Midoku's database) or the Suwayomi server. */
  | { status: 'error'; error: string; where: 'library' | 'server' }

interface State {
  entries: Entry[]
  sources: Source[]
  queue: string[]
  tabs: LibraryTab[]
  updatesSeen: boolean
  toastMessage: string | null
  miniHidden: boolean
  server: ServerState
  /** The library shown is the copy saved on this device (no connection). */
  offline: boolean
  /** Progress of the check for new chapters. */
  updating: { done: number; total: number } | null
}

const initial: State = {
  ...sampleState(),
  sources: SOURCES,
  queue: ['salt-static', 'paper-tigers', 'night-bus', 'quiet-tide', 'low-orbit', 'glasswing'],
  updatesSeen: false,
  toastMessage: null,
  miniHidden: false,
  server: { status: 'off' },
  offline: false,
  updating: null,
}

const SAMPLE_QUEUE = initial.queue


/** Finds a title by app id, or by the server id of any of its linked sources. */
function findIn(entries: Entry[], id: string) {
  const hit = entries.find((e) => e.id === id)
  if (hit || !/^s\d+$/.test(id)) return hit
  const n = Number(id.slice(1))
  return entries.find((e) => e.sources.some((s) => s.mangaId === n))
}

function useActions(set: (fn: (s: State) => State) => void, get: () => State) {
  return useMemo(() => {
    const editEntry = (id: string, fn: (e: Entry) => Entry) =>
      set((s) => ({ ...s, entries: s.entries.map((e) => (e.id === id ? fn(e) : e)) }))
    let toastTimer: ReturnType<typeof setTimeout> | undefined
    const toast = (message: string) => {
      set((s) => ({ ...s, toastMessage: message }))
      clearTimeout(toastTimer)
      toastTimer = setTimeout(() => set((s) => ({ ...s, toastMessage: null })), 2200)
    }
    const find = (id: string) => findIn(get().entries, id)

    let warned = false
    /** Changes are saved in the database (through the write queue) only once the app password was entered. */
    const canSave = () => {
      const st = get().server.status
      if (st === 'off') return false
      if (st === 'signin') {
        if (!warned) toast('Enter the app password to keep your library')
        warned = true
        return false
      }
      return true
    }

    /** Saves the title in the database the first time it matters; returns its row id. */
    const ensureEntry = (id: string): string | undefined => {
      const e = find(id)
      if (!e || !canSave()) return undefined
      if (e.dbId) return e.dbId
      if (!e.remote) return undefined
      const dbId = crypto.randomUUID()
      editEntry(e.id, (x) => ({ ...x, dbId }))
      saveEntry(entryRow(e, dbId))
      e.sources.filter((s) => s.mangaUrl).forEach((s) => saveEntrySource(sourceRow(dbId, s)))
      return dbId
    }

    const saveChapters = (id: string, chapterIds: Set<string>, extra?: Partial<ChapterStateRow>) => {
      const dbId = ensureEntry(id)
      if (!dbId) return
      const rows = (find(id)?.chapters ?? []).filter((c) => chapterIds.has(c.id) && c.sourceUrl).map((c) => ({ ...stateRow(dbId, c), ...extra }))
      if (rows.length) saveChapterStates(rows)
    }

    const writeTab = (id: string) => {
      if (!canSave()) return
      const tabs = get().tabs
      const i = tabs.findIndex((t) => t.id === id)
      if (i >= 0) saveTabs([tabRow(tabs[i], i)])
    }
    const newTabId = (prefix: string) => (get().server.status !== 'off' ? crypto.randomUUID() : `${prefix}-${Date.now().toString(36)}`)

    /** Reading state, split chapters and inserted chapters from the database, for a saved title whose chapters are loaded. */
    const loadStates = async (id: string) => {
      const dbId = find(id)?.dbId
      if (!dbId || get().server.status === 'signin') return
      await loadEntryExtras(dbId)
        .then(({ states, splits, inserts }) => editEntry(id, (e) => {
          const inserted = inserts.map(insertedFromRow)
          return {
            ...e,
            inserted,
            splits: Object.fromEntries(splits.map((r) => [chapterKey(r.source_id, r.chapter_url), { breaks: r.breaks, skip: r.excluded ?? [] }])),
            chapters: withDownloads(applyStates(withInserted(e.chapters, inserted), states.map(rowState))),
          }
        }))
        .catch((e: Error) => { if (!isOffline(e)) toast(`Couldn't load reading progress: ${e.message}`) })
    }

    /**
     * Turns a change on shown chapters (which may be parts of a split chapter) into changes on the whole
     * chapters, where reading state lives. Reading part 1 moves the whole chapter's page past it;
     * only the last part marks the whole chapter read.
     */
    const toPhysical = (e: Entry, ids: Set<string>, patch: Partial<Chapter>) => {
      const shown = visibleChapters(e)
      const out = new Map<string, Partial<Chapter>>()
      for (const id of ids) {
        const part = shown.find((c) => c.id === id)
        if (!part?.range || !part.physicalId) { out.set(physicalIdOf(id), { ...out.get(physicalIdOf(id)), ...patch }); continue }
        const whole = e.chapters.find((c) => c.id === part.physicalId)
        if (!whole) continue
        const parts = shown.filter((c) => c.physicalId === whole.id)
        const last = parts[parts.length - 1]?.id === part.id
        const p: Partial<Chapter> = { ...patch }
        if (patch.read === true && !last) { delete p.read; p.page = Math.max(whole.page, part.range[1]) }
        if (patch.read === false) { p.read = false; p.page = Math.min(whole.page, part.range[0] - 1) }
        out.set(whole.id, { ...out.get(whole.id), ...p })
      }
      return out
    }

    /** Merges fresh server data into a title, keeping everything Midoku knows about it. */
    const mergeEntry = (fresh: Entry) =>
      set((s) => {
        const prev = findIn(s.entries, fresh.id)
        if (!prev) return { ...s, entries: [...s.entries, { ...fresh, chapters: withDownloads(fresh.chapters) }] }
        const next: Entry = applyCustom({
          ...fresh,
          original: undefined,
          custom: prev.custom,
          position: prev.position,
          renumber: prev.renumber,
          id: prev.id,
          dbId: prev.dbId,
          tabs: prev.tabs,
          inLibrary: prev.inLibrary,
          lastReadAgo: prev.lastReadAgo,
          parentId: prev.parentId,
          addedOrder: prev.addedOrder,
          // Linked sources are Midoku's; the server only refreshes the main source's name, icon and count.
          sources: prev.sources.length ? prev.sources.map((x) => {
            const f = fresh.sources.find((y) => y.sourceId === x.sourceId && y.mangaUrl === x.mangaUrl)
            return f ? { ...x, name: f.name ?? x.name, iconUrl: f.iconUrl ?? x.iconUrl, chapters: f.chapters || x.chapters } : x
          }) : fresh.sources,
          remote: prev.remote ? { ...fresh.remote!, mangaId: prev.remote.mangaId, sourceId: prev.remote.sourceId, mangaUrl: prev.remote.mangaUrl, chaptersLoaded: fresh.remote?.chaptersLoaded || prev.remote.chaptersLoaded } : fresh.remote,
          counts: fresh.counts && prev.counts
            ? { total: fresh.counts.total, unread: Math.max(0, fresh.counts.total - (prev.counts.total - prev.counts.unread)) }
            : fresh.counts,
          splits: prev.splits ?? fresh.splits,
          inserted: prev.inserted ?? fresh.inserted,
          chapters: fresh.remote?.chaptersLoaded ? withDownloads(applyStates(withInserted(fresh.chapters, prev.inserted ?? fresh.inserted), statesOf(prev.chapters))) : prev.chapters,
        })
        return { ...s, entries: s.entries.map((e) => (e === prev ? next : e)) }
      })

    /**
     * Loads a title's details and the chapters of every linked source from the server. Without a
     * connection the copy saved on this device is used. Returns whether the data is live or saved.
     */
    const loadEntry = async (id: string, refresh = false): Promise<'live' | 'saved'> => {
      const known = find(id)
      openedAt.set(known?.id ?? id, Date.now())
      const mangaId = known?.remote?.mangaId ?? Number(id.slice(1))
      try {
        const manga = await getManga(mangaId, refresh)
        const firstLoad = !find(id)?.remote?.chaptersLoaded
        mergeEntry(toEntry(manga))
        const e = find(id)!
        const sources = [...e.sources].sort((a, b) => Number(!!b.main) - Number(!!a.main)).filter((s) => s.mangaId != null)
        const lists = await Promise.all(sources.map((s, i) =>
          getChapters(s.mangaId!, refresh)
            .then((chapters) => ({ sourceId: s.sourceId, mangaUrl: s.mangaUrl, name: s.name, segment: s.segment, chapters }))
            // Only the main source has to answer; another source failing just leaves its versions out.
            .catch((err) => { if (i === 0) throw err; return null })))
        const ok = lists.filter((l): l is NonNullable<typeof l> => !!l)
        const fresh = toEntry(manga)
        mergeEntry({ ...fresh, chapters: mergeChapters(ok, e.renumber), remote: { ...fresh.remote!, chaptersLoaded: true } })
        editEntry(e.id, (x) => ({
          ...x,
          updatedAgo: hoursSince(newestUpload(ok)) ?? x.updatedAgo,
          sources: x.sources.map((s) => {
            const l = ok.find((y) => y.sourceId === s.sourceId && y.mangaUrl === s.mangaUrl)
            return l ? { ...s, chapters: l.chapters.length } : s
          }),
        }))
        if (firstLoad) await loadStates(e.id)
        return 'live'
      } catch (err) {
        if (!isOffline(err)) throw err
        const entryId = known?.id ?? id
        const hasDownloads = getSavedList().some((d) => d.entryId === entryId)
        const saved = await readEntryCopy<Entry>(entryId, hasDownloads)
        if (!saved) throw err
        // The saved copy carries its reading state; anything newer known here wins.
        mergeEntry({ ...saved, remote: saved.remote && { ...saved.remote, chaptersLoaded: true } })
        return 'saved'
      }
    }

    /** A title gets new chapters when one of its sources is followed (picked in Updates → Get new chapters). */
    const isFollowed = (e: Entry) => e.sources.some((s) => s.following && s.mangaId != null)
    /** Asks the server to look for new chapters on the library titles picked for it (followed sources only). */
    let checking = false
    const checkUpdates = async (quiet = false) => {
      if (checking || get().server.status === 'off') return
      const list = get().entries.filter((e) => e.inLibrary && e.dbId && e.remote && isFollowed(e))
      if (!list.length) { if (!quiet) toast('No titles get new chapters yet · pick them in Updates'); return }
      checking = true
      set((s) => ({ ...s, updating: { done: 0, total: list.length } }))
      let found = 0
      let grew = 0
      let failures = 0
      const jobs = [...list]
      const worker = async () => {
        while (jobs.length) {
          const e = jobs.shift()!
          try {
            // Followed sources are asked for new chapters; the others keep the chapters the server has.
            const sources = [...e.sources].sort((a, b) => Number(!!b.main) - Number(!!a.main)).filter((s) => s.mangaId != null)
            const lists = await Promise.all(sources.map((s) => getChapters(s.mangaId!, s.following).then((chapters) => ({ sourceId: s.sourceId, name: s.name, segment: s.segment, chapters }))))
            const merged = mergeChapters(lists, e.renumber)
            // The newest chapter can gain pages after it comes out. When the server has fetched its pages
            // before, they are fetched again and compared; more pages are noted for Updates.
            const main = lists[0]
            const latest = [...main.chapters].sort((a, b) => b.chapterNumber - a.chapterNumber || Number(b.uploadDate) - Number(a.uploadDate))[0]
            if (latest && latest.pageCount > 0 && e.dbId) {
              const now = await getPages(latest.id).then((p) => p.length).catch(() => 0)
              if (now > latest.pageCount) {
                grew++
                const c = toChapter(latest, main.sourceId)
                notePageGrowth({ entry_id: e.dbId, source_id: main.sourceId, chapter_url: latest.url, chapter_number: c.number, chapter_label: c.label, pages: now, pages_before: latest.pageCount })
                editEntry(e.id, (x) => ({ ...x, chapters: x.chapters.map((ch) => (ch.remoteId === latest.id ? { ...ch, pages: now, newPages: now - latest.pageCount } : ch)) }))
              }
            }
            const cur = find(e.id)
            if (cur) {
              const before = cur.chapters.length || (cur.counts?.total ?? 0)
              const read = cur.counts ? cur.counts.total - cur.counts.unread : 0
              if (merged.length > before) found++
              editEntry(cur.id, (x) => ({
                ...x,
                updatedAgo: hoursSince(newestUpload(lists)) ?? x.updatedAgo,
                chapters: x.remote?.chaptersLoaded ? withDownloads(applyStates(withInserted(merged, x.inserted), statesOf(x.chapters))) : x.chapters,
                counts: { total: Math.max(merged.length, read), unread: Math.max(0, merged.length - read) },
              }))
            }
          } catch {
            failures++
          }
          set((s) => ({ ...s, updating: s.updating && { ...s.updating, done: s.updating.done + 1 } }))
        }
      }
      await Promise.all([worker(), worker(), worker()])
      checking = false
      set((s) => ({ ...s, updating: null, updatesSeen: found || grew ? false : s.updatesSeen }))
      try { localStorage.setItem(UPDATED_KEY, String(Date.now())) } catch { /* checked again next launch */ }
      const pagesNote = grew ? `${grew} chapter${grew === 1 ? '' : 's'} got new pages` : ''
      if (found) toast(`${found} title${found === 1 ? ' has' : 's have'} new chapters${pagesNote ? ` · ${pagesNote}` : ''}`)
      else if (grew) toast(pagesNote)
      else if (failures === list.length) toast("Couldn't reach the server")
      else if (!quiet) toast('No new chapters')
    }

    const reorderMain = (sources: EntrySource[], sourceId: string, mangaUrl?: string) =>
      sources.map((s) => ({ ...s, main: s.sourceId === sourceId && s.mangaUrl === mangaUrl }))
        .sort((a, b) => Number(b.main) - Number(a.main))

    const actions = {
      editEntry,
      loadEntry,
      loadStates,
      checkUpdates,
      toggleLibrary: (id: string) => {
        const e = find(id)
        if (!e) return
        editEntry(e.id, (x) => ({ ...x, inLibrary: !x.inLibrary }))
        // A title saved for the first time is written with its new library state.
        if (e.dbId) { if (canSave()) updateEntry(e.dbId, { in_library: !e.inLibrary }) } else ensureEntry(e.id)
      },
      /** Adds titles to the end of the Reading list. */
      addToReading: (ids: string[]) => {
        const st = get()
        const fresh = ids.filter((id) => { const e = find(id); return e && (st.server.status === 'off' ? !st.queue.includes(e.id) : e.readingPos == null) })
        if (!fresh.length) { toast('Already in Reading'); return }
        if (st.server.status === 'off') set((s) => ({ ...s, queue: [...s.queue, ...fresh.map((id) => find(id)!.id)] }))
        else {
          let pos = Math.max(0, ...st.entries.map((e) => e.readingPos ?? 0))
          for (const id of fresh) {
            const e = find(id)!
            pos += 1
            const p = pos
            editEntry(e.id, (x) => ({ ...x, readingPos: p }))
            const dbId = ensureEntry(e.id)
            if (dbId && e.dbId) updateEntry(dbId, { reading_pos: p })
          }
        }
        toast(fresh.length === 1 ? `Added ${find(fresh[0])!.title} to Reading` : `Added ${fresh.length} titles to Reading`)
      },
      /** Takes titles out of the Reading list (all of them when no ids are given). */
      removeFromReading: (ids?: string[]) => {
        const st = get()
        const list = ids ?? (st.server.status === 'off' ? st.queue : st.entries.filter((e) => e.readingPos != null).map((e) => e.id))
        if (st.server.status === 'off') { set((s) => ({ ...s, queue: s.queue.filter((q) => !list.includes(q)) })); return }
        for (const id of list) {
          const e = find(id)
          if (!e || e.readingPos == null) continue
          editEntry(e.id, (x) => ({ ...x, readingPos: undefined }))
          if (e.dbId && canSave()) updateEntry(e.dbId, { reading_pos: null })
        }
      },
      /** Moves a title earlier (-1) or later (+1) in the Reading list. */
      moveInReading: (id: string, by: -1 | 1) => {
        const st = get()
        if (st.server.status === 'off') {
          set((s) => {
            const q = [...s.queue], i = q.indexOf(id), j = i + by
            if (i < 0 || j < 0 || j >= q.length) return s
            ;[q[i], q[j]] = [q[j], q[i]]
            return { ...s, queue: q }
          })
          return
        }
        const list = st.entries.filter((e) => e.readingPos != null).sort((a, b) => a.readingPos! - b.readingPos!)
        const i = list.findIndex((e) => e.id === id), j = i + by
        if (i < 0 || j < 0 || j >= list.length) return
        const a = list[i], b = list[j]
        editEntry(a.id, (x) => ({ ...x, readingPos: b.readingPos }))
        editEntry(b.id, (x) => ({ ...x, readingPos: a.readingPos }))
        if (canSave()) { if (a.dbId) updateEntry(a.dbId, { reading_pos: b.readingPos }); if (b.dbId) updateEntry(b.dbId, { reading_pos: a.readingPos }) }
      },
      /** Picks titles to get new chapters (their main source is followed), or stops all their sources. */
      setFollow: (ids: string[], on: boolean) => {
        for (const id of ids) {
          const e = find(id)
          if (!e?.remote) continue
          const main = e.sources.find((s) => s.main) ?? e.sources[0]
          const want = (s: EntrySource) => (on ? (s === main ? true : s.following) : false)
          const changed = e.sources.filter((s) => s.mangaUrl && want(s) !== s.following)
          if (!changed.length) continue
          editEntry(e.id, (x) => ({ ...x, sources: x.sources.map((s) => (changed.includes(s) ? { ...s, following: want(s) } : s)) }))
          const dbId = ensureEntry(e.id)
          if (dbId) changed.forEach((s) => updateEntrySource({ entry_id: dbId, source_id: s.sourceId, manga_url: s.mangaUrl! }, { following: want(s) }))
        }
      },
      toggleFollow: (id: string, sourceId: string, mangaUrl?: string) => {
        const e = find(id)
        if (!e) return
        const s = e.sources.find((x) => x.sourceId === sourceId && (!mangaUrl || x.mangaUrl === mangaUrl))
        if (!s) return
        editEntry(e.id, (x) => ({ ...x, sources: x.sources.map((y) => (y === s ? { ...y, following: !y.following } : y)) }))
        const dbId = e.remote ? ensureEntry(e.id) : undefined
        if (dbId && s.mangaUrl) updateEntrySource({ entry_id: dbId, source_id: s.sourceId, manga_url: s.mangaUrl }, { following: !s.following })
      },
      /** Links the same title on another source; its chapters become versions in the same slots. */
      linkSource: async (id: string, link: { mangaId: number; mangaUrl: string; sourceId: string; name?: string; iconUrl?: string }) => {
        const e = find(id)
        if (!e) return
        if (e.sources.some((s) => s.sourceId === link.sourceId && s.mangaUrl === link.mangaUrl)) { toast('Already linked'); return }
        const source: EntrySource = { sourceId: link.sourceId, mangaId: link.mangaId, mangaUrl: link.mangaUrl, name: link.name, iconUrl: link.iconUrl, chapters: 0, following: false, main: false }
        const hadRow = !!e.dbId
        editEntry(e.id, (x) => ({ ...x, sources: [...x.sources, source] }))
        const dbId = ensureEntry(e.id)
        if (dbId && hadRow) saveEntrySource(sourceRow(dbId, source))
        toast(`Linked ${link.name ?? 'source'}`)
        await loadEntry(e.id).catch(() => {})
      },
      unlinkSource: async (id: string, sourceId: string, mangaUrl?: string) => {
        const e = find(id)
        const s = e?.sources.find((x) => x.sourceId === sourceId && x.mangaUrl === mangaUrl)
        if (!e || !s || s.main) return
        editEntry(e.id, (x) => ({ ...x, sources: x.sources.filter((y) => y !== s) }))
        if (e.dbId && s.mangaUrl && canSave()) deleteEntrySource(e.dbId, s.sourceId, s.mangaUrl)
        await loadEntry(e.id).catch(() => {})
      },
      /** The main source supplies the details and is the one read; the title keeps its place and progress. */
      setMainSource: async (id: string, sourceId: string, mangaUrl?: string) => {
        const e = find(id)
        const s = e?.sources.find((x) => x.sourceId === sourceId && x.mangaUrl === mangaUrl)
        if (!e || !s || s.main || s.mangaId == null || !s.mangaUrl) return
        editEntry(e.id, (x) => ({
          ...x,
          sources: reorderMain(x.sources, sourceId, mangaUrl),
          remote: x.remote && { ...x.remote, mangaId: s.mangaId!, sourceId, mangaUrl: s.mangaUrl! },
        }))
        const dbId = ensureEntry(e.id)
        if (dbId && e.dbId) {
          updateEntrySource({ entry_id: dbId }, { is_main: false })
          updateEntrySource({ entry_id: dbId, source_id: sourceId, manga_url: s.mangaUrl }, { is_main: true })
        }
        toast(`${s.name ?? 'Source'} is now the main source`)
        await loadEntry(e.id).catch(() => {})
      },
      /**
       * Moves a title to another source: links it, carries reading state (read, page, bookmark, hidden, moved,
       * thumbnail) and page layouts over by chapter number, makes it the main source and unlinks the old one.
       */
      migrateSource: async (id: string, to: { mangaId: number; mangaUrl: string; sourceId: string; name?: string; iconUrl?: string }, quiet = false): Promise<false | { moved: number; lost: number }> => {
        let e = find(id)
        const from = e?.sources.find((s) => s.main) ?? e?.sources[0]
        if (!e || !from) return false
        if (from.sourceId === to.sourceId && from.mangaUrl === to.mangaUrl) { if (!quiet) toast('That is the current source'); return false }
        if (!e.remote?.chaptersLoaded) await loadEntry(e.id).catch(() => {})
        e = find(id)!
        const keysOf = (c: Chapter) => (c.alts?.length ? c.alts.map((a) => chapterKey(a.sourceId, a.url)) : c.sourceUrl ? [chapterKey(c.sourceId, c.sourceUrl)] : [])
        const before = new Set(e.chapters.flatMap(keysOf))
        const already = e.sources.some((s) => s.sourceId === to.sourceId && s.mangaUrl === to.mangaUrl)
        if (!already) {
          const source: EntrySource = { sourceId: to.sourceId, mangaId: to.mangaId, mangaUrl: to.mangaUrl, name: to.name, iconUrl: to.iconUrl, chapters: 0, following: !!from.following, main: false }
          const hadRow = !!e.dbId
          editEntry(e.id, (x) => ({ ...x, sources: [...x.sources, source] }))
          const db0 = ensureEntry(e.id)
          if (db0 && hadRow) saveEntrySource(sourceRow(db0, source))
          await loadEntry(e.id)
        }
        e = find(id)!
        const dbId = ensureEntry(e.id)
        const fresh = (c: Chapter) => c.alts?.find((a) => a.sourceId === to.sourceId && !before.has(chapterKey(a.sourceId, a.url)))
        const touched = (c: Chapter) => c.read || c.page > 0 || c.bookmarked || c.removed || c.order != null || !!c.thumb || !!c.marks?.length
        let moved = 0, lost = 0
        const rows: ChapterStateRow[] = []
        for (const c of e.chapters) {
          if (c.insertId || !touched(c)) continue
          const v = fresh(c)
          if (!v) { lost++; continue }
          moved++
          if (dbId) rows.push(stateRow(dbId, { ...c, sourceId: v.sourceId, sourceUrl: v.url, preferred: false }))
          const split = c.sourceUrl ? e.splits?.[chapterKey(c.sourceId, c.sourceUrl)] : undefined
          if (dbId && split) saveSplit({ entry_id: dbId, source_id: v.sourceId, chapter_url: v.url, breaks: split.breaks, excluded: split.skip })
        }
        if (rows.length) saveChapterStates(rows)
        await flushWrites().catch(() => false)
        const target = find(id)!.sources.find((s) => s.sourceId === to.sourceId && s.mangaUrl === to.mangaUrl)
        if (target && !target.main) {
          editEntry(e.id, (x) => ({ ...x, sources: reorderMain(x.sources, to.sourceId, to.mangaUrl), remote: x.remote && { ...x.remote, mangaId: to.mangaId, sourceId: to.sourceId, mangaUrl: to.mangaUrl } }))
          if (dbId && e.dbId) {
            updateEntrySource({ entry_id: dbId }, { is_main: false })
            updateEntrySource({ entry_id: dbId, source_id: to.sourceId, manga_url: to.mangaUrl }, { is_main: true })
          }
        }
        editEntry(e.id, (x) => ({ ...x, sources: x.sources.filter((y) => !(y.sourceId === from.sourceId && y.mangaUrl === from.mangaUrl)) }))
        if (dbId && from.mangaUrl) deleteEntrySource(dbId, from.sourceId, from.mangaUrl)
        await flushWrites().catch(() => false)
        await loadEntry(e.id).catch(() => {})
        // The chapters on screen are the new source's now: read their state from the database.
        loadStates(e.id)
        if (!quiet) toast(`Moved to ${to.name ?? 'the new source'} · ${moved} chapter${moved === 1 ? '' : 's'} carried over${lost ? ` · ${lost} not found there` : ''}`)
        return { moved, lost }
      },
      /** Nests a title inside another entry (a series), or takes it out again. */
      setParent: (childId: string, parentId: string | undefined) => {
        const child = find(childId)
        const parent = parentId ? find(parentId) : undefined
        if (!child || child.id === parent?.id) return
        editEntry(child.id, (x) => ({ ...x, parentId: parent?.id }))
        const childDb = ensureEntry(child.id)
        const parentDb = parent ? ensureEntry(parent.id) : null
        if (childDb && parentDb !== undefined) updateEntry(childDb, { parent_id: parentDb })
      },
      editChapters: (id: string, chapterIds: Set<string>, patch: Partial<Chapter>) => {
        const e = find(id)
        if (!e) return
        const changes = toPhysical(e, chapterIds, patch)
        // Removing an inserted chapter takes the insertion away rather than hiding it.
        const dropped = patch.removed ? e.chapters.filter((c) => changes.has(c.id) && c.insertId) : []
        if (dropped.length) {
          editEntry(e.id, (x) => ({
            ...x,
            inserted: x.inserted?.filter((i) => !dropped.some((c) => c.insertId === i.id)),
            chapters: x.chapters.filter((c) => !dropped.includes(c)),
          }))
          if (e.dbId && canSave()) dropped.forEach((c) => deleteInserted(c.insertId!))
          dropped.forEach((c) => changes.delete(c.id))
        }
        editEntry(e.id, (x) => ({ ...x, chapters: x.chapters.map((c) => (changes.has(c.id) ? { ...c, ...changes.get(c.id) } : c)) }))
        if (patch.read !== undefined || patch.bookmarked !== undefined || patch.removed !== undefined || patch.page !== undefined || 'thumb' in patch || 'marks' in patch) saveChapters(e.id, new Set(changes.keys()))
      },
      /** Reads another version (linked source) of a chapter from now on. */
      chooseVersion: (id: string, chapterId: string, versionIndex: number) => {
        const e = find(id)
        const c = e?.chapters.find((x) => x.id === physicalIdOf(chapterId))
        const v = c?.alts?.[versionIndex]
        if (!e || !c || !v) return
        const chosen = showVersion(c, v, true)
        editEntry(e.id, (x) => ({ ...x, chapters: x.chapters.map((y) => (y.id === c.id ? chosen : y)) }))
        const dbId = ensureEntry(e.id)
        // The pick is saved on the chosen version; the others lose theirs. Reading state goes with it.
        if (dbId) saveChapterStates(c.alts!.map((a) => stateRow(dbId, { ...chosen, sourceId: a.sourceId, sourceUrl: a.url, preferred: a === v })))
        toast(`Reading ${v.name}`)
      },
      /** Sets where a chapter's parts start (first page of every part after the first) and which pages are left out. */
      splitChapter: (id: string, chapterId: string, { breaks, skip }: PageLayout) => {
        const e = find(id)
        const c = e?.chapters.find((x) => x.id === physicalIdOf(chapterId))
        if (!e || !c?.sourceUrl) return
        const key = chapterKey(c.sourceId, c.sourceUrl)
        const sorted = (l: number[]) => [...new Set(l)].sort((a, b) => a - b)
        const clean = sorted(breaks).filter((b) => b > 1)
        const left = sorted(skip).filter((n) => n >= 1)
        const any = clean.length > 0 || left.length > 0
        editEntry(e.id, (x) => {
          const { [key]: _old, ...rest } = x.splits ?? {}
          return { ...x, splits: any ? { ...rest, [key]: { breaks: clean, skip: left } } : rest }
        })
        const dbId = ensureEntry(e.id)
        if (dbId) {
          if (any) saveSplit({ entry_id: dbId, source_id: c.sourceId, chapter_url: c.sourceUrl, breaks: clean, excluded: left })
          else deleteSplit(dbId, c.sourceId, c.sourceUrl)
        }
        const skipped = left.length ? `${left.length} page${left.length === 1 ? '' : 's'} left out` : ''
        toast(!any ? `${c.label} is whole again` : [clean.length ? `${c.label} in ${clean.length + 1} parts` : c.label, skipped].filter(Boolean).join(' · '))
      },
      /** Places a chapter from another title or source into this entry. */
      insertChapter: (id: string, chapter: Omit<InsertedChapter, 'id'>) => {
        const e = find(id)
        if (!e) return
        const ins: InsertedChapter = { ...chapter, id: crypto.randomUUID() }
        editEntry(e.id, (x) => {
          const inserted = [...(x.inserted ?? []), ins]
          return { ...x, inserted, chapters: withDownloads(withInserted(x.chapters, inserted)) }
        })
        const dbId = ensureEntry(e.id)
        if (dbId) saveInserted(insertedRow(dbId, ins))
        toast(`Added ${ins.label}`)
      },
      /** Saves chapters on this device for offline reading. */
      downloadChapters: (id: string, chapterIds: Set<string>) => {
        const e = find(id)
        if (!e) return
        const ids = new Set([...chapterIds].map(physicalIdOf))
        const jobs: DownloadJob[] = e.chapters
          .filter((c) => ids.has(c.id) && c.sourceUrl && c.remoteId)
          .map((c) => ({ key: chapterKey(c.sourceId, c.sourceUrl!), entryId: e.id, title: e.title, label: c.label, remoteId: c.remoteId! }))
        if (!jobs.length) { toast(e.remote ? 'Nothing to download' : 'Downloads need a server'); return }
        const n = download(jobs)
        toast(n ? `Downloading ${n} chapter${n === 1 ? '' : 's'}` : 'Already downloaded')
      },
      removeDownloads: (id: string, chapterIds: Set<string>) => {
        const e = find(id)
        if (!e) return
        const ids = new Set([...chapterIds].map(physicalIdOf))
        const keys = e.chapters.filter((c) => ids.has(c.id) && c.sourceUrl).map((c) => chapterKey(c.sourceId, c.sourceUrl!))
        keys.forEach((k) => void removeDownload(k))
        toast(`Removed ${keys.length} download${keys.length === 1 ? '' : 's'}`)
      },
      toggleInstall: (sourceId: string) =>
        set((s) => ({ ...s, sources: s.sources.map((x) => (x.id === sourceId ? { ...x, installed: !x.installed, update: false } : x)) })),
      togglePin: (sourceId: string) =>
        set((s) => ({ ...s, sources: s.sources.map((x) => (x.id === sourceId ? { ...x, pinned: !x.pinned } : x)) })),
      updateAll: () => set((s) => ({ ...s, sources: s.sources.map((x) => ({ ...x, update: false })) })),
      clearWarning: (sourceId: string) =>
        set((s) => ({ ...s, sources: s.sources.map((x) => (x.id === sourceId ? { ...x, warn: undefined } : x)) })),
      markUpdatesSeen: () => set((s) => ({ ...s, updatesSeen: true })),
      dismissMini: () => set((s) => ({ ...s, miniHidden: true })),
      /** Saves the reader position; reaching the last page marks the chapter read. */
      setProgress: (entryId: string, chapterId: string, pageIn: number) => {
        const e = find(entryId)
        if (!e) return
        // A part of a split chapter saves its position on the whole chapter.
        // So does a chapter with pages left out: the reader's page number maps to the physical page.
        const shown = visibleChapters(e)
        const part = shown.find((c) => c.id === chapterId && c.range)
        const parts = part?.physicalId ? shown.filter((c) => c.physicalId === part.physicalId) : []
        const lastPart = !part?.physicalId || parts[parts.length - 1]?.id === part.id
        if (part?.physicalId) chapterId = part.physicalId
        const total = e.chapters.find((c) => c.id === chapterId)?.pages ?? 0
        const page = part?.range ? shownPages(part, total)[pageIn - 1] ?? part.range[0] - 1 + pageIn : pageIn
        set((s) => ({
          ...s,
          miniHidden: false,
          entries: s.entries.map((x) => x.id !== e.id ? x : {
            ...x,
            lastReadAgo: 0,
            chapters: x.chapters.map((c) => {
              if (c.id !== chapterId) return c
              const done = part ? lastPart && part.pages > 0 && pageIn >= part.pages : page >= c.pages
              return { ...c, page: done ? 0 : page, read: c.read || done, isNew: done ? false : c.isNew, newPages: undefined }
            }),
          }),
        }))
        // History names the chapter as it was shown (a part keeps its own name).
        const label = (part ?? shown.find((c) => c.id === chapterId) ?? e.chapters.find((c) => c.id === chapterId))?.label ?? ''
        const at = new Date().toISOString()
        saveChapters(e.id, new Set([chapterId]), { read_at: at, chapter_label: label })
        if (get().server.status === 'off') {
          const c = find(e.id)?.chapters.find((x) => x.id === chapterId)
          recordLocalHistory({ entryId: e.id, chapterId: part?.id ?? chapterId, label, page: pageIn, read: !!c?.read, at: Date.now() })
        }
        const dbId = find(e.id)?.dbId
        if (dbId) updateEntry(dbId, { last_read_at: at })
      },
      /** Adds a category tab and returns its id. */
      createTab: (name: string) => {
        const id = newTabId('tab')
        set((s) => ({ ...s, tabs: [...s.tabs, { id, kind: 'tab', name }] }))
        writeTab(id)
        return id
      },
      renameTab: (id: string, name: string) => {
        set((s) => ({ ...s, tabs: s.tabs.map((t) => (t.id === id ? { ...t, name } : t)) }))
        writeTab(id)
      },
      /** Deleting a tab keeps its titles in the library. */
      deleteTab: (id: string) => {
        set((s) => ({
          ...s,
          tabs: s.tabs.filter((t) => t.id !== id),
          entries: s.entries.map((e) => (e.tabs.includes(id) ? { ...e, tabs: e.tabs.filter((t) => t !== id) } : e)),
        }))
        if (canSave()) deleteTabRow(id)
      },
      toggleInTab: (entryId: string, tabId: string) => {
        const e = find(entryId)
        if (!e) return
        const on = !e.tabs.includes(tabId)
        editEntry(e.id, (x) => ({ ...x, tabs: on ? [...x.tabs, tabId] : x.tabs.filter((t) => t !== tabId) }))
        const dbId = ensureEntry(e.id)
        if (dbId) setEntryTab(dbId, tabId, on)
      },
      addTab: (name: string, filters: LibraryFilters) => {
        const id = newTabId('smart')
        set((s) => ({ ...s, tabs: [...s.tabs, { id, kind: 'smart', name, filters }] }))
        writeTab(id)
      },
      /** Edits a title's details; empty values go back to the server's. */
      editDetails: (id: string, patch: CustomDetails) => {
        const e = find(id)
        if (!e) return
        const custom: CustomDetails = { ...e.custom, ...patch }
        delete (custom as { status?: unknown }).status // hand-set statuses are gone; status follows progress
        for (const k of Object.keys(custom) as (keyof CustomDetails)[]) if (custom[k] === undefined || custom[k] === '') delete custom[k]
        // A series made in Midoku has nothing from a server: its details are all its own.
        if (e.sources.length === 0 && !custom.title) custom.title = e.title
        editEntry(e.id, (x) => applyCustom(x, custom))
        const dbId = ensureEntry(e.id)
        if (dbId) updateEntry(dbId, { custom })
      },
      /** Bookmarks a page of a chapter (a whole-chapter page number), or takes the bookmark away. */
      toggleMark: (id: string, chapterId: string, wholePage: number) => {
        const e = find(id)
        const whole = e?.chapters.find((c) => c.id === physicalIdOf(chapterId))
        if (!e || !whole) return false
        const has = whole.marks?.includes(wholePage)
        const marks = has ? whole.marks!.filter((n) => n !== wholePage) : [...(whole.marks ?? []), wholePage].sort((a, b) => a - b)
        actions.editChapters(e.id, new Set([whole.id]), { marks: marks.length ? marks : undefined })
        return !has
      },
      /** Marks every chapter of a title (and of the titles nested in it) read or unread. */
      markEntry: async (id: string, read: boolean) => {
        const e = find(id)
        if (!e) return
        const targets = [e, ...get().entries.filter((x) => x.parentId === e.id)]
        let n = 0
        for (const t of targets) {
          if (t.remote && !t.remote.chaptersLoaded) await loadEntry(t.id).catch(() => {})
          const cur = find(t.id)
          const ids = new Set((cur?.chapters ?? []).filter((c) => !c.removed && c.read !== read).map((c) => c.id))
          if (!ids.size || !cur) continue
          n += ids.size
          actions.editChapters(cur.id, ids, read ? { read: true, isNew: false, newPages: undefined } : { read: false, page: 0 })
        }
        toast(n ? `${e.title}: ${n} chapter${n === 1 ? '' : 's'} marked ${read ? 'read' : 'unread'}` : `Already ${read ? 'read' : 'unread'}`)
      },
      /** Reading mode for one title; undefined goes back to the device default. */
      setReaderMode: (id: string, mode: ReaderMode | undefined) => {
        const e = find(id)
        if (!e) return
        const custom: CustomDetails = { ...e.custom, reader: mode }
        if (!mode) delete custom.reader
        editEntry(e.id, (x) => ({ ...x, custom }))
        const dbId = ensureEntry(e.id)
        if (dbId) updateEntry(dbId, { custom })
      },
      /** Removes titles from the library (they stay in the database with their progress). */
      removeFromLibrary: (ids: string[]) => {
        for (const id of ids) {
          const e = find(id)
          if (!e?.inLibrary) continue
          editEntry(e.id, (x) => ({ ...x, inLibrary: false }))
          if (e.dbId && canSave()) updateEntry(e.dbId, { in_library: false })
        }
      },
      /**
       * Groups titles (in the given order) into a new series that holds them, or merges them into one title
       * whose chapters follow each other. Returns the id of the title to open.
       */
      groupTitles: async (ids: string[], opts: { mode: 'nest' | 'merge'; title?: string; inheritFrom?: string; renumber?: boolean }): Promise<string | undefined> => {
        const parts = ids.map(find).filter((e): e is Entry => !!e)
        if (parts.length < 2) return undefined
        const from = (opts.inheritFrom && find(opts.inheritFrom)) || parts[0]
        const details: CustomDetails = { title: opts.title?.trim() || from.title, author: from.author, description: from.description, cover: from.coverUrl }
        const server = get().server.status !== 'off'
        if (server && !canSave()) return undefined

        if (opts.mode === 'nest') {
          const dbId = server ? crypto.randomUUID() : undefined
          const id = server ? `${LOCAL}${dbId}` : `${LOCAL}-${Date.now().toString(36)}`
          const tabs = [...new Set(parts.flatMap((p) => p.tabs))]
          const series = applyCustom({
            id, dbId, title: '', author: '', description: '', art: from.art, publishing: from.publishing, tabs, tags: [], sources: [], chapters: [],
            inLibrary: true, updatedAgo: Math.min(...parts.map((p) => p.updatedAgo)), addedOrder: Date.now(), counts: { total: 0, unread: 0 },
            original: { title: '', author: '', description: '' },
          }, details)
          set((s) => ({
            ...s,
            entries: [...s.entries.map((e) => { const i = parts.findIndex((p) => p.id === e.id); return i < 0 ? e : { ...e, parentId: id, position: i } }), series],
          }))
          if (dbId) {
            saveEntry(entryRow(series, dbId))
            tabs.forEach((t) => setEntryTab(dbId, t, true))
            parts.forEach((p, i) => { const childDb = ensureEntry(p.id); if (childDb) updateEntry(childDb, { parent_id: dbId, position: i }) })
          }
          toast(`Grouped ${parts.length} titles`)
          return id
        }

        // Merge: the first title keeps its row; the others' sources follow as later segments.
        const [keep, ...rest] = parts
        if (server && parts.some((p) => !p.remote)) { toast('Only titles from the server can be merged'); return undefined }
        const keepDb = server ? ensureEntry(keep.id) : undefined
        const restDb = rest.map((p) => (server ? ensureEntry(p.id) : undefined))
        const segOf = (p: Entry) => Math.max(0, ...p.sources.map((x) => x.segment ?? 0))
        let next = segOf(keep) + 1
        const offsets: number[] = []
        const sources = [...keep.sources]
        for (const p of rest) {
          offsets.push(next)
          for (const x of p.sources) {
            if (!sources.some((y) => y.sourceId === x.sourceId && y.mangaUrl === x.mangaUrl)) sources.push({ ...x, main: false, segment: next + (x.segment ?? 0) })
          }
          next += segOf(p) + 1
        }
        const custom: CustomDetails = { ...keep.custom, ...(from !== keep || opts.title?.trim() ? details : {}) }
        const restIds = new Set(rest.map((p) => p.id))
        // Sample titles have their chapters in memory: they are put one after another.
        const chapters = server ? [] : parts.flatMap((p, i) => [...p.chapters].sort((a, b) => a.number - b.number).map((c) => ({ ...c, id: i ? `m${i}-${c.id}` : c.id })))
          .map((c, i) => ({ ...c, number: i + 1, label: opts.renumber ? `Chapter ${i + 1}` : c.label }))
        set((s) => ({
          ...s,
          entries: s.entries.filter((e) => !restIds.has(e.id)).map((e) => {
            if (e.parentId && restIds.has(e.parentId)) return { ...e, parentId: keep.id }
            if (e.id !== keep.id) return e
            return applyCustom({
              ...e, sources, renumber: !!opts.renumber, inLibrary: true,
              tabs: [...new Set(parts.flatMap((p) => p.tabs))],
              chapters: server ? [] : chapters,
              remote: e.remote && { ...e.remote, chaptersLoaded: false },
            }, custom)
          }),
        }))
        if (keepDb && restDb.every(Boolean)) {
          updateEntry(keepDb, { custom, renumber: !!opts.renumber, in_library: true })
          mergeEntryRows(keepDb, restDb as string[], offsets)
          await flushWrites().catch(() => false)
          await loadEntry(keep.id).catch(() => {})
        }
        toast(`Merged ${parts.length} titles`)
        return keep.id
      },
      /**
       * Adds chapters of one title to another library entry (Midoku's "Add to entry"). The first one gets
       * `name`; its number (from the name, or the entry's next number) places it, the rest follow it.
       */
      addToEntry: (fromId: string, chapterIds: Set<string>, targetId: string, name: string) => {
        const from = find(fromId)
        const target = find(targetId)
        if (!from || !target) return
        const ids = new Set([...chapterIds].map(physicalIdOf))
        const picked = from.chapters.filter((c) => ids.has(c.id) && c.sourceUrl).sort((a, b) => a.number - b.number)
        if (!picked.length) { toast('Nothing to add'); return }
        const { prefix, number } = parseChapterName(name.trim()) ?? { prefix: chapterPrefix(target), number: nextChapterNumber(target) }
        const added: InsertedChapter[] = picked.map((c, i) => ({
          id: crypto.randomUUID(), sourceId: c.sourceId,
          mangaUrl: from.inserted?.find((x) => x.id === c.insertId)?.mangaUrl ?? from.sources.find((x) => x.sourceId === c.sourceId)?.mangaUrl ?? '',
          chapterUrl: c.sourceUrl!, remoteId: c.remoteId, number: number + i,
          label: i === 0 && name.trim() ? name.trim() : `${prefix}${Number((number + i).toFixed(3))}`, fromTitle: from.title,
        }))
        editEntry(target.id, (x) => {
          const inserted = [...(x.inserted ?? []), ...added]
          return { ...x, inserted, chapters: x.chapters.length ? withDownloads(withInserted(x.chapters, inserted)) : x.chapters }
        })
        const dbId = ensureEntry(target.id)
        if (dbId) added.forEach((i) => saveInserted(insertedRow(dbId, i)))
        toast(`Added ${added.length === 1 ? added[0].label : `${added.length} chapters`} to ${target.title}`)
      },
      /** Moves a chapter in the reading order: after another chapter, or first when `afterId` is null. */
      moveChapter: (id: string, chapterId: string, afterId: string | null) => {
        const e = find(id)
        if (!e) return
        const moving = physicalIdOf(chapterId)
        const list = e.chapters.filter((c) => !c.removed && c.id !== moving).sort((a, b) => a.number - b.number)
        const i = afterId ? list.findIndex((c) => c.id === physicalIdOf(afterId)) : -1
        if (afterId && i < 0) return
        const before = list[i]?.number
        const after = list[i + 1]?.number
        const order = before === undefined ? (after ?? 1) - 1 : after === undefined ? before + 1 : (before + after) / 2
        editEntry(e.id, (x) => ({ ...x, chapters: x.chapters.map((c) => (c.id === moving ? { ...c, order, number: order, sourceNumber: c.sourceNumber ?? c.number } : c)) }))
        saveChapters(e.id, new Set([moving]))
        const c = e.chapters.find((x) => x.id === moving)
        toast(`Moved ${c?.label ?? 'chapter'}${afterId ? ` after ${list[i].label}` : ' to the start'}`)
      },
      /** Puts moved chapters back where their source has them (one chapter, or all of them). */
      resetOrder: (id: string, chapterId?: string) => {
        const e = find(id)
        if (!e) return
        const ids = new Set(e.chapters.filter((c) => c.order != null && (!chapterId || c.id === physicalIdOf(chapterId))).map((c) => c.id))
        if (!ids.size) return
        editEntry(e.id, (x) => ({ ...x, chapters: x.chapters.map((c) => (ids.has(c.id) ? { ...c, order: undefined, number: c.sourceNumber ?? c.number } : c)) }))
        saveChapters(e.id, ids)
        toast(ids.size === 1 ? 'Back in its original place' : `${ids.size} chapters back in their original places`)
      },
      toast,
    }
    return actions
  }, [set, get])
}

export type Store = State & ReturnType<typeof useActions> & {
  entry: (id: string) => Entry | undefined
  source: (id: string) => Source | undefined
  children: (id: string) => Entry[]
}

const Ctx = createContext<Store | null>(null)

export function StoreProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState(initial)
  // Every change goes through set, so actions read the latest state right after changing it.
  const latest = useRef(state)
  const set = useCallback((fn: (s: State) => State) => {
    latest.current = fn(latest.current)
    setState(latest.current)
  }, [])
  const get = useCallback(() => latest.current, [])
  const actions = useActions(set, get)
  const { serverUrl, serverUser, serverPass } = useSettings()
  const auth = useAuth()
  const lastServer = useRef('')
  // Back online after an offline launch: load the library from the database again.
  const [reload, setReload] = useState(0)
  useEffect(() => {
    const on = () => { if (latest.current.offline) setReload((n) => n + 1) }
    window.addEventListener('online', on)
    return () => window.removeEventListener('online', on)
  }, [])

  useEffect(() => onWriteError((message) => actions.toast(`Not saved: ${message}`)), [actions])

  useEffect(() => {
    // Titles opened from the same server stay while the library (re)loads; another server starts empty.
    const sameServer = !!serverUrl && lastServer.current === serverUrl
    lastServer.current = serverUrl
    const browsed = (s: State) => (sameServer ? s.entries.filter((e) => e.remote && !e.dbId) : [])
    if (!serverUrl) {
      set((s) => ({ ...s, ...sampleState(), sources: SOURCES, queue: SAMPLE_QUEUE, server: { status: 'off' }, offline: false }))
      return
    }
    if (!auth.ready || !auth.userId) {
      set((s) => ({ ...s, entries: browsed(s), queue: [], tabs: DEVICE_TABS, server: { status: auth.ready ? 'signin' : 'loading' } }))
      return
    }
    let alive = true
    set((s) => ({ ...s, entries: browsed(s), queue: [], server: { status: 'loading' } }))
    ;(async () => {
      // The library saved on this device shows at once; the database's copy replaces it when it arrives.
      const snap = await readJSON<LibrarySnapshot>('library')
      if (!alive) return
      if (snap) set((s) => ({ ...s, entries: [...snap.entries, ...browsed(s).filter((e) => !snap.entries.some((x) => x.id === e.id))], tabs: snap.tabs, server: { status: 'ready' } }))
      let entries: Entry[]
      let tabs: LibraryTab[]
      let offline = false
      try {
        if (!navigator.onLine) throw new TypeError('Failed to fetch')
        // Changes made offline go out first, so the library read back includes them.
        await flushWrites().catch(() => false)
        const lib: DbLibrary = await loadLibrary()
        tabs = lib.tabs.map(toTab)
        if (!tabs.length) {
          // First launch: start with Reading and All.
          tabs = DEVICE_TABS.map((t) => ({ ...t, id: crypto.randomUUID() }))
          saveTabs(tabs.map(tabRow))
        }
        entries = entriesFromDb(lib)
      } catch (e) {
        if (!alive) return
        if (!snap || !isOffline(e)) {
          set((s) => ({ ...s, server: { status: 'error', error: (e as Error).message, where: 'library' } }))
          return
        }
        ;({ entries, tabs } = snap)
        offline = true
      }
      if (!alive) return
      // A saved title that is already open keeps its loaded chapters and gets its reading state.
      // (Anything still in the state was opened from this server after the reset above.)
      const open = new Map(latest.current.entries.filter((e) => e.remote && (!e.dbId || e.remote.chaptersLoaded)).map((e) => [e.id, e]))
      const merged = entries.map((e) => {
        const o = open.get(e.id)
        // Keep what the open copy already loaded (chapters, inserted and split chapters).
        return o?.remote?.chaptersLoaded
          ? { ...e, chapters: withDownloads(o.chapters), inserted: o.inserted, splits: o.splits, remote: { ...e.remote!, chaptersLoaded: true, url: o.remote.url } }
          : o ? { ...e, inserted: o.inserted ?? e.inserted, splits: o.splits ?? e.splits } : e
      })
      const ids = new Set(entries.map((e) => e.id))
      set((s) => ({ ...s, entries: [...merged, ...[...open.values()].filter((e) => !ids.has(e.id))], tabs, offline, server: { status: 'ready' } }))
      // Open titles reload so chapters from every linked source are merged, then get their reading state.
      merged.forEach((e) => { if (e.remote?.chaptersLoaded) void actions.loadEntry(e.id).catch(() => 'saved').then(() => actions.loadStates(e.id)) })
      if (offline) return
      await syncWithServer(() => alive)
    })()
    return () => { alive = false }

    /**
     * Fills in chapter totals from the server and finds titles whose server id no longer matches
     * (Suwayomi reinstalled or moved), then looks for new chapters if it has been a while.
     */
    async function syncWithServer(alive: () => boolean) {
      const entries = latest.current.entries.filter((e) => e.dbId)
      const ids = [...new Set(entries.flatMap((e) => e.sources.map((s) => s.mangaId).filter((n): n is number => n != null)))]
      let byId: Map<number, SManga>
      try {
        byId = new Map((await getMangaSummaries(ids)).map((m) => [m.id, m]))
      } catch (e) {
        if (alive()) set((s) => ({ ...s, server: { status: 'error', error: (e as Error).message, where: 'server' } }))
        return
      }
      if (!alive()) return
      const matches = (s: EntrySource, m?: SManga) => !!m && m.url === s.mangaUrl && String(m.sourceId) === String(s.sourceId)
      set((st) => ({ ...st, entries: st.entries.map((e) => {
        const main = e.sources.find((s) => s.main)
        const m = main?.mangaId != null ? byId.get(main.mangaId) : undefined
        return e.dbId && main && matches(main, m) ? enrich(e, m!) : e
      }) }))
      // Titles the server no longer knows by that id are found again by source and address.
      const lost = entries.flatMap((e) => e.sources.filter((s) => s.mangaUrl && !matches(s, s.mangaId != null ? byId.get(s.mangaId) : undefined)).map((s) => ({ e, s })))
      let missing = 0
      for (const { e, s } of lost) {
        if (!alive()) return
        let m: SManga | undefined
        try { m = await resolveManga(s.sourceId, s.mangaUrl!, e.title) } catch { m = undefined }
        if (!m) { missing++; continue }
        const found = m
        updateEntrySource({ entry_id: e.dbId!, source_id: s.sourceId, manga_url: s.mangaUrl! }, { server_manga_id: found.id })
        set((st) => {
          const cur = st.entries.find((x) => x.dbId === e.dbId)
          if (!cur) return st
          const newId = s.main ? `s${found.id}` : cur.id
          const next: Entry = {
            ...cur,
            id: newId,
            sources: cur.sources.map((x) => (x.sourceId === s.sourceId && x.mangaUrl === s.mangaUrl ? { ...x, mangaId: found.id } : x)),
            remote: s.main && cur.remote ? { ...cur.remote, mangaId: found.id } : cur.remote,
          }
          return {
            ...st,
            entries: st.entries.map((x) => (x === cur ? (s.main ? enrich(next, found) : next) : x.parentId === cur.id ? { ...x, parentId: newId } : x)),
          }
        })
      }
      if (missing && alive()) actions.toast(`${missing} linked title${missing === 1 ? '' : 's'} couldn't be found on this server`)
      if (alive() && navigator.onLine && Date.now() - lastUpdateCheck() > UPDATE_EVERY_MS) void actions.checkUpdates(true)
    }
  }, [serverUrl, serverUser, serverPass, auth.ready, auth.userId, actions, set, reload])

  // Old copies of opened titles go after 3 days (titles with downloads keep theirs).
  useEffect(() => { void pruneEntryCopies(new Set(getSavedList().map((d) => d.entryId))) }, [])

  // Downloads finishing or being removed show on the chapters.
  const downloads = useDownloads()
  useEffect(() => {
    set((s) => {
      let changed = false
      const entries = s.entries.map((e) => {
        if (!e.chapters.length) return e
        const chapters = withDownloads(e.chapters)
        if (chapters.some((c, i) => c !== e.chapters[i])) { changed = true; return { ...e, chapters } }
        return e
      })
      return changed ? { ...s, entries } : s
    })
  }, [downloads.saved, set])

  const { tabs, entries, server } = state

  // Sample data: remember tabs and filing on this device.
  useEffect(() => {
    if (server.status === 'off') saveSampleLayout({ tabs, memberships: Object.fromEntries(entries.map((e) => [e.id, e.tabs])) })
  }, [server.status, tabs, entries])

  // Keep a copy for offline launches: the library, and each opened title with its chapters and progress.
  const savedEntries = useRef(new Map<string, Entry>())
  useEffect(() => {
    if (server.status !== 'ready' && !(server.status === 'error' && server.where === 'server')) return
    const t = setTimeout(() => {
      const lib = entries.filter((e) => e.dbId).map((e) => ({
        ...e, chapters: [], remote: e.remote && { ...e.remote, chaptersLoaded: false },
        counts: { total: totalCount(e), unread: unreadCount(e) },
      }))
      void writeJSON('library', { entries: lib, tabs } satisfies LibrarySnapshot)
      for (const e of entries) {
        const opened = openedAt.get(e.id)
        if (!opened || !e.remote?.chaptersLoaded || savedEntries.current.get(e.id) === e) continue
        savedEntries.current.set(e.id, e)
        void writeEntryCopy(e.id, e, opened)
      }
    }, 1000)
    return () => clearTimeout(t)
  }, [server, entries, tabs])

  // The Reading list is kept by hand (like native Midoku): titles added to it, in their order.
  const queue = useMemo(() => (server.status === 'off' ? state.queue : entries
    .filter((e) => e.readingPos != null && e.inLibrary)
    .sort((a, b) => a.readingPos! - b.readingPos!)
    .map((e) => e.id)), [server.status, state.queue, entries])

  const value = useMemo<Store>(() => ({
    ...state,
    queue,
    ...actions,
    // The latest state, so code that awaited a load (e.g. loadEntry) sees the result.
    entry: (id) => findIn(latest.current.entries, id),
    source: (id) => state.sources.find((s) => s.id === id),
    children: (id) => state.entries.filter((e) => e.parentId === id && e.inLibrary).sort((a, b) => (a.position ?? 0) - (b.position ?? 0)),
  }), [state, queue, actions])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore(): Store {
  const s = useContext(Ctx)
  if (!s) throw new Error('StoreProvider missing')
  return s
}

// Derived helpers shared by pages.
/** Chapters as shown: removed ones hidden, split chapters as their parts. */
export const visibleChapters = (e: Entry) => expandSplits(e.chapters.filter((c) => !c.removed), e.splits)
/** Server titles in the library list carry totals until their chapters are loaded. */
const summaryOnly = (e: Entry) => e.chapters.length === 0 && !!e.counts
export const totalCount = (e: Entry) => (summaryOnly(e) ? e.counts!.total : visibleChapters(e).length)
export const unreadCount = (e: Entry) => (summaryOnly(e) ? e.counts!.unread : visibleChapters(e).filter((c) => !c.read).length)
export const newCount = (e: Entry) => (summaryOnly(e) ? e.counts!.unread : visibleChapters(e).filter((c) => c.isNew && !c.read).length)
export const readCount = (e: Entry) => (summaryOnly(e) ? e.counts!.total - e.counts!.unread : visibleChapters(e).filter((c) => c.read).length)

/** Unread until a chapter is read, Reading until every chapter is (a new chapter turns it back), then Completed. */
export function statusOf(e: Entry): Status {
  const total = totalCount(e)
  const read = readCount(e)
  if (total > 0 && read === total) return 'completed'
  return read > 0 || (!summaryOnly(e) && visibleChapters(e).some((c) => c.page > 0)) ? 'reading' : 'unread'
}

/** The chapter the reader resumes: the first unread one in reading order. */
export function resumeChapter(e: Entry): Chapter | undefined {
  return [...visibleChapters(e)].sort((a, b) => a.number - b.number).find((c) => !c.read)
}

export function progressPct(e: Entry): number {
  const total = totalCount(e)
  return total ? Math.round((readCount(e) / total) * 100) : 0
}

/** "just now", "3h ago", "2d ago". */
export const agoText = (hours: number) => (hours < 1 ? 'just now' : `${agoLabel(hours)} ago`)

export function agoLabel(hours: number): string {
  if (hours < 1) return 'now'
  if (hours < 24) return `${Math.round(hours)}h`
  const d = Math.round(hours / 24)
  return d < 7 ? `${d}d` : `${Math.round(d / 7)}w`
}

/** "Chapter 12" → prefix "Chapter ", number 12. */
export function parseChapterName(name: string): { prefix: string; number: number } | undefined {
  const m = name.match(/^(.*?)(\d+(?:\.\d+)?)\s*$/)
  return m ? { prefix: m[1], number: Number(m[2]) } : undefined
}
/** How the entry names its chapters ("Ch. ", "Chapter "), from its last numbered chapter. */
export function chapterPrefix(e: Entry): string {
  const last = [...visibleChapters(e)].sort((a, b) => b.number - a.number).map((c) => parseChapterName(c.label.split(' · ')[0])).find(Boolean)
  return last?.prefix || 'Chapter '
}
/** The number after the entry's last chapter (from the totals when its chapters aren't loaded yet). */
export function nextChapterNumber(e: Entry): number {
  const shown = visibleChapters(e).filter((c) => !c.physicalId)
  if (!shown.length) return (e.counts?.total ?? 0) + 1
  return Math.floor(Math.max(...shown.map((c) => c.number))) + 1
}
export const suggestedChapterName = (e: Entry) => `${chapterPrefix(e)}${nextChapterNumber(e)}`
