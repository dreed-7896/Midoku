import { createClient, type Session } from '@supabase/supabase-js'
import { useSyncExternalStore } from 'react'
import type { CustomDetails, LibraryFilters, LibraryTab } from './types'

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
db.auth.onAuthStateChange((_event, s) => {
  setSession(s)
  if (s) void flushWrites()
})
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
  custom: CustomDetails
  position: number
  renumber: boolean
}
export interface EntrySourceRow {
  entry_id: string
  source_id: string
  manga_url: string
  server_manga_id: number | null
  source_name: string | null
  following: boolean
  is_main: boolean
  segment: number
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
  preferred: boolean
  position: number | null
  /** Set when the chapter is read in the reader; drives the History screen. */
  read_at?: string | null
  chapter_label?: string | null
  /** Set by the update check when a chapter gets more pages. */
  pages?: number | null
  pages_before?: number | null
  pages_grew_at?: string | null
}
export interface SplitRow { entry_id: string; source_id: string; chapter_url: string; breaks: number[]; excluded: number[] }
export interface InsertedRow {
  id: string
  entry_id: string
  source_id: string
  manga_url: string
  chapter_url: string
  server_chapter_id: number | null
  number: number
  label: string
  from_title: string
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
    all<EntryRow>(db.from('entries').select('id, title, author, cover_path, description, tags, publishing, parent_id, in_library, added_at, last_read_at, custom, position, renumber')),
    all<EntrySourceRow>(db.from('entry_sources').select('entry_id, source_id, manga_url, server_manga_id, source_name, following, is_main, segment')),
    all<TabRow>(db.from('tabs').select('id, kind, name, filters, position').order('position')),
    all<{ entry_id: string; tab_id: string }>(db.from('entry_tabs').select('entry_id, tab_id')),
    all<{ entry_id: string; read_count: number }>(db.from('entry_progress').select('entry_id, read_count')),
  ])
  return { entries, sources, tabs, entryTabs, progress }
}

/** A saved title's reading state, split chapters and inserted chapters. */
export async function loadEntryExtras(entryId: string) {
  const [states, splits, inserts] = await Promise.all([
    all<ChapterStateRow>(db.from('chapter_states').select('entry_id, source_id, chapter_url, chapter_number, page, read, bookmarked, removed, preferred, position, read_at, pages, pages_before, pages_grew_at').eq('entry_id', entryId)),
    all<SplitRow>(db.from('chapter_splits').select('entry_id, source_id, chapter_url, breaks, excluded').eq('entry_id', entryId)),
    all<InsertedRow>(db.from('inserted_chapters').select('id, entry_id, source_id, manga_url, chapter_url, server_chapter_id, number, label, from_title').eq('entry_id', entryId)),
  ])
  return { states, splits, inserts }
}

// Writes: an ordered outbox kept in localStorage. Each change is queued, then sent in order; without a
// connection the queue waits and is sent when the device is back online, so nothing done offline is lost.
// Order matters: a title's row is written before the tabs, sources and chapter states that refer to it.

type Match = Record<string, string>
type Op =
  | { kind: 'upsert'; table: string; rows: object[]; onConflict?: string }
  | { kind: 'update'; table: string; patch: object; match: Match }
  | { kind: 'delete'; table: string; match: Match }
  | { kind: 'rpc'; fn: string; args: object }

const OUTBOX_KEY = 'midoku.outbox'
let outbox: Op[] = (() => { try { return JSON.parse(localStorage.getItem(OUTBOX_KEY) ?? '[]') } catch { return [] } })()
const outboxListeners = new Set<() => void>()
const errorListeners = new Set<(message: string) => void>()
let pendingCount = outbox.length
function persistOutbox() {
  try { localStorage.setItem(OUTBOX_KEY, JSON.stringify(outbox)) } catch { /* kept in memory for this session */ }
  pendingCount = outbox.length
  outboxListeners.forEach((l) => l())
}

/** Number of changes not yet saved in the database. */
export const usePendingWrites = () => useSyncExternalStore((l) => { outboxListeners.add(l); return () => outboxListeners.delete(l) }, () => pendingCount)
/** Called when the database refuses a change (not for missing connection). */
export const onWriteError = (fn: (message: string) => void) => { errorListeners.add(fn); return () => { errorListeners.delete(fn) } }

const networkError = (message: string) => !navigator.onLine || /fetch|network|load failed|timed? ?out/i.test(message)

async function send(op: Op) {
  if (op.kind === 'rpc') { fail((await db.rpc(op.fn, op.args)).error); return }
  const t = db.from(op.table)
  const { error } = await (op.kind === 'upsert' ? t.upsert(op.rows, op.onConflict ? { onConflict: op.onConflict } : undefined)
    : op.kind === 'update' ? t.update(op.patch).match(op.match)
    : t.delete().match(op.match))
  if (error) throw new Error(error.message)
}

let flushing: Promise<boolean> | null = null
/** Sends queued changes in order. Resolves true once the queue is empty. */
export function flushWrites(): Promise<boolean> {
  if (flushing) return flushing
  flushing = (async () => {
    while (outbox.length && auth.userId) {
      try {
        await send(outbox[0])
      } catch (e) {
        const message = (e as Error).message
        if (networkError(message)) return false
        errorListeners.forEach((l) => l(message))
      }
      outbox.shift()
      persistOutbox()
    }
    return outbox.length === 0
  })().finally(() => { flushing = null })
  return flushing
}

