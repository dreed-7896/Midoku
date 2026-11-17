import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import {
  ChapterStateRow, DbLibrary, deleteTabRow, EntryRow, loadChapterStates, loadLibrary, saveChapterStates, saveEntry,
  saveEntrySource, saveTabs, setEntryTab, TabRow, updateEntry, useAuth,
} from './db'
import { ENTRIES, LIBRARY_TABS, SOURCES } from './mock'
import { useSettings } from './settings'
import { artFor, assetUrl, getMangaSummaries, hoursSince } from './suwayomi'
import type { Chapter, Entry, LibraryFilters, LibraryTab, Source, Status } from './types'

/*
 * Where things live:
 * - Sample data (no server address): kept on this device in localStorage.
 * - With a Suwayomi server: Suwayomi only supplies titles, chapters, pages and extensions and is never written to.
 *   The library, tabs, reading progress and chapter marks live in Midoku's database (Supabase), per signed-in person.
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

// Database rows to the app's model

const toTab = (r: TabRow): LibraryTab =>
  r.kind === 'smart' ? { id: r.id, kind: 'smart', name: r.name, filters: r.filters ?? { statuses: [], newOnly: false } } : { id: r.id, kind: r.kind, name: r.name } as LibraryTab

const tabRow = (t: LibraryTab, position: number): TabRow =>
  ({ id: t.id, kind: t.kind, name: t.name, filters: t.kind === 'smart' ? t.filters : null, position })

const publishingOf = (p: string): Entry['publishing'] => (p === 'Completed' || p === 'Hiatus' ? p : 'Ongoing')

/** Library titles as stored; chapter totals are filled in from the server afterwards. */
function entriesFromDb(lib: DbLibrary): Entry[] {
  const main = new Map<string, DbLibrary['sources'][number]>()
  for (const s of lib.sources) if (s.is_main || !main.has(s.entry_id)) main.set(s.entry_id, s)
  const tabsOf = new Map<string, string[]>()
  for (const t of lib.entryTabs) tabsOf.set(t.entry_id, [...(tabsOf.get(t.entry_id) ?? []), t.tab_id])
  const read = new Map(lib.progress.map((p) => [p.entry_id, p.read_count]))
  const appId = new Map<string, string>()
  const list: Entry[] = []
  for (const r of lib.entries) {
    const src = main.get(r.id)
    if (src?.server_manga_id == null) continue
    const mangaId = src.server_manga_id
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
      sources: [{ sourceId: src.source_id, chapters: 0, following: src.following, main: true, name: src.source_name ?? undefined }],
      parentId: r.parent_id ?? undefined,
      chapters: [],
      inLibrary: r.in_library,
      lastReadAgo: r.last_read_at ? hoursSince(Date.parse(r.last_read_at)) : undefined,
      updatedAgo: 1e6,
      addedOrder: r.added_at ? Date.parse(r.added_at) : 0,
      remote: { mangaId, sourceId: src.source_id, mangaUrl: src.manga_url, chaptersLoaded: false },
      counts: { total: readCount, unread: 0 },
    })
  }
  return list.map((e) => (e.parentId ? { ...e, parentId: appId.get(e.parentId) } : e))
}

const entryRow = (e: Entry, dbId: string): EntryRow => ({
  id: dbId,
  title: e.title,
  author: e.author,
  cover_path: e.coverPath ?? null,
  description: e.description,
  tags: e.tags,
  publishing: e.publishing,
  parent_id: null,
  in_library: e.inLibrary,
  last_read_at: null,
})

const stateRow = (dbId: string, c: Chapter): ChapterStateRow => ({
  entry_id: dbId,
  source_id: c.sourceId,
  chapter_url: c.sourceUrl!,
  chapter_number: c.number,
  page: c.page,
  read: c.read,
  bookmarked: c.bookmarked,
  removed: !!c.removed,
})

const applyStates = (chapters: Chapter[], states: Pick<Chapter, 'sourceUrl' | 'page' | 'read' | 'bookmarked' | 'removed'>[]) => {
  const byUrl = new Map(states.filter((s) => s.sourceUrl).map((s) => [s.sourceUrl!, s]))
  return chapters.map((c) => {
    const s = c.sourceUrl ? byUrl.get(c.sourceUrl) : undefined
    return s ? { ...c, page: s.page, read: s.read, bookmarked: s.bookmarked, removed: s.removed || undefined } : c
  })
}

// Store

type ServerState =
  /** Sample data, no server address. */
  | { status: 'off' }
  /** A server is set but nobody is signed in to Midoku's database. */
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
}

const initial: State = {
  ...sampleState(),
  sources: SOURCES,
  queue: ['salt-static', 'paper-tigers', 'night-bus', 'quiet-tide', 'low-orbit', 'glasswing'],
  updatesSeen: false,
  toastMessage: null,
  miniHidden: false,
  server: { status: 'off' },
}

