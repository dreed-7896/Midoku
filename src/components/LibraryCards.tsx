import { newCount, progressPct, readCount, resumeChapter, useStore, visibleChapters } from '../data/store'
import type { Entry } from '../data/types'
import { Cover } from './Art'
import { Icon } from './Icon'
import { TLink as Link } from './Nav'

export function LibraryCard({ entry: e }: { entry: Entry }) {
  const store = useStore()
  const unread = newCount(e)
  const nested = store.children(e.id).length
  const ch = resumeChapter(e)
  return (
    <Link to={`/entry/${e.id}`} className="card">
      <div className="thumb">
        <Cover art={e.art} title={e.title} />
        {unread > 0 && <span className="badge badge--tr">{unread}</span>}
        {nested > 0 && <span className="badge badge--tl badge--glass"><Icon name="layers" size={11} stroke={2.4} />{nested}</span>}
        <span className="thumb__bar"><span style={{ width: `${progressPct(e)}%` }} /></span>
      </div>
      <div className="card-title">{e.title}</div>
      <div className="card-meta">{ch ? `${ch.label} / ${visibleChapters(e).length}` : `${visibleChapters(e).length} ch · done`}</div>
    </Link>
  )
}

/** An entry that holds nested titles (Midoku's grouped titles), shown as a stack. */
export function SeriesCard({ entry: e }: { entry: Entry }) {
  const store = useStore()
  const kids = store.children(e.id)
  const versions = e.chapters.filter((c) => c.versions > 1).length
  const total = visibleChapters(e).length
  return (
    <Link to={`/entry/${e.id}`} className="series">
      <div className="series__stack">
        {kids.slice(0, 2).reverse().map((k, i) => (
          <div key={k.id} className={`series__back series__back--${i}`}><Cover art={k.art} title={k.title} /></div>
        ))}
        <div className="series__front"><Cover art={e.art} title={e.title} /></div>
      </div>
      <div className="grow">
        <div className="eyebrow"><Icon name="layers" size={13} stroke={2.2} /> Series · {kids.length + 1} titles</div>
        <div className="series__title">{e.title}</div>
        <div className="card-meta">{e.sources.length} source{e.sources.length === 1 ? '' : 's'}{versions ? ` · ${versions} merged versions` : ''}</div>
        <div className="row-progress">
          <span className="bar"><span style={{ width: `${progressPct(e)}%` }} /></span>
          <span>{readCount(e)}/{total}</span>
        </div>
      </div>
      {newCount(e) > 0 && <span className="badge badge--tr">{newCount(e)}</span>}
    </Link>
  )
}

/** Series first as stacks, then everything else as a cover grid. */
export function EntryGrid({ entries }: { entries: Entry[] }) {
  const store = useStore()
  const series = entries.filter((e) => store.children(e.id).length > 0)
  const singles = entries.filter((e) => store.children(e.id).length === 0)
  return (
    <>
      {series.map((e) => <SeriesCard key={e.id} entry={e} />)}
      {singles.length > 0 && <div className="grid3">{singles.map((e) => <LibraryCard key={e.id} entry={e} />)}</div>}
    </>
  )
}
