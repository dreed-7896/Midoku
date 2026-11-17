import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { ENTRIES, LIBRARY_TABS, SOURCES } from './mock'
import { useSettings } from './settings'
import {
  categoryIdOf, categoryTabId, createCategory, deleteCategory, getCategories, getLibrary, renameCategory,
  saveChapterProgress, SCategory, setInLibrary, setMangaCategory, toEntry, updateChapters,
} from './suwayomi'
import type { Chapter, Entry, LibraryFilters, LibraryTab, Source, Status } from './types'

/**
 * Library layout kept on the device, per server address (or for the sample data): the tab order,
 * Reading/All and saved-filter tabs, and for the sample data which tabs each title is in.
 * On a server, category tabs and their titles live on the server; the device only remembers their place.
 */
interface SavedLayout { tabs: LibraryTab[]; memberships?: Record<string, string[]> }
const LAYOUT_KEY = 'midoku.library'
const SAMPLE_SCOPE = 'sample'

function readLayouts(): Record<string, SavedLayout> {
  try {
    return JSON.parse(localStorage.getItem(LAYOUT_KEY) ?? '{}')
  } catch {
    return {}
  }
}
const loadLayout = (scope: string): SavedLayout | undefined => readLayouts()[scope]
function saveLayout(scope: string, layout: SavedLayout) {
  try {
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ ...readLayouts(), [scope]: layout }))
  } catch {
    // Storage can be unavailable (private mode); the layout then lasts for this session only.
  }
}

const DEVICE_TABS = LIBRARY_TABS.filter((t) => t.kind === 'reading' || t.kind === 'all')

/** Server categories in their saved places among the device tabs; new categories go at the end. */
function mergeTabs(saved: LibraryTab[] | undefined, categories: SCategory[]): LibraryTab[] {
  const server = new Map<string, LibraryTab>(categories.map((c) => [categoryTabId(c.id), { id: categoryTabId(c.id), kind: 'tab', name: c.name }]))
  const out: LibraryTab[] = []
  for (const t of saved ?? DEVICE_TABS) {
    if (t.kind !== 'tab') out.push(t)
    else if (server.has(t.id)) { out.push(server.get(t.id)!); server.delete(t.id) }
  }
  return [...out, ...server.values()]
}

function sampleState() {
  const saved = loadLayout(SAMPLE_SCOPE)
  const m = saved?.memberships
  return {
    tabs: saved?.tabs ?? LIBRARY_TABS,
    entries: m ? ENTRIES.map((e) => (m[e.id] ? { ...e, tabs: m[e.id] } : e)) : ENTRIES,
  }
}

