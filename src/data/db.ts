import { createClient, type Session } from '@supabase/supabase-js'
import { useSyncExternalStore } from 'react'
import type { LibraryFilters, LibraryTab } from './types'

/**
 * Midoku's own database (Supabase). It holds the library, tabs, reading progress and chapter marks
 * for the signed-in person. Suwayomi is never written to.
 * The publishable key is meant to ship in the app; row-level security keeps each person's rows private.
 */
const URL = import.meta.env.VITE_SUPABASE_URL || 'https://ujrklbjeqbvzqdcrcthw.supabase.co'
const KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_6Y9ApBecGpjltrzKl1XOlQ_6o1YneEN'

export const db = createClient(URL, KEY, { auth: { persistSession: true, autoRefreshToken: true } })

// Sign-in state

interface Auth { ready: boolean; userId: string | null; email: string | null }
let auth: Auth = { ready: false, userId: null, email: null }
const listeners = new Set<() => void>()
/** The password is asked again this long after it was last entered on the device. */
const PASSWORD_DAYS = 10
const ENTERED_KEY = 'midoku.passwordAt'
const readEntered = () => { try { return Number(localStorage.getItem(ENTERED_KEY)) || 0 } catch { return 0 } }
const writeEntered = (t: number | null) => {
  try {
    if (t) localStorage.setItem(ENTERED_KEY, String(t))
    else localStorage.removeItem(ENTERED_KEY)
  } catch {
    // Without storage the session still works; the password is then asked on the next launch.
  }
}
const expired = () => Date.now() - readEntered() > PASSWORD_DAYS * 86_400_000

const setSession = (s: Session | null) => {
  // An old session counts as locked; it is signed out so the password is asked again.
  if (s && expired()) {
    s = null
    db.auth.signOut({ scope: 'local' }).catch(() => {})
  }
  const next = { ready: true, userId: s?.user.id ?? null, email: s?.user.email ?? null }
  if (next.ready === auth.ready && next.userId === auth.userId && next.email === auth.email) return
  auth = next
  listeners.forEach((l) => l())
}
db.auth.getSession().then(({ data }) => setSession(data.session))
db.auth.onAuthStateChange((_event, s) => setSession(s))
// An app left open in the background is checked again when it comes back.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && auth.userId && expired()) db.auth.getSession().then(({ data }) => setSession(data.session))
})

export const useAuth = () => useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l) }, () => auth)

const fail = (error: { message: string } | null) => { if (error) throw new Error(error.message) }

/**
 * Midoku has a single built-in user; the app password is that user's password.
 * Signing in keeps the session on the device; the password is asked again every 10 days (or after "Lock now").
 */
const OWNER_EMAIL = 'owner@midoku.invalid'

export async function enterPassword(password: string) {
  writeEntered(Date.now())
  const { error } = await db.auth.signInWithPassword({ email: OWNER_EMAIL, password })
  if (error) {
    writeEntered(null)
    throw new Error(/invalid/i.test(error.message) ? 'Wrong password.' : error.message)
  }
}
export async function changePassword(password: string) {
  fail((await db.auth.updateUser({ password })).error)
}
export async function lockApp() {
  writeEntered(null)
  fail((await db.auth.signOut()).error)
}

// Rows

export interface EntryRow {
  id: string
  title: string
  author: string
  cover_path: string | null
  description: string
  tags: string[]
  publishing: string
  parent_id: string | null
  in_library: boolean
  added_at?: string
  last_read_at: string | null
}
export interface EntrySourceRow {
  entry_id: string
  source_id: string
  manga_url: string
  server_manga_id: number | null
  source_name: string | null
  following: boolean
  is_main: boolean
}
export interface ChapterStateRow {
  entry_id: string
  source_id: string
  chapter_url: string
  chapter_number: number | null
  page: number
  read: boolean
  bookmarked: boolean
  removed: boolean
}
export interface TabRow {
  id: string
  kind: LibraryTab['kind']
  name: string
  filters: LibraryFilters | null
  position: number
}

export interface DbLibrary {
  entries: EntryRow[]
  sources: EntrySourceRow[]
  tabs: TabRow[]
  entryTabs: { entry_id: string; tab_id: string }[]
  progress: { entry_id: string; read_count: number }[]
}

async function all<T>(q: PromiseLike<{ data: T[] | null; error: { message: string } | null }>): Promise<T[]> {
  const { data, error } = await q
  fail(error)
  return data ?? []
}

export async function loadLibrary(): Promise<DbLibrary> {
  const [entries, sources, tabs, entryTabs, progress] = await Promise.all([
    all<EntryRow>(db.from('entries').select('id, title, author, cover_path, description, tags, publishing, parent_id, in_library, added_at, last_read_at')),
    all<EntrySourceRow>(db.from('entry_sources').select('entry_id, source_id, manga_url, server_manga_id, source_name, following, is_main')),
    all<TabRow>(db.from('tabs').select('id, kind, name, filters, position').order('position')),
    all<{ entry_id: string; tab_id: string }>(db.from('entry_tabs').select('entry_id, tab_id')),
    all<{ entry_id: string; read_count: number }>(db.from('entry_progress').select('entry_id, read_count')),
  ])
  return { entries, sources, tabs, entryTabs, progress }
}

export const loadChapterStates = (entryId: string) =>
  all<ChapterStateRow>(db.from('chapter_states').select('entry_id, source_id, chapter_url, chapter_number, page, read, bookmarked, removed').eq('entry_id', entryId))

const run = async (q: PromiseLike<{ error: { message: string } | null }>) => fail((await q).error)

export const saveEntry = (row: EntryRow) => run(db.from('entries').upsert(row))
export const updateEntry = (id: string, patch: Partial<EntryRow>) =>
  run(db.from('entries').update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id))
export const saveEntrySource = (row: EntrySourceRow) => run(db.from('entry_sources').upsert(row, { onConflict: 'entry_id,source_id,manga_url' }))
export const saveTabs = (rows: TabRow[]) => run(db.from('tabs').upsert(rows))
export const deleteTabRow = (id: string) => run(db.from('tabs').delete().eq('id', id))
export const setEntryTab = (entryId: string, tabId: string, on: boolean) =>
  run(on ? db.from('entry_tabs').upsert({ entry_id: entryId, tab_id: tabId }) : db.from('entry_tabs').delete().eq('entry_id', entryId).eq('tab_id', tabId))
export const saveChapterStates = (rows: ChapterStateRow[]) =>
  run(db.from('chapter_states').upsert(rows.map((r) => ({ ...r, updated_at: new Date().toISOString() })), { onConflict: 'entry_id,source_id,chapter_url' }))
