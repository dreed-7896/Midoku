import { useMemo, useState } from 'react'
import { Cover } from '../components/Art'
import { Chip, IconButton, PageHead, Sheet } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { EntryGrid, FolderTile } from '../components/LibraryCards'
import { TLink as Link } from '../components/Nav'
import { newCount, readCount, resumeChapter, unreadCount, useStore, visibleChapters } from '../data/store'
import { Entry, GroupBy, LibraryFilters, SortBy, Status, STATUS_LABEL } from '../data/types'

const EMPTY: LibraryFilters = { statuses: [], newOnly: false, progress: 'any' }
export const SORT_LABEL: Record<SortBy, string> = { recent: 'Recently read', title: 'Title', added: 'Recently added', updated: 'Recently updated' }
const GROUP_LABEL: Record<GroupBy, string> = { none: 'None', collection: 'Collection', status: 'Status', source: 'Source' }
const PROGRESS_LABEL: Record<LibraryFilters['progress'], string> = { any: 'Any', notStarted: 'Not started', inProgress: 'In progress', completed: 'Fully read' }

function matches(e: Entry, f: LibraryFilters) {
  if (f.statuses.length && !f.statuses.includes(e.status)) return false
  if (f.newOnly && newCount(e) === 0) return false
  if (f.tag && !e.tags.includes(f.tag)) return false
  const read = readCount(e), total = visibleChapters(e).length
  if (f.progress === 'notStarted' && read > 0) return false
  if (f.progress === 'inProgress' && !(read > 0 && read < total)) return false
  if (f.progress === 'completed' && !(total > 0 && read === total)) return false
  return true
}

export function sorter(sort: SortBy) {
  return (a: Entry, b: Entry) => {
    switch (sort) {
      case 'title': return a.title.localeCompare(b.title)
      case 'added': return b.addedOrder - a.addedOrder
      case 'updated': return a.updatedAgo - b.updatedAgo
      default: return (a.lastReadAgo ?? 1e9) - (b.lastReadAgo ?? 1e9)
    }
  }
}

export function nextSort(s: SortBy): SortBy {
  const order: SortBy[] = ['recent', 'updated', 'added', 'title']
  return order[(order.indexOf(s) + 1) % order.length]
}

