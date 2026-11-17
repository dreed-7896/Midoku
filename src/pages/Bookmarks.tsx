import { useEffect, useMemo, useState } from 'react'
import { Cover } from '../components/Art'
import { IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { useNav } from '../components/Nav'
import { Empty, Loading } from '../components/Status'
import { loadPageMarks } from '../data/db'
import { openBookmark } from '../data/openChapter'
import { useStore } from '../data/store'

interface Mark { entryId: string; sourceId: string; url: string; label: string; number: number; page: number }

/** Every bookmarked page in the library, grouped by title (like native Midoku's bookmarks). */
export default function Bookmarks() {
  const store = useStore()
  const nav = useNav()
  const server = store.server.status !== 'off'
  const [rows, setRows] = useState<Mark[] | null>(null)
  const [error, setError] = useState<string>()
  const [q, setQ] = useState('')
  const [opening, setOpening] = useState<string>()

  useEffect(() => {
    if (!server) {
      // Sample data keeps its bookmarks on the chapters.
      setRows(store.entries.flatMap((e) => e.chapters.filter((c) => c.marks?.length).flatMap((c) =>
        c.marks!.map((page) => ({ entryId: e.id, sourceId: c.sourceId, url: c.sourceUrl ?? c.id, label: c.label, number: c.number, page })))))
      return
    }
    if (store.server.status !== 'ready') return
    const byDb = new Map(store.entries.filter((e) => e.dbId).map((e) => [e.dbId!, e.id]))
    loadPageMarks()
      .then((list) => setRows(list.flatMap((r) => {
        const entryId = byDb.get(r.entry_id)
        if (!entryId) return []
        const label = r.chapter_label?.split(' · ')[0] ?? (r.chapter_number != null ? `Ch. ${Number(r.chapter_number)}` : 'Chapter')
        return r.marks.map((page) => ({ entryId, sourceId: r.source_id, url: r.chapter_url, label, number: Number(r.chapter_number ?? 0), page }))
      })))
      .catch((e: Error) => setError(e.message))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [server, store.server.status])

  const groups = useMemo(() => {
    const map = new Map<string, Mark[]>()
    for (const m of rows ?? []) map.set(m.entryId, [...(map.get(m.entryId) ?? []), m])
    const needle = q.trim().toLowerCase()
    return [...map.entries()]
      .map(([entryId, list]) => ({ entry: store.entry(entryId), list: list.sort((a, b) => a.number - b.number || a.page - b.page) }))
      .filter((g) => g.entry && (!needle || g.entry.title.toLowerCase().includes(needle)))
      .sort((a, b) => a.entry!.title.localeCompare(b.entry!.title))
  }, [rows, q, store])

  const open = async (m: Mark) => {
    const key = `${m.url}#${m.page}`
    setOpening(key)
    try { await openBookmark(store, (to) => nav.go(to), m.entryId, server ? { sourceId: m.sourceId, url: m.url } : { chapterId: m.url }, m.page) }
    catch (e) { store.toast(`Couldn't open it: ${(e as Error).message}`) }
    finally { setOpening(undefined) }
  }
  const remove = async (m: Mark) => {
    const e = store.entry(m.entryId)
    if (!e) return
    if (e.remote && !e.remote.chaptersLoaded) await store.loadEntry(e.id).catch(() => {})
    const c = store.entry(e.id)?.chapters.find((x) => (server ? (x.sourceId === m.sourceId && x.sourceUrl === m.url) || x.alts?.some((a) => a.sourceId === m.sourceId && a.url === m.url) : x.id === m.url))
    if (!c) { store.toast("Couldn't find that chapter"); return }
    store.toggleMark(e.id, c.id, m.page)
    setRows((r) => r?.filter((x) => x !== m) ?? null)
  }
  const count = rows?.length ?? 0

  return (
    <div className="page">
      <div className="entry__top"><IconButton icon="back" label="Back" onClick={() => nav.back('/library')} /></div>
      <header className="pad-x pad-t">
        <h1 className="h1">Bookmarks</h1>
        <div className="card-meta pad-t-sm">{rows ? `${count} page${count === 1 ? '' : 's'} in ${groups.length} title${groups.length === 1 ? '' : 's'}` : 'Loading…'}</div>
      </header>
      {count > 6 && <div className="pad-x pad-t-sm"><label className="field"><Icon name="search" size={18} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search titles" aria-label="Search titles" /></label></div>}
      {error && <div className="pad-x pad-t"><Empty icon="alert" tone="error" title="Couldn't load bookmarks" detail={error} /></div>}
      {!rows && !error && <div className="pad-x pad-t"><Loading label="Loading bookmarks" shape="rows" /></div>}
      {rows && !count && <div className="pad-x pad-t"><Empty icon="bookmark" title="No bookmarked pages" detail="In the reader, tap the bookmark button to mark the page you're on." /></div>}
      {groups.map(({ entry, list }) => (
        <section key={entry!.id} className="section section--tight pad-x">
          <button type="button" className="order-row history-row plain-btn mark-head" onClick={() => nav.go(`/entry/${entry!.id}`)}>
            <Cover art={entry!.art} title={entry!.title} url={entry!.coverUrl} className="order-row__cover" />
            <span className="check-row__name check-row__name--stack grow"><strong className="ellipsis">{entry!.title}</strong><span className="card-meta">{list.length} page{list.length === 1 ? '' : 's'}</span></span>
            <Icon name="chevronRight" size={16} />
          </button>
          <div className="check-list">
            {list.map((m) => (
              <div key={`${m.url}#${m.page}`} className="check-row">
                <button type="button" className="check-row__name grow plain-btn" disabled={!!opening} onClick={() => void open(m)}>
                  <Icon name="bookmarkFill" size={14} /><span className="ellipsis">{m.label} · page {m.page}{opening === `${m.url}#${m.page}` ? ' · opening…' : ''}</span>
                </button>
                <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove bookmark on ${m.label} page ${m.page}`} onClick={() => void remove(m)}><Icon name="x" size={16} /></button>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  )
}
