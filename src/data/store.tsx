import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { ENTRIES, LIBRARY_TABS, SOURCES } from './mock'
import { useSettings } from './settings'
import { getLibrary, saveChapterProgress, setInLibrary, toEntry, updateChapters } from './suwayomi'
import type { Chapter, Entry, LibraryFilters, LibraryTab, Source, Status } from './types'

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
  entries: ENTRIES,
  sources: SOURCES,
  queue: ['salt-static', 'paper-tigers', 'night-bus', 'quiet-tide', 'low-orbit', 'glasswing'],
  tabs: LIBRARY_TABS,
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
    return {
      editEntry,
      toggleLibrary: (id: string) => {
        const e = find(id)
        editEntry(id, (x) => ({ ...x, inLibrary: !x.inLibrary }))
        if (e?.remote) sync(setInLibrary(e.remote.mangaId, !e.inLibrary))
      },
      /** Adds or refreshes a title loaded from the server, keeping the tabs it was filed in here. */
      upsertEntry: (entry: Entry) =>
        set((s) => {
          const old = s.entries.find((e) => e.id === entry.id)
          const next = old ? { ...entry, tabs: old.tabs } : entry
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
        return id
      },
      renameTab: (id: string, name: string) =>
        set((s) => ({ ...s, tabs: s.tabs.map((t) => (t.id === id ? { ...t, name } : t)) })),
      /** Deleting a tab keeps its titles in the library. */
      deleteTab: (id: string) =>
        set((s) => ({
          ...s,
          tabs: s.tabs.filter((t) => t.id !== id),
          entries: s.entries.map((e) => (e.tabs.includes(id) ? { ...e, tabs: e.tabs.filter((t) => t !== id) } : e)),
        })),
      toggleInTab: (entryId: string, tabId: string) =>
        editEntry(entryId, (e) => ({ ...e, tabs: e.tabs.includes(tabId) ? e.tabs.filter((t) => t !== tabId) : [...e.tabs, tabId] })),
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
  useEffect(() => {
    if (!serverUrl) {
      setState((s) => ({ ...s, entries: ENTRIES, sources: SOURCES, queue: SAMPLE_QUEUE, server: { status: 'off' } }))
      return
    }
    let alive = true
    setState((s) => ({ ...s, entries: [], queue: [], server: { status: 'loading' } }))
    getLibrary()
      .then((list) => alive && setState((s) => ({ ...s, entries: list.map((m) => toEntry(m)), server: { status: 'ready' } })))
      .catch((e: Error) => alive && setState((s) => ({ ...s, server: { status: 'error', error: e.message } })))
    return () => { alive = false }
  }, [serverUrl, serverUser, serverPass])
  const value = useMemo<Store>(() => ({
    ...state,
    ...actions,
    entry: (id) => state.entries.find((e) => e.id === id),
    source: (id) => state.sources.find((s) => s.id === id),
    children: (id) => state.entries.filter((e) => e.parentId === id && e.inLibrary),
  }), [state, actions])
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
