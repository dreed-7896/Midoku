import { visibleChapters, type Store } from './store'
import type { Chapter } from './types'

type Find = { chapterId?: string; sourceId?: string; url?: string }

/** The chapter as the title holds it (loading the title's chapters when needed). */
export async function findChapter(store: Store, entryId: string, find: Find): Promise<Chapter | undefined> {
  const first = store.entry(entryId)
  if (!first) return undefined
  if (first.remote && !first.remote.chaptersLoaded) await store.loadEntry(entryId)
  const e = store.entry(entryId) ?? first
  return e.chapters.find((c) => find.chapterId ? c.id === find.chapterId
    : (c.sourceId === find.sourceId && c.sourceUrl === find.url) || !!c.alts?.some((a) => a.sourceId === find.sourceId && a.url === find.url))
}

/**
 * Opens a chapter found by its id (sample data) or by source + address (server), loading the title's
 * chapters first when needed. `nextIfRead` goes on to the following chapter when that one is finished.
 * Falls back to the title page when the chapter is gone.
 */
export async function openChapter(store: Store, go: (to: string) => void, entryId: string,
  find: { chapterId?: string; sourceId?: string; url?: string }, nextIfRead = false) {
  const first = store.entry(entryId)
  if (!first) return
  if (first.remote && !first.remote.chaptersLoaded) await store.loadEntry(entryId)
  const e = store.entry(entryId) ?? first
  const shown = [...visibleChapters(e)].sort((a, b) => a.number - b.number)
  const matches = (c: Chapter) => find.chapterId ? c.id === find.chapterId
    : (c.sourceId === find.sourceId && c.sourceUrl === find.url) || !!c.alts?.some((a) => a.sourceId === find.sourceId && a.url === find.url)
  const whole = e.chapters.find(matches)
  // A split chapter opens at its first unread part.
  const i = shown.findIndex((c) => matches(c) || (!!whole && c.physicalId === whole.id && !c.read))
  if (i < 0) { go(`/entry/${e.id}`); return }
  const c = nextIfRead && shown[i].read && shown[i + 1] ? shown[i + 1] : shown[i]
  go(`/read/${e.id}/${c.id}`)
}

/** Opens a page bookmark: the chapter (or the part of a split chapter holding that page) at that page. */
export async function openBookmark(store: Store, go: (to: string) => void, entryId: string, find: Find, page: number) {
  const whole = await findChapter(store, entryId, find)
  const e = store.entry(entryId)
  if (!whole || !e) { go(`/entry/${entryId}`); return }
  const part = visibleChapters(e).find((c) => c.physicalId === whole.id && c.range && page >= c.range[0] && page <= c.range[1])
  go(`/read/${e.id}/${(part ?? whole).id}?page=${page}`)
}