export default function Library() {
  const store = useStore()
  const [tabId, setTabId] = useState('collections')
  const [filters, setFilters] = useState<LibraryFilters>(EMPTY)
  const [groupBy, setGroupBy] = useState<GroupBy>('none')
  const [sort, setSort] = useState<SortBy>('recent')
  const [query, setQuery] = useState('')
  const [searching, setSearching] = useState(false)
  const [sheet, setSheet] = useState(false)
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({})

  const tab = store.tabs.find((t) => t.id === tabId) ?? store.tabs[1]
  const roots = store.entries.filter((e) => e.inLibrary && !e.parentId)
  const activeFilters = tab.kind === 'smart' ? { ...tab.filters, ...mergeUser(filters) } : filters
  const filterCount = filters.statuses.length + (filters.newOnly ? 1 : 0) + (filters.progress !== 'any' ? 1 : 0)
  const q = query.trim().toLowerCase()

  const list = useMemo(() => roots
    .filter((e) => matches(e, activeFilters))
    .filter((e) => !q || e.title.toLowerCase().includes(q) || e.author.toLowerCase().includes(q))
    .sort(sorter(sort)), [roots, activeFilters, q, sort])

  const sections = useMemo(
    () => group(list, groupBy, (id) => store.source(id)?.name ?? id, (id) => store.collection(id)?.name ?? id),
    [list, groupBy, store],
  )
  const unreadTotal = roots.reduce((n, e) => n + unreadCount(e), 0)

  const toggleStatus = (s: Status) =>
    setFilters((f) => ({ ...f, statuses: f.statuses.includes(s) ? f.statuses.filter((x) => x !== s) : [...f.statuses, s] }))

  const saveTab = () => {
    const name = window.prompt('Name this tab')
    if (name?.trim()) {
      store.addTab(name.trim(), filters)
      setSheet(false)
      store.toast(`Saved “${name.trim()}”`)
    }
  }

  const newCollection = () => {
    const name = window.prompt('Name the new collection')
    if (name?.trim()) {
      store.createCollection(name.trim())
      store.toast(`Created “${name.trim()}”`)
    }
  }

  // A search always shows a flat list across the whole library.
  const view = q ? 'search' : tab.kind

  return (
    <div className="page">
      <PageHead kicker={`${roots.length} titles · ${unreadTotal} unread`} title="Library">
        <IconButton icon="search" label="Search library" active={searching} onClick={() => { setSearching((s) => !s); setQuery('') }} />
        <IconButton icon="sliders" label={`Filters, ${filterCount} active`} badge={filterCount || undefined} onClick={() => setSheet(true)} />
      </PageHead>

      {searching && (
        <div className="pad-x pad-t-sm">
          <label className="field">
            <Icon name="search" size={18} />
            <input autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Filter by title or author" aria-label="Filter library" />
          </label>
        </div>
      )}

      <div className="chips pad-x pad-t" role="tablist" aria-label="Library tabs">
        {store.tabs.map((t) => (
          <button key={t.id} type="button" role="tab" aria-selected={t.id === tab.id} className={`chip chip--lg${t.id === tab.id ? ' is-on' : ''}`} onClick={() => setTabId(t.id)}>
            {t.kind === 'reading' && <Icon name="book" size={15} stroke={2} />}
            {t.kind === 'collections' && <Icon name="folder" size={15} stroke={2} />}
            {t.kind === 'smart' && <Icon name="sparkle" size={15} stroke={2} />}
            {t.name}
            {t.kind === 'reading' && <span className="chip__count">{store.queue.length}</span>}
            {t.kind === 'collections' && <span className="chip__count">{store.collections.length}</span>}
            {t.kind === 'all' && <span className="chip__count">{roots.length}</span>}
          </button>
        ))}
        <button type="button" className="chip chip--lg chip--dashed" aria-label="Save current filters as a tab" onClick={saveTab}><Icon name="plus" size={16} /></button>
      </div>

      {view !== 'reading' && view !== 'collections' && (
        <div className="chips pad-x pad-t-sm">
          {filters.statuses.map((s) => <Chip key={s} removable onClick={() => toggleStatus(s)}>Status: {STATUS_LABEL[s]}</Chip>)}
          {filters.newOnly && <Chip removable onClick={() => setFilters((f) => ({ ...f, newOnly: false }))}>New chapters</Chip>}
          {filters.progress !== 'any' && <Chip removable onClick={() => setFilters((f) => ({ ...f, progress: 'any' }))}>{PROGRESS_LABEL[filters.progress]}</Chip>}
          <button type="button" className="chip" onClick={() => setSort(nextSort(sort))}><Icon name="sort" size={14} stroke={2} />{SORT_LABEL[sort]}</button>
          <button type="button" className="chip" onClick={() => setSheet(true)}><Icon name="layers" size={14} stroke={2} />Group: {GROUP_LABEL[groupBy]}</button>
        </div>
      )}

      {view === 'reading' && <ReadingQueue />}

      {view === 'collections' && (
        <>
          <section className="section pad-x">
            <div className="section-head">
              <h2 className="h2">Collections<span className="h2__count">{store.collections.length}</span></h2>
              <button type="button" className="link-btn" onClick={newCollection}>New</button>
            </div>
            <div className="grid2">
              {store.collections.map((c) => (
                <FolderTile key={c.id} collection={c} entries={roots.filter((e) => e.collections.includes(c.id)).sort(sorter(sort))} />
              ))}
              <button type="button" className="folder folder--new" onClick={newCollection}>
                <Icon name="plus" size={22} />New collection
              </button>
            </div>
          </section>
          {(() => {
            const loose = roots.filter((e) => e.collections.length === 0).sort(sorter(sort))
            return loose.length > 0 && (
              <section className="section pad-x">
                <div className="section-head">
                  <h2 className="h2">Not in a collection<span className="h2__count">{loose.length}</span></h2>
                </div>
                <EntryGrid entries={loose} />
              </section>
            )
          })()}
        </>
      )}

      {(view === 'all' || view === 'smart' || view === 'search') && (
        list.length === 0 ? <p className="empty pad-x">Nothing matches.</p> : sections.map((sec) => {
          const isCollapsed = !!collapsed[sec.name]
          return (
            <section key={sec.name} className="section pad-x">
              {groupBy !== 'none' && (
                <button type="button" className="group-head" aria-expanded={!isCollapsed} onClick={() => setCollapsed((c) => ({ ...c, [sec.name]: !isCollapsed }))}>
                  <span className="h2">{sec.name}</span>
                  <span className="count-box">{sec.entries.length}</span>
                  <span className="grow" />
                  <Icon name={isCollapsed ? 'chevronRight' : 'chevronDown'} size={18} stroke={2} />
                </button>
              )}
              {isCollapsed ? (
                <div className="peek">
                  {sec.entries.slice(0, 6).map((e) => <Cover key={e.id} art={e.art} title={e.title} className="peek__cover" />)}
                  <span className="card-meta">{sec.entries.filter((e) => newCount(e) > 0).length || 'No'} with new chapters</span>
                </div>
              ) : (
                <EntryGrid entries={sec.entries} />
              )}
            </section>
          )
        })
      )}

      <Sheet open={sheet} title="Filter and sort" onClose={() => setSheet(false)}>
        <div className="label label--flush">Status</div>
        <div className="chips wrap">
          {(Object.keys(STATUS_LABEL) as Status[]).map((s) => <Chip key={s} on={filters.statuses.includes(s)} onClick={() => toggleStatus(s)}>{STATUS_LABEL[s]}</Chip>)}
        </div>
        <div className="label">Reading progress</div>
        <div className="segmented">
          {(Object.keys(PROGRESS_LABEL) as LibraryFilters['progress'][]).map((p) => (
            <button key={p} type="button" className={filters.progress === p ? 'is-on' : ''} onClick={() => setFilters((f) => ({ ...f, progress: p }))}>{PROGRESS_LABEL[p]}</button>
          ))}
        </div>
        <label className="toggle-row">
          <span><Icon name="sparkle" size={16} stroke={2} /> Only titles with new chapters</span>
          <input type="checkbox" checked={filters.newOnly} onChange={(e) => setFilters((f) => ({ ...f, newOnly: e.target.checked }))} />
        </label>
        <div className="label">Group the All tab by</div>
        <div className="segmented">
          {(Object.keys(GROUP_LABEL) as GroupBy[]).map((g) => (
            <button key={g} type="button" className={groupBy === g ? 'is-on' : ''} onClick={() => setGroupBy(g)}>{GROUP_LABEL[g]}</button>
          ))}
        </div>
        <div className="label">Sort</div>
        <div className="segmented">
          {(Object.keys(SORT_LABEL) as SortBy[]).map((s) => (
            <button key={s} type="button" className={sort === s ? 'is-on' : ''} onClick={() => setSort(s)}>{SORT_LABEL[s]}</button>
          ))}
        </div>
        <div className="sheet__actions">
          <button type="button" className="btn btn--ghost" onClick={() => setFilters(EMPTY)}>Clear filters</button>
          <button type="button" className="btn btn--accent" onClick={() => { setTabId('all'); saveTab() }}>Save as tab</button>
        </div>
      </Sheet>
    </div>
  )
}

