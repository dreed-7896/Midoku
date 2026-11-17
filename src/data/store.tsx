import { createContext, ReactNode, useCallback, useContext, useMemo, useState } from 'react'
import { ENTRIES, SOURCES } from './mock'
import type { Chapter, Entry, LibraryFilters, LibraryTab, Source, Status } from './types'

interface State {
  entries: Entry[]
  sources: Source[]
  queue: string[]
  tabs: LibraryTab[]
  updatesSeen: boolean
  toastMessage: string | null
}

const initial: State = {
  entries: ENTRIES,
  sources: SOURCES,
  queue: ['salt-static', 'paper-tigers', 'night-bus', 'quiet-tide', 'low-orbit', 'glasswing'],
  tabs: [
    { id: 'reading', kind: 'reading', name: 'Reading' },
    { id: 'all', kind: 'all', name: 'All' },
    { id: 'webtoons', kind: 'smart', name: 'Webtoons', filters: { statuses: [], newOnly: false, progress: 'any', tag: 'Webtoon' } },
    { id: 'favourites', kind: 'group', name: 'Favourites', entryIds: ['hollow-crown', 'paper-tigers', 'vapor-hearts'] },
  ],
  updatesSeen: false,
  toastMessage: null,
}

function useActions(set: (fn: (s: State) => State) => void) {
  return useMemo(() => {
    const editEntry = (id: string, fn: (e: Entry) => Entry) =>
      set((s) => ({ ...s, entries: s.entries.map((e) => (e.id === id ? fn(e) : e)) }))
    let toastTimer: ReturnType<typeof setTimeout> | undefined
    return {
      editEntry,
      setStatus: (id: string, status: Status) => editEntry(id, (e) => ({ ...e, status })),
      toggleLibrary: (id: string) => editEntry(id, (e) => ({ ...e, inLibrary: !e.inLibrary })),
      toggleFollow: (id: string, sourceId: string) =>
        editEntry(id, (e) => ({ ...e, sources: e.sources.map((s) => (s.sourceId === sourceId ? { ...s, following: !s.following } : s)) })),
      editChapters: (id: string, chapterIds: Set<string>, patch: Partial<Chapter>) =>
        editEntry(id, (e) => ({ ...e, chapters: e.chapters.map((c) => (chapterIds.has(c.id) ? { ...c, ...patch } : c)) })),
      toggleInstall: (sourceId: string) =>
        set((s) => ({ ...s, sources: s.sources.map((x) => (x.id === sourceId ? { ...x, installed: !x.installed, update: false } : x)) })),
      togglePin: (sourceId: string) =>
        set((s) => ({ ...s, sources: s.sources.map((x) => (x.id === sourceId ? { ...x, pinned: !x.pinned } : x)) })),
      updateAll: () => set((s) => ({ ...s, sources: s.sources.map((x) => ({ ...x, update: false })) })),
      clearWarning: (sourceId: string) =>
        set((s) => ({ ...s, sources: s.sources.map((x) => (x.id === sourceId ? { ...x, warn: undefined } : x)) })),
      markUpdatesSeen: () => set((s) => ({ ...s, updatesSeen: true })),
      addTab: (name: string, filters: LibraryFilters) =>
        set((s) => ({ ...s, tabs: [...s.tabs, { id: `tab-${Date.now()}`, kind: 'smart', name, filters }] })),
      toast: (message: string) => {
        set((s) => ({ ...s, toastMessage: message }))
        clearTimeout(toastTimer)
        toastTimer = setTimeout(() => set((s) => ({ ...s, toastMessage: null })), 2200)
      },
    }
  }, [set])
}

type Store = State & ReturnType<typeof useActions> & {
  entry: (id: string) => Entry | undefined
  source: (id: string) => Source | undefined
  children: (id: string) => Entry[]
}

const Ctx = createContext<Store | null>(null)

export function StoreProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState(initial)
  const set = useCallback((fn: (s: State) => State) => setState(fn), [])
  const actions = useActions(set)
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
export const unreadCount = (e: Entry) => visibleChapters(e).filter((c) => !c.read).length
export const newCount = (e: Entry) => visibleChapters(e).filter((c) => c.isNew && !c.read).length
export const readCount = (e: Entry) => visibleChapters(e).filter((c) => c.read).length

/** The chapter the reader resumes: the first unread one in reading order. */
export function resumeChapter(e: Entry): Chapter | undefined {
  return [...visibleChapters(e)].sort((a, b) => a.number - b.number).find((c) => !c.read)
}

export function progressPct(e: Entry): number {
  const total = visibleChapters(e).length
  return total ? Math.round((readCount(e) / total) * 100) : 0
}

export function agoLabel(hours: number): string {
  if (hours < 1) return 'now'
  if (hours < 24) return `${Math.round(hours)}h`
  const d = Math.round(hours / 24)
  return d < 7 ? `${d}d` : `${Math.round(d / 7)}w`
}
