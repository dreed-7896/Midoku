import { newCount, progressPct, readCount, resumeChapter, useStore, visibleChapters } from '../data/store'
import type { Entry } from '../data/types'
import { Cover } from './Art'
import { Icon } from './Icon'
import { TLink as Link } from './Nav'
import type { ReactNode } from 'react'

/** Library selection: cards toggle instead of opening. */
export interface Pick { selected: Set<string>; toggle: (id: string) => void }

function CardShell({ id, className, pick, children }: { id: string; className: string; pick?: Pick; children: ReactNode }) {
  if (!pick) return <Link to={`/entry/${id}`} className={className}>{children}</Link>
  const on = pick.selected.has(id)
  return (
    <button type="button" className={`${className} is-picking${on ? ' is-picked' : ''}`} aria-pressed={on} onClick={() => pick.toggle(id)}>
      {children}
      <span className={`pick-check${on ? ' is-on' : ''}`}>{on && <Icon name="check" size={14} stroke={2.6} />}</span>
    </button>
  )
}

export function LibraryCard({ entry: e, pick }: { entry: Entry; pick?: Pick }) {
  const store = useStore()
  const unread = newCount(e)
  const nested = store.children(e.id).length
  const ch = resumeChapter(e)
  return (
    <CardShell id={e.id} className="card" pick={pick}>
      <div className="thumb">
        <Cover art={e.art} title={e.title} url={e.coverUrl} />
        {unread > 0 && <span className="badge badge--tr">{unread}</span>}
        {nested > 0 && <span className="badge badge--tl badge--glass"><Icon name="layers" size={11} stroke={2.4} />{nested}</span>}
        <span className="thumb__bar"><span style={{ width: `${progressPct(e)}%` }} /></span>
      </div>
      <div className="card-title">{e.title}</div>
      <div className="card-meta">
        {ch ? `${ch.label} / ${visibleChapters(e).length}`
          : e.counts && !e.chapters.length ? `${e.counts.unread} unread · ${e.counts.total} ch`
          : nested && !e.sources.length ? `${nested} titles`
          : `${visibleChapters(e).length} ch · done`}
      </div>
    </CardShell>
  )
}

/** An entry that holds nested titles (Midoku's grouped titles), shown as a stack. */
export function SeriesCard({ entry: e, pick }: { entry: Entry; pick?: Pick }) {
  const store = useStore()
  const kids = store.children(e.id)
  const versions = e.chapters.filter((c) => c.versions > 1).length
  const total = visibleChapters(e).length
  return (
    <CardShell id={e.id} className="series" pick={pick}>
      <div className="series__stack">
        {kids.slice(0, 2).reverse().map((k, i) => (
          <div key={k.id} className={`series__back series__back--${i}`}><Cover art={k.art} title={k.title} url={k.coverUrl} /></div>
        ))}
        <div className="series__front"><Cover art={e.art} title={e.title} url={e.coverUrl ?? kids[0]?.coverUrl} /></div>
      </div>
      <div className="grow">
        <div className="eyebrow"><Icon name="layers" size={13} stroke={2.2} /> Series · {kids.length + 1} titles</div>
        <div className="series__title">{e.title}</div>
        <div className="card-meta">{e.sources.length ? `${e.sources.length} source${e.sources.length === 1 ? '' : 's'}` : 'Made in Midoku'}{versions ? ` · ${versions} merged versions` : ''}</div>
        <div className="row-progress">
          <span className="bar"><span style={{ width: `${progressPct(e)}%` }} /></span>
          <span>{readCount(e)}/{total}</span>
        </div>
      </div>
      {newCount(e) > 0 && <span className="badge badge--tr">{newCount(e)}</span>}
    </CardShell>
  )
}

/** Series first as stacks, then everything else as a cover grid. */
export function EntryGrid({ entries, pick }: { entries: Entry[]; pick?: Pick }) {
  const store = useStore()
  const series = entries.filter((e) => store.children(e.id).length > 0)
  const singles = entries.filter((e) => store.children(e.id).length === 0)
  return (
    <>
      {series.map((e) => <SeriesCard key={e.id} entry={e} pick={pick} />)}
      {singles.length > 0 && <div className="grid3">{singles.map((e) => <LibraryCard key={e.id} entry={e} pick={pick} />)}</div>}
    </>
  )
}
