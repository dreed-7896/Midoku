import { useCallback, useEffect, useMemo, useState } from 'react'
import { Cover } from '../components/Art'
import { IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { useNav } from '../components/Nav'
import { Banner, Empty, Loading } from '../components/Status'
import { byDay, timeLabel } from '../data/dates'
import { loadPageUpdates, loadReadMarks } from '../data/db'
import { openChapter } from '../data/openChapter'
import { useStore } from '../data/store'
import { getRecentChapters, toChapter } from '../data/suwayomi'
import type { Entry } from '../data/types'

/** A new chapter, or new pages in a chapter, of a library title. */
interface Update {
  key: string
  entry: Entry
  label: string
  detail: string
  at: number
  read: boolean
  pages?: { before: number; now: number }
  chapterId?: string
  sourceId?: string
  url?: string
}

const DAY = 86_400_000

export default function Updates() {
  const store = useStore()
  const nav = useNav()
  const server = store.server.status !== 'off'
  const [items, setItems] = useState<Update[] | null>(null)
  const [error, setError] = useState<string>()
  const [opening, setOpening] = useState<string>()

  const load = useCallback(async () => {
    setError(undefined)
    const library = store.entries.filter((e) => e.inLibrary)
    try {
      if (!server) {
        setItems(library.flatMap((e) => e.chapters.filter((c) => c.isNew).map((c): Update => ({
          key: `${e.id}/${c.id}`, entry: e, label: c.label, detail: c.title, at: Date.now() - e.updatedAgo * 3_600_000, read: c.read, chapterId: c.id,
        }))).sort((a, b) => b.at - a.at))
        return
      }
      // Newest chapters of every followed source, then Midoku's read marks for them.
      const byManga = new Map<number, Entry>()
      for (const e of library) for (const s of e.sources) if (s.following && s.mangaId != null) byManga.set(s.mangaId, e)
      const [recent, grown] = await Promise.all([getRecentChapters([...byManga.keys()]), loadPageUpdates()])
      const marks = await loadReadMarks(recent.map((c) => c.url))
      const isRead = (dbId: string | undefined, sourceId: string, url: string) => marks.some((m) => m.entry_id === dbId && m.source_id === sourceId && m.chapter_url === url && m.read)
      const out: Update[] = []
      for (const c of recent) {
        const e = byManga.get(c.mangaId)
        const at = Number(c.uploadDate)
        if (!e || !(at > 0)) continue
        const sourceId = e.sources.find((s) => s.mangaId === c.mangaId)?.sourceId ?? ''
        const ch = toChapter(c, sourceId)
        out.push({ key: `c${c.id}`, entry: e, label: ch.label, detail: ch.title, at, read: isRead(e.dbId, sourceId, c.url), sourceId, url: c.url })
      }
      for (const g of grown) {
        const e = library.find((x) => x.dbId === g.entry_id)
        if (!e) continue
        out.push({
          key: `p${g.entry_id}/${g.chapter_url}`, entry: e, label: g.chapter_label || 'Chapter', detail: `${g.pages_before} → ${g.pages} pages`,
          at: Date.parse(g.pages_grew_at), read: false, pages: { before: g.pages_before, now: g.pages }, sourceId: g.source_id, url: g.chapter_url,
        })
      }
      // The last 60 days.
      setItems(out.filter((u) => u.at > Date.now() - 60 * DAY).sort((a, b) => b.at - a.at))
    } catch (e) {
      setError((e as Error).message)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [server, store.entries.length])
  useEffect(() => { if (store.server.status !== 'loading' && store.server.status !== 'signin') void load() }, [load, store.server.status])
  // Opening Updates clears the bell's badge.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { store.markUpdatesSeen() }, [])

  const groups = useMemo(() => byDay(items ?? [], (u) => u.at), [items])
  const check = async () => { await store.checkUpdates(); await load() }
  const open = async (u: Update) => {
    setOpening(u.key)
    try {
      await openChapter(store, (to) => nav.go(to), u.entry.id, { chapterId: u.chapterId, sourceId: u.sourceId, url: u.url })
    } catch (err) {
      store.toast(`Couldn't open it: ${(err as Error).message}`)
    } finally {
      setOpening(undefined)
    }
  }

  return (
    <div className="page">
      <div className="entry__top">
        <IconButton icon="back" label="Back" onClick={() => nav.back('/')} />
        {server && <IconButton icon="refresh" label="Check for new chapters" active={!!store.updating} onClick={() => void check()} />}
      </div>
      <header className="pad-x pad-t">
        <h1 className="h1">Updates</h1>
      </header>
      {store.updating && <div className="pad-x pad-t-sm"><Banner tone="busy">Checking for new chapters and pages… {store.updating.done} of {store.updating.total}</Banner></div>}

      {error && <div className="pad-x pad-t"><Empty icon="alert" tone="error" title="Couldn't load updates" detail={error} action={{ label: 'Try again', onClick: () => void load() }} /></div>}
      {!items && !error && <div className="pad-x pad-t"><Loading label="Loading updates" shape="rows" /></div>}
      {items && !items.length && <div className="pad-x pad-t"><Empty icon="bell" title="No updates" detail="New chapters, and new pages in recent chapters, from your library show up here." /></div>}

      {groups.map(([day, list]) => (
        <section key={day} className="section section--tight pad-x">
          <div className="label label--flush">{day}</div>
          <div className="check-list">
            {list.map((u) => (
              <button key={u.key} type="button" className={`order-row history-row plain-btn${u.read ? ' is-read' : ''}`} disabled={opening === u.key} onClick={() => void open(u)}>
                <span className="order-row__cover"><Cover art={u.entry.art} title={u.entry.title} url={u.entry.coverUrl} /></span>
                <span className="check-row__name check-row__name--stack grow">
                  <strong className="ellipsis">{u.entry.title}</strong>
                  <span className="card-meta ellipsis">{u.label} · {u.detail}</span>
                </span>
                {u.pages ? <span className="tag tag--accent">+{u.pages.now - u.pages.before} pages</span>
                  : u.read ? <Icon name="check" size={16} /> : <span className="card-meta">{timeLabel(u.at)}</span>}
              </button>
            ))}
          </div>
        </section>
      ))}
    </div>
  )
}
