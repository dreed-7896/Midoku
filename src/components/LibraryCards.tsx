import { newCount, progressPct, resumeChapter, useStore, visibleChapters } from '../data/store'
import type { Entry } from '../data/types'
import { Cover } from './Art'
import { Icon } from './Icon'
import { TLink as Link } from './Nav'
import { createContext, useContext, type ReactNode } from 'react'
import { useLongPress } from './LongPress'

/** Library selection: cards toggle instead of opening. */
export interface Pick { selected: Set<string>; toggle: (id: string) => void }

/** Long-pressing a library card opens its options (set by the Library screen). */
export const CardMenu = createContext<((e: Entry) => void) | null>(null)

function CardShell({ entry, className, pick, children }: { entry: Entry; className: string; pick?: Pick; children: ReactNode }) {
  const menu = useContext(CardMenu)
  const lp = useLongPress<Entry>((e) => menu?.(e))(entry)
  if (!pick) {
    return (
      <Link to={`/entry/${entry.id}`} className={className} onClick={(ev) => { if (lp.wasLongPress()) ev.preventDefault() }}
        onPointerDown={menu ? lp.onPointerDown : undefined} onPointerMove={lp.onPointerMove} onPointerUp={lp.onPointerUp} onPointerLeave={lp.onPointerLeave}
        onContextMenu={menu ? lp.onContextMenu : undefined} draggable={false}>
        {children}
      </Link>
    )
  }
  const on = pick.selected.has(entry.id)
  return (
    <button type="button" className={`${className} is-picking${on ? ' is-picked' : ''}`} aria-pressed={on} onClick={() => pick.toggle(entry.id)}>
      {children}
      <span className={`pick-check${on ? ' is-on' : ''}`}>{on && <Icon name="check" size={14} stroke={2.6} />}</span>
    </button>
  )
}

/** Top-right corner of a cover: unread count, and an icon on titles that hold other titles (series) or sit inside one. */
export function CoverCorner({ entry: e }: { entry: Entry }) {
  const store = useStore()
  const unread = newCount(e)
  const holds = store.children(e.id).length > 0
  const inside = !!e.parentId
  if (!unread && !holds && !inside) return null
  return (
    <span className="thumb__corner">
      {unread > 0 && <span className="badge">{unread}</span>}
      {(holds || inside) && <span className="badge badge--glass" aria-label={holds ? 'Series' : 'In a series'}><Icon name={holds ? 'books' : 'layers'} size={12} stroke={2.2} /></span>}
    </span>
  )
}

export function LibraryCard({ entry: e, pick, index }: { entry: Entry; pick?: Pick; index?: number }) {
  const store = useStore()
  const nested = store.children(e.id).length
  const ch = resumeChapter(e)
  return (
    <CardShell entry={e} className="card" pick={pick}>
      <div className="thumb">
        <Cover art={e.art} title={e.title} url={e.coverUrl} />
        {index !== undefined && <span className="badge badge--tl badge--light">{index}</span>}
        <CoverCorner entry={e} />
        <span className="thumb__bar"><span style={{ width: `${progressPct(e)}%` }} /></span>
      </div>
      <div className="card-title">{e.title}</div>
      <div className="card-meta">
        {nested && !e.sources.length ? `${nested} title${nested === 1 ? '' : 's'}`
          : ch ? `${ch.label} / ${visibleChapters(e).length}`
          : e.counts && !e.chapters.length ? `${e.counts.unread} unread · ${e.counts.total} ch`
          : `${visibleChapters(e).length} ch · done`}
      </div>
    </CardShell>
  )
}

/** Every title, series included, in one cover grid; series are marked with an icon. */
export function EntryGrid({ entries, pick }: { entries: Entry[]; pick?: Pick }) {
  return <div className="grid3">{entries.map((e) => <LibraryCard key={e.id} entry={e} pick={pick} />)}</div>
}