function enqueue(op: Op) {
  outbox.push(op)
  persistOutbox()
  void flushWrites()
}

window.addEventListener('online', () => void flushWrites())
setInterval(() => { if (outbox.length && navigator.onLine) void flushWrites() }, 30_000)

const now = () => new Date().toISOString()

export const saveEntry = (row: EntryRow) => enqueue({ kind: 'upsert', table: 'entries', rows: [row] })
export const updateEntry = (id: string, patch: Partial<EntryRow>) =>
  enqueue({ kind: 'update', table: 'entries', patch: { ...patch, updated_at: now() }, match: { id } })
export const saveEntrySource = (row: EntrySourceRow) => enqueue({ kind: 'upsert', table: 'entry_sources', rows: [row], onConflict: 'entry_id,source_id,manga_url' })
export const updateEntrySource = (match: { entry_id: string; source_id?: string; manga_url?: string }, patch: Partial<EntrySourceRow>) =>
  enqueue({ kind: 'update', table: 'entry_sources', patch, match: match as Match })
export const deleteEntrySource = (entryId: string, sourceId: string, mangaUrl: string) =>
  enqueue({ kind: 'delete', table: 'entry_sources', match: { entry_id: entryId, source_id: sourceId, manga_url: mangaUrl } })
export const saveTabs = (rows: TabRow[]) => enqueue({ kind: 'upsert', table: 'tabs', rows })
export const deleteTabRow = (id: string) => enqueue({ kind: 'delete', table: 'tabs', match: { id } })
export const setEntryTab = (entryId: string, tabId: string, on: boolean) =>
  enqueue(on ? { kind: 'upsert', table: 'entry_tabs', rows: [{ entry_id: entryId, tab_id: tabId }] }
    : { kind: 'delete', table: 'entry_tabs', match: { entry_id: entryId, tab_id: tabId } })
export const saveChapterStates = (rows: ChapterStateRow[]) =>
  enqueue({ kind: 'upsert', table: 'chapter_states', rows: rows.map((r) => ({ ...r, updated_at: now() })), onConflict: 'entry_id,source_id,chapter_url' })
export const saveSplit = (row: SplitRow) => enqueue({ kind: 'upsert', table: 'chapter_splits', rows: [row], onConflict: 'entry_id,source_id,chapter_url' })
export const deleteSplit = (entryId: string, sourceId: string, chapterUrl: string) =>
  enqueue({ kind: 'delete', table: 'chapter_splits', match: { entry_id: entryId, source_id: sourceId, chapter_url: chapterUrl } })
export const saveInserted = (row: InsertedRow) => enqueue({ kind: 'upsert', table: 'inserted_chapters', rows: [row] })
export const deleteInserted = (id: string) => enqueue({ kind: 'delete', table: 'inserted_chapters', match: { id } })
export const deleteEntryRow = (id: string) => enqueue({ kind: 'delete', table: 'entries', match: { id } })
/** Merges titles into `keep` in the database (see merge_entries in the migrations). */
export const mergeEntryRows = (keep: string, parts: string[], segments: number[]) =>
  enqueue({ kind: 'rpc', fn: 'merge_entries', args: { keep, parts, segments } })

/** Clears reading history for one title (its row id), or for everything. */
export const clearHistoryRows = (entry: string | null) => enqueue({ kind: 'rpc', fn: 'clear_history', args: { entry } })

export interface HistoryRow { entry_id: string; source_id: string; chapter_url: string; chapter_label: string | null; chapter_number: number | null; page: number; read: boolean; read_at: string }
/** Recently read chapters, newest first. Waits for queued changes so the latest reads are included. */
export async function loadHistory(limit = 400): Promise<HistoryRow[]> {
  await flushWrites()
  return all<HistoryRow>(db.from('chapter_states').select('entry_id, source_id, chapter_url, chapter_label, chapter_number, page, read, read_at')
    .not('read_at', 'is', null).order('read_at', { ascending: false }).limit(limit))
}

/** Chapters that got new pages, newest first. */
export const loadPageUpdates = (limit = 100) =>
  all<HistoryRow & { pages: number; pages_before: number; pages_grew_at: string }>(db.from('chapter_states')
    .select('entry_id, source_id, chapter_url, chapter_label, chapter_number, page, read, read_at, pages, pages_before, pages_grew_at')
    .not('pages_grew_at', 'is', null).order('pages_grew_at', { ascending: false }).limit(limit))

/** Read marks for these source chapters. */
export const loadReadMarks = (urls: string[]) =>
  urls.length ? all<{ entry_id: string; source_id: string; chapter_url: string; read: boolean; page: number }>(
    db.from('chapter_states').select('entry_id, source_id, chapter_url, read, page').in('chapter_url', urls)) : Promise.resolve([])

/** Notes that a chapter got more pages (only these columns, so progress on an existing row is kept). */
export const notePageGrowth = (row: { entry_id: string; source_id: string; chapter_url: string; chapter_number: number; chapter_label: string; pages: number; pages_before: number }) =>
  enqueue({ kind: 'upsert', table: 'chapter_states', rows: [{ ...row, pages_grew_at: now() }], onConflict: 'entry_id,source_id,chapter_url' })
