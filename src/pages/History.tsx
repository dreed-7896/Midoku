import { useCallback, useEffect, useMemo, useState } from 'react'
import { Cover } from '../components/Art'
import { IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { useNav } from '../components/Nav'
import { Empty, Loading } from '../components/Status'
import { clearHistoryRows, loadHistory } from '../data/db'
import { clearLocalHistory, readLocalHistory } from '../data/history'
import { dayLabel, timeLabel } from '../data/dates'
import { openChapter } from '../data/openChapter'
import { useStore } from '../data/store'
import type { Entry } from '../data/types'

/** One title's latest read: the History screen shows one row per title, newest first. */
interface Item {
  entry: Entry
  label: string
  page: number
  read: boolean
  at: number
  /** Sample mode knows the chapter id; with a server the chapter is found by source + url. */
  chapterId?: string
  sourceId?: string
  chapterUrl?: string
}

export default function History() {
  const store = useStore()
  const nav = useNav()
  const server = store.server.status !== 'off'
  const [items, setItems] = useState<Item[] | null>(null)
  const [error, setError] = useState<string>()
  const [query, setQuery] = useState('')
  const [opening, setOpening] = useState<string>()

  const load = useCallback(async () => {
    setError(undefined)
    try {
      const seen = new Set<string>()
      const out: Item[] = []
      if (server) {
        for (const r of await loadHistory()) {
          const entry = store.entries.find((e) => e.dbId === r.entry_id)
          if (!entry || seen.has(entry.id)) continue
          seen.add(entry.id)
          out.push({ entry, label: r.chapter_label || (r.chapter_number != null ? `Chapter ${r.chapter_number}` : 'Chapter'), page: r.page, read: r.read, at: Date.parse(r.read_at), sourceId: r.source_id, chapterUrl: r.chapter_url })
        }
      } else {
        for (const r of readLocalHistory()) {
          const entry = store.entry(r.entryId)
          if (!entry || seen.has(entry.id)) continue
          seen.add(entry.id)
          out.push({ entry, label: r.label, page: r.page, read: r.read, at: r.at, chapterId: r.chapterId })
        }
      }
      setItems(out)
    } catch (e) {
      setError((e as Error).message)
    }
    // Entries are looked up once per load; reloading on every library change would refetch constantly.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [server, store.entries.length])
  useEffect(() => { if (store.server.status !== 'loading' && store.server.status !== 'signin') void load() }, [load, store.server.status])

  const q = query.trim().toLowerCase()
  const groups = useMemo(() => {
    const map = new Map<string, Item[]>()
    for (const it of items ?? []) {
      if (q && !it.entry.title.toLowerCase().includes(q)) continue
      const k = dayLabel(it.at)
      map.set(k, [...(map.get(k) ?? []), it])
    }
    return [...map.entries()]
  }, [items, q])

  const remove = (it: Item) => {
    if (server) { if (it.entry.dbId) clearHistoryRows(it.entry.dbId) } else clearLocalHistory(it.entry.id)
    setItems((list) => list?.filter((x) => x !== it) ?? null)
    store.toast(`Removed ${it.entry.title} from history`)
  }
  const clearAll = () => {
    if (!window.confirm('Clear all reading history? Progress and read marks stay.')) return
    if (server) clearHistoryRows(null); else clearLocalHistory()
    setItems([])
  }

  /** Opens the chapter last read; a finished one goes on to the next chapter. */
  const resume = async (it: Item) => {
    setOpening(it.entry.id)
    try {
      await openChapter(store, (to) => nav.go(to), it.entry.id, { chapterId: it.chapterId, sourceId: it.sourceId, url: it.chapterUrl }, true)
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
        {!!items?.length && <IconButton icon="trash" label="Clear all history" onClick={clearAll} />}
      </div>
      <header className="pad-x pad-t">
        <h1 className="h1">History</h1>
      </header>
      {!!items?.length && (
        <div className="pad-x pad-t-sm">
          <label className="field">
            <Icon name="search" size={18} />
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search history" aria-label="Search history" />
          </label>
        </div>
      )}

      {error && <div className="pad-x pad-t"><Empty icon="alert" tone="error" title="Couldn't load history" detail={error} action={{ label: 'Try again', onClick: () => void load() }} /></div>}
      {!items && !error && <div className="pad-x pad-t"><Loading label="Loading history" shape="rows" /></div>}
      {items && !items.length && <div className="pad-x pad-t"><Empty icon="clock" title="No history yet" detail="Chapters you read show up here, newest first." /></div>}
      {items && items.length > 0 && !groups.length && <div className="pad-x pad-t"><Empty icon="search" title={`Nothing matches “${query}”`} /></div>}

      {groups.map(([day, list]) => (
        <section key={day} className="section section--tight pad-x">
          <div className="label label--flush">{day}</div>
          <div className="check-list">
            {list.map((it) => (
              <div key={it.entry.id} className="order-row history-row">
                <button type="button" className="plain-btn order-row__cover" aria-label={`Open ${it.entry.title}`} onClick={() => nav.go(`/entry/${it.entry.id}`)}>
                  <Cover art={it.entry.art} title={it.entry.title} url={it.entry.coverUrl} />
                </button>
                <button type="button" className="check-row__name check-row__name--stack grow plain-btn" onClick={() => nav.go(`/entry/${it.entry.id}`)}>
                  <strong className="ellipsis">{it.entry.title}</strong>
                  <span className="card-meta">{it.label}{it.read ? ' · read' : it.page ? ` · page ${it.page}` : ''} · {timeLabel(it.at)}</span>
                </button>
                <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove ${it.entry.title} from history`} onClick={() => remove(it)}><Icon name="trash" size={16} /></button>
                <button type="button" className="icon-btn icon-btn--sm icon-btn--accent" aria-label={`Resume ${it.entry.title}`} disabled={opening === it.entry.id} onClick={() => void resume(it)}><Icon name="play" size={14} /></button>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  )
}