const SAMPLE_QUEUE = initial.queue

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
    const find = (id: string) => get().entries.find((e) => e.id === id)

    /** Database writes run after the local change; a failure is reported, the local change stays. */
    const sync = (p: Promise<unknown>) => p.catch((e: Error) => toast(`Not saved: ${e.message}`))
    const usesDb = () => get().server.status !== 'off'
    let warned = false
    const canSave = () => {
      const st = get().server.status
      if (st === 'off') return false
      if (st === 'signin') {
        if (!warned) toast('Sign in from Settings to keep your library')
        warned = true
        return false
      }
      return true
    }

    /** Saves the title to the database once and returns its row id; later writes wait for it. */
    const saving = new Map<string, Promise<string>>()
    const ensureEntry = (id: string): Promise<string> => {
      const pending = saving.get(id)
      if (pending) return pending
      const e = find(id)
      if (!e?.remote) return Promise.reject(new Error('Not a server title'))
      if (e.dbId) return Promise.resolve(e.dbId)
      const dbId = crypto.randomUUID()
      editEntry(id, (x) => ({ ...x, dbId }))
      const remote = e.remote
      const p = saveEntry(entryRow(e, dbId))
        .then(() => saveEntrySource({
          entry_id: dbId, source_id: remote.sourceId, manga_url: remote.mangaUrl, server_manga_id: remote.mangaId,
          source_name: e.sources[0]?.name ?? null, following: true, is_main: true,
        }))
        .then(() => dbId)
      p.catch(() => {
        saving.delete(id)
        editEntry(id, (x) => ({ ...x, dbId: undefined }))
      })
      saving.set(id, p)
      return p
    }
    const withEntry = (id: string, write: (dbId: string) => Promise<unknown>) => {
      if (!canSave() || !find(id)?.remote) return
      sync(ensureEntry(id).then(write))
    }
    const saveChapters = (id: string, chapterIds: Set<string>) =>
      withEntry(id, (dbId) => {
        const rows = (find(id)?.chapters ?? []).filter((c) => chapterIds.has(c.id) && c.sourceUrl).map((c) => stateRow(dbId, c))
        return rows.length ? saveChapterStates(rows) : Promise.resolve()
      })
    /** Tab writes in flight; filing a title into a new tab waits for the tab to exist. */
    const tabWrites = new Map<string, Promise<unknown>>()
    const writeTab = (id: string) => {
      if (!canSave()) return
      const tabs = get().tabs
      const i = tabs.findIndex((t) => t.id === id)
      if (i < 0) return
      const p = (tabWrites.get(id) ?? Promise.resolve()).catch(() => {}).then(() => saveTabs([tabRow(tabs[i], i)]))
      tabWrites.set(id, p)
      sync(p)
    }
    const newTabId = (prefix: string) => (usesDb() ? crypto.randomUUID() : `${prefix}-${Date.now().toString(36)}`)

    /** Reading state from the database for a saved title whose chapters are loaded. */
    const loadStates = (id: string) => {
      const dbId = find(id)?.dbId
      if (!dbId || get().server.status === 'signin') return
      loadChapterStates(dbId)
        .then((rows) => editEntry(id, (e) => ({
          ...e,
          chapters: applyStates(e.chapters, rows.map((r) => ({ sourceUrl: r.chapter_url, page: r.page, read: r.read, bookmarked: r.bookmarked, removed: r.removed }))),
        })))
        .catch((e: Error) => toast(`Couldn't load reading progress: ${e.message}`))
    }

    return {
      editEntry,
      toggleLibrary: (id: string) => {
        const e = find(id)
        if (!e) return
        editEntry(id, (x) => ({ ...x, inLibrary: !x.inLibrary }))
        // A title saved for the first time is written with its new library state.
        const known = !!e.dbId || saving.has(id)
        withEntry(id, (dbId) => (known ? updateEntry(dbId, { in_library: !e.inLibrary }) : Promise.resolve()))
      },
      /** Adds or refreshes a title loaded from the server, keeping what Midoku knows about it. */
      upsertEntry: (entry: Entry) => {
        const old = find(entry.id)
        const firstChapters = entry.remote?.chaptersLoaded && !old?.remote?.chaptersLoaded
        set((s) => {
          const prev = s.entries.find((e) => e.id === entry.id)
          const next: Entry = prev ? {
            ...entry,
            dbId: prev.dbId,
            tabs: prev.tabs,
            inLibrary: prev.inLibrary,
            lastReadAgo: prev.lastReadAgo,
            parentId: prev.parentId,
            addedOrder: prev.addedOrder,
            counts: entry.counts && prev.counts
              ? { total: entry.counts.total, unread: Math.max(0, entry.counts.total - (prev.counts.total - prev.counts.unread)) }
              : entry.counts,
            chapters: applyStates(entry.chapters, prev.chapters),
          } : entry
          return { ...s, entries: prev ? s.entries.map((e) => (e.id === entry.id ? next : e)) : [...s.entries, next] }
        })
        // The first time chapters arrive for a saved title, bring in its reading state.
        if (firstChapters) loadStates(entry.id)
      },
      loadStates,
      toggleFollow: (id: string, sourceId: string) =>
        editEntry(id, (e) => ({ ...e, sources: e.sources.map((s) => (s.sourceId === sourceId ? { ...s, following: !s.following } : s)) })),
      editChapters: (id: string, chapterIds: Set<string>, patch: Partial<Chapter>) => {
        editEntry(id, (x) => ({ ...x, chapters: x.chapters.map((c) => (chapterIds.has(c.id) ? { ...c, ...patch } : c)) }))
        if (patch.read !== undefined || patch.bookmarked !== undefined || patch.removed !== undefined || patch.page !== undefined) saveChapters(id, chapterIds)
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
      setProgress: (entryId: string, chapterId: string, page: number) => {
        set((s) => ({
          ...s,
          miniHidden: false,
          entries: s.entries.map((e) => e.id !== entryId ? e : {
            ...e,
            lastReadAgo: 0,
            chapters: e.chapters.map((c) => {
              if (c.id !== chapterId) return c
              const done = page >= c.pages
              return { ...c, page: done ? 0 : page, read: c.read || done, isNew: done ? false : c.isNew }
            }),
          }),
        }))
        saveChapters(entryId, new Set([chapterId]))
        withEntry(entryId, (dbId) => updateEntry(dbId, { last_read_at: new Date().toISOString() }))
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
        if (canSave()) sync(deleteTabRow(id))
      },
      toggleInTab: (entryId: string, tabId: string) => {
        const e = find(entryId)
        if (!e) return
        const on = !e.tabs.includes(tabId)
        editEntry(entryId, (x) => ({ ...x, tabs: on ? [...x.tabs, tabId] : x.tabs.filter((t) => t !== tabId) }))
        withEntry(entryId, (dbId) => (tabWrites.get(tabId) ?? Promise.resolve()).then(() => setEntryTab(dbId, tabId, on)))
      },
      addTab: (name: string, filters: LibraryFilters) => {
        const id = newTabId('smart')
        set((s) => ({ ...s, tabs: [...s.tabs, { id, kind: 'smart', name, filters }] }))
        writeTab(id)
      },
      toast,
    }
  }, [set, get])
}