function mergeUser(f: LibraryFilters): Partial<LibraryFilters> {
  const out: Partial<LibraryFilters> = {}
  if (f.statuses.length) out.statuses = f.statuses
  if (f.newOnly) out.newOnly = true
  if (f.progress !== 'any') out.progress = f.progress
  return out
}

function group(list: Entry[], by: GroupBy, sourceName: (id: string) => string, collectionName: (id: string) => string) {
  if (by === 'none') return [{ name: 'All', entries: list }]
  const map = new Map<string, Entry[]>()
  const add = (k: string, e: Entry) => map.set(k, [...(map.get(k) ?? []), e])
  for (const e of list) {
    if (by === 'status') add(STATUS_LABEL[e.status], e)
    else if (by === 'source') add(sourceName(e.sources.find((s) => s.main)?.sourceId ?? ''), e)
    else if (e.collections.length === 0) add('Not in a collection', e)
    else e.collections.forEach((c) => add(collectionName(c), e))
  }
  return [...map.entries()].map(([name, entries]) => ({ name, entries })).sort((a, b) =>
    a.name === 'Not in a collection' ? 1 : b.name === 'Not in a collection' ? -1 : b.entries.length - a.entries.length)
}

function ReadingQueue() {
  const store = useStore()
  const list = store.queue.map((id) => store.entry(id)).filter((e): e is Entry => !!e)
  return (
    <section className="section pad-x">
      <p className="hint">Your next reads, in order.</p>
      <div className="grid3">
        {list.map((e, i) => {
          const ch = resumeChapter(e)
          return (
            <Link key={e.id} to={`/entry/${e.id}`} className="card">
              <div className="thumb">
                <Cover art={e.art} title={e.title} />
                <span className="badge badge--tl badge--light">{i + 1}</span>
                {newCount(e) > 0 && <span className="badge badge--tr">{newCount(e)}</span>}
              </div>
              <div className="card-title">{e.title}</div>
              <div className="card-meta">{ch ? `Next: ${ch.label}` : 'Caught up'}</div>
            </Link>
          )
        })}
      </div>
    </section>
  )
}