interface State {
  entries: Entry[]
  sources: Source[]
  queue: string[]
  tabs: LibraryTab[]
  updatesSeen: boolean
  toastMessage: string | null
  miniHidden: boolean
  /** Sample data when no server is set; otherwise the state of the server library. */
  server: { status: 'off' | 'loading' | 'ready' | 'error'; error?: string }
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
    /** Server writes run after the local change; a failure is reported, the local change stays. */
    const sync = (p: Promise<unknown>) => p.catch((e: Error) => toast(`Not saved on the server: ${e.message}`))
    const find = (id: string) => get().entries.find((e) => e.id === id)
    const onServer = () => get().server.status !== 'off'
    /** Server ids for tabs created here whose category is still being created. */
    const pendingCategories = new Map<string, Promise<number>>()
    const categoryFor = async (tabId: string) => categoryIdOf(tabId) ?? pendingCategories.get(tabId)
    /** Titles whose tabs were changed here; a slower server reload must not undo that. */
    const tabsTouched = new Set<string>()
    const replaceTabId = (from: string, to: string) =>
      set((s) => ({
        ...s,
        tabs: s.tabs.map((t) => (t.id === from ? { ...t, id: to } : t)),
        entries: s.entries.map((e) => (e.tabs.includes(from) ? { ...e, tabs: e.tabs.map((t) => (t === from ? to : t)) } : e)),
      }))
    return {
      editEntry,
      toggleLibrary: (id: string) => {
        const e = find(id)
        editEntry(id, (x) => ({ ...x, inLibrary: !x.inLibrary }))
        if (e?.remote) sync(setInLibrary(e.remote.mangaId, !e.inLibrary))
      },
      /** Adds or refreshes a title loaded from the server; its tabs come from the server's categories. */
      upsertEntry: (entry: Entry) =>
        set((s) => {
          const old = s.entries.find((e) => e.id === entry.id)
          const keepTabs = old && (!entry.remote || tabsTouched.has(entry.id))
          const next = keepTabs ? { ...entry, tabs: old.tabs } : entry
          return { ...s, entries: old ? s.entries.map((e) => (e.id === entry.id ? next : e)) : [...s.entries, next] }
        }),
      toggleFollow: (id: string, sourceId: string) =>
        editEntry(id, (e) => ({ ...e, sources: e.sources.map((s) => (s.sourceId === sourceId ? { ...s, following: !s.following } : s)) })),
      editChapters: (id: string, chapterIds: Set<string>, patch: Partial<Chapter>) => {
        const e = find(id)
        editEntry(id, (x) => ({ ...x, chapters: x.chapters.map((c) => (chapterIds.has(c.id) ? { ...c, ...patch } : c)) }))
        if (!e?.remote || (patch.read === undefined && patch.bookmarked === undefined)) return
        const ids = e.chapters.filter((c) => chapterIds.has(c.id) && c.remoteId).map((c) => c.remoteId!)
        const serverPatch: { isRead?: boolean; isBookmarked?: boolean } = {}
        if (patch.read !== undefined) serverPatch.isRead = patch.read
        if (patch.bookmarked !== undefined) serverPatch.isBookmarked = patch.bookmarked
        if (ids.length) sync(updateChapters(ids, serverPatch))
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
        const c = find(entryId)?.chapters.find((x) => x.id === chapterId)
        if (c?.remoteId && c.pages) sync(saveChapterProgress(c.remoteId, page, c.pages))
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
      },
      /** Adds a category tab and returns its id. */
      createTab: (name: string) => {
        const id = `tab-${Date.now().toString(36)}`
        set((s) => ({ ...s, tabs: [...s.tabs, { id, kind: 'tab', name }] }))
        if (onServer()) {
          const made = createCategory(name).then((c) => {
            replaceTabId(id, categoryTabId(c.id))
            return c.id
          })
          pendingCategories.set(id, made)
          sync(made)
        }
        return id
      },
      renameTab: (id: string, name: string) => {
        set((s) => ({ ...s, tabs: s.tabs.map((t) => (t.id === id ? { ...t, name } : t)) }))
        if (onServer()) sync(categoryFor(id).then((cat) => cat !== undefined && renameCategory(cat, name)))
      },
      /** Deleting a tab keeps its titles in the library. */
      deleteTab: (id: string) => {
        set((s) => ({
          ...s,
          tabs: s.tabs.filter((t) => t.id !== id),
          entries: s.entries.map((e) => (e.tabs.includes(id) ? { ...e, tabs: e.tabs.filter((t) => t !== id) } : e)),
        }))
        if (onServer()) sync(categoryFor(id).then((cat) => cat !== undefined && deleteCategory(cat)))
      },
      toggleInTab: (entryId: string, tabId: string) => {
        const e = find(entryId)
        if (!e) return
        const on = !e.tabs.includes(tabId)
        tabsTouched.add(entryId)
        editEntry(entryId, (x) => ({ ...x, tabs: on ? [...x.tabs, tabId] : x.tabs.filter((t) => t !== tabId) }))
        const mangaId = e.remote?.mangaId
        if (mangaId !== undefined) sync(categoryFor(tabId).then((cat) => cat !== undefined && setMangaCategory(mangaId, cat, on)))
      },
      addTab: (name: string, filters: LibraryFilters) =>
        set((s) => ({ ...s, tabs: [...s.tabs, { id: `smart-${Date.now().toString(36)}`, kind: 'smart', name, filters }] })),
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
  const latest = useRef(state)
  latest.current = state
  const set = useCallback((fn: (s: State) => State) => setState(fn), [])
  const get = useCallback(() => latest.current, [])
  const actions = useActions(set, get)
  const { serverUrl, serverUser, serverPass } = useSettings()

  // With a server address the library comes from Suwayomi; without one the app shows sample data.
  const scope = serverUrl ? serverUrl.trim().replace(/\/+$/, '') : SAMPLE_SCOPE
  useEffect(() => {
    if (!serverUrl) {
      setState((s) => ({ ...s, ...sampleState(), sources: SOURCES, queue: SAMPLE_QUEUE, server: { status: 'off' } }))
      return
    }
    let alive = true
    const saved = loadLayout(scope)
    // Until the server answers, show the tabs as they were last time.
    setState((s) => ({ ...s, entries: [], queue: [], tabs: saved?.tabs ?? DEVICE_TABS, server: { status: 'loading' } }))
    Promise.all([getLibrary(), getCategories()])
      .then(([list, categories]) => alive && setState((s) => ({
        ...s,
        entries: list.map((m) => toEntry(m)),
        tabs: mergeTabs(saved?.tabs, categories),
        server: { status: 'ready' },
      })))
      .catch((e: Error) => alive && setState((s) => ({ ...s, server: { status: 'error', error: e.message } })))
    return () => { alive = false }
  }, [scope, serverUrl, serverUser, serverPass])

  // Remember the layout. Nothing is saved while a server library is loading or failed, so it is not wiped.
  const { tabs, entries, server } = state
  useEffect(() => {
    if (server.status === 'off') saveLayout(SAMPLE_SCOPE, { tabs, memberships: Object.fromEntries(entries.map((e) => [e.id, e.tabs])) })
  }, [server.status, tabs, entries])
  useEffect(() => {
    if (server.status === 'ready') saveLayout(scope, { tabs })
  }, [server.status, scope, tabs])

  // On a server, the Reading tab lists titles started and not finished, most recently read first.
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