type Store = State & ReturnType<typeof useActions> & {
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

  useEffect(() => {
    // Titles opened from the same server stay while the library (re)loads; another server starts empty.
    const sameServer = !!serverUrl && lastServer.current === serverUrl
    lastServer.current = serverUrl
    const browsed = (s: State) => (sameServer ? s.entries.filter((e) => e.remote && !e.dbId) : [])
    if (!serverUrl) {
      set((s) => ({ ...s, ...sampleState(), sources: SOURCES, queue: SAMPLE_QUEUE, server: { status: 'off' } }))
      return
    }
    if (!auth.ready) {
      set((s) => ({ ...s, entries: browsed(s), queue: [], tabs: DEVICE_TABS, server: { status: 'loading' } }))
      return
    }
    if (!auth.userId) {
      set((s) => ({ ...s, entries: browsed(s), queue: [], tabs: DEVICE_TABS, server: { status: 'signin' } }))
      return
    }
    let alive = true
    set((s) => ({ ...s, entries: browsed(s), queue: [], server: { status: 'loading' } }))
    ;(async () => {
      let lib: DbLibrary
      try {
        lib = await loadLibrary()
      } catch (e) {
        if (alive) set((s) => ({ ...s, server: { status: 'error', error: (e as Error).message, where: 'library' } }))
        return
      }
      if (!alive) return
      let tabs = lib.tabs.map(toTab)
      if (!tabs.length) {
        // First sign-in: start with Reading and All.
        tabs = DEVICE_TABS.map((t) => ({ ...t, id: crypto.randomUUID() }))
        saveTabs(tabs.map(tabRow)).catch((e: Error) => actions.toast(`Not saved: ${e.message}`))
      }
      const entries = entriesFromDb(lib)
      // A saved title that is already open keeps its loaded chapters and gets its reading state.
      // (Anything still in the state was opened from this server after the reset above.)
      const open = new Map(latest.current.entries.filter((e) => e.remote && !e.dbId).map((e) => [e.id, e]))
      const merged = entries.map((e) => {
        const o = open.get(e.id)
        return o?.remote?.chaptersLoaded ? { ...e, chapters: o.chapters, remote: { ...e.remote!, chaptersLoaded: true, url: o.remote.url } } : e
      })
      const ids = new Set(entries.map((e) => e.id))
      set((s) => ({ ...s, entries: [...merged, ...[...open.values()].filter((e) => !ids.has(e.id))], tabs, server: { status: 'ready' } }))
      merged.forEach((e) => e.remote?.chaptersLoaded && actions.loadStates(e.id))
      // Chapter totals and newest uploads come from the server.
      try {
        const summaries = await getMangaSummaries(entries.map((e) => e.remote!.mangaId))
        if (!alive) return
        const byId = new Map(summaries.map((m) => [`s${m.id}`, m]))
        set((s) => ({
          ...s,
          entries: s.entries.map((e) => {
            const m = byId.get(e.id)
            if (!m || e.remote?.chaptersLoaded) return e
            const total = m.chapters?.totalCount ?? 0
            const read = e.counts ? e.counts.total - e.counts.unread : 0
            return {
              ...e,
              coverUrl: assetUrl(m.thumbnailUrl) || e.coverUrl,
              updatedAgo: hoursSince(m.latestUploadedChapter?.uploadDate) ?? 1e6,
              sources: e.sources.map((x, i) => (i === 0 ? { ...x, chapters: total, name: m.source?.displayName ?? x.name, iconUrl: m.source?.iconUrl ? assetUrl(m.source.iconUrl) : x.iconUrl } : x)),
              counts: { total: Math.max(total, read), unread: Math.max(0, total - read) },
            }
          }),
        }))
      } catch (e) {
        if (alive) set((s) => ({ ...s, server: { status: 'error', error: (e as Error).message, where: 'server' } }))
      }
    })()
    return () => { alive = false }
  }, [serverUrl, serverUser, serverPass, auth.ready, auth.userId, actions])

  // Sample data: remember tabs and filing on this device.
  const { tabs, entries, server } = state
  useEffect(() => {
    if (server.status === 'off') saveSampleLayout({ tabs, memberships: Object.fromEntries(entries.map((e) => [e.id, e.tabs])) })
  }, [server.status, tabs, entries])

  // With a server, the Reading tab lists titles started and not finished, most recently read first.
  const queue = useMemo(() => (server.status === 'off' ? state.queue : entries
    .filter((e) => e.inLibrary && !e.parentId && e.lastReadAgo !== undefined && unreadCount(e) > 0)
    .sort((a, b) => a.lastReadAgo! - b.lastReadAgo!)
    .map((e) => e.id)), [server.status, state.queue, entries])

  const value = useMemo<Store>(() => ({
    ...state,
    queue,
    ...actions,
    entry: (id) => state.entries.find((e) => e.id === id),
    source: (id) => state.sources.find((s) => s.id === id),
    children: (id) => state.entries.filter((e) => e.parentId === id && e.inLibrary),
  }), [state, queue, actions])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore(): Store {
  const s = useContext(Ctx)
  if (!s) throw new Error('StoreProvider missing')
  return s
}

// Derived helpers shared by pages.
export const visibleChapters = (e: Entry) => e.chapters.filter((c) => !c.removed)
/** Server titles in the library list carry totals until their chapters are loaded. */
const summaryOnly = (e: Entry) => e.chapters.length === 0 && !!e.counts
export const totalCount = (e: Entry) => (summaryOnly(e) ? e.counts!.total : visibleChapters(e).length)
export const unreadCount = (e: Entry) => (summaryOnly(e) ? e.counts!.unread : visibleChapters(e).filter((c) => !c.read).length)
export const newCount = (e: Entry) => (summaryOnly(e) ? e.counts!.unread : visibleChapters(e).filter((c) => c.isNew && !c.read).length)
export const readCount = (e: Entry) => (summaryOnly(e) ? e.counts!.total - e.counts!.unread : visibleChapters(e).filter((c) => c.read).length)

/** Reading until every chapter is read; a new chapter turns a completed title back to reading. */
export function statusOf(e: Entry): Status {
  const total = totalCount(e)
  return total > 0 && readCount(e) === total ? 'completed' : 'reading'
}

/** The chapter the reader resumes: the first unread one in reading order. */
export function resumeChapter(e: Entry): Chapter | undefined {
  return [...visibleChapters(e)].sort((a, b) => a.number - b.number).find((c) => !c.read)
}

export function progressPct(e: Entry): number {
  const total = totalCount(e)
  return total ? Math.round((readCount(e) / total) * 100) : 0
}

export function agoLabel(hours: number): string {
  if (hours < 1) return 'now'
  if (hours < 24) return `${Math.round(hours)}h`
  const d = Math.round(hours / 24)
  return d < 7 ? `${d}d` : `${Math.round(d / 7)}w`
}
