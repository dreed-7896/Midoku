import { useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Cover } from '../components/Art'
import { Chip, IconButton, PageHead, ServerStatus, Sheet } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { EntryGrid } from '../components/LibraryCards'
import { TLink as Link } from '../components/Nav'
import { newCount, resumeChapter, statusOf, unreadCount, useStore } from '../data/store'
import { Entry, GroupBy, LibraryFilters, LibraryTab, SortBy, Status, STATUS_LABEL } from '../data/types'

const EMPTY: LibraryFilters = { statuses: [], newOnly: false }
const SORT_LABEL: Record<SortBy, string> = { recent: 'Recently read', title: 'Title', added: 'Recently added', updated: 'Recently updated' }
const GROUP_LABEL: Record<GroupBy, string> = { none: 'None', tab: 'Tab', status: 'Status', source: 'Source' }

function matches(e: Entry, f: LibraryFilters) {
  if (f.statuses.length && !f.statuses.includes(statusOf(e))) return false
  if (f.newOnly && newCount(e) === 0) return false
  if (f.tag && !e.tags.includes(f.tag)) return false
  return true
}

function sorter(sort: SortBy) {
  return (a: Entry, b: Entry) => {
    switch (sort) {
      case 'title': return a.title.localeCompare(b.title)
      case 'added': return b.addedOrder - a.addedOrder
      case 'updated': return a.updatedAgo - b.updatedAgo
      default: return (a.lastReadAgo ?? 1e9) - (b.lastReadAgo ?? 1e9)
    }
  }
}

export default function Library() {
  const store = useStore()
  const tabs = store.tabs
  const [active, setActive] = useState(() => Math.max(0, tabs.findIndex((t) => t.id === 'all')))
  const [filters, setFilters] = useState<LibraryFilters>(EMPTY)
  const [groupBy, setGroupBy] = useState<GroupBy>('none')
  const [sort, setSort] = useState<SortBy>('recent')
  const [query, setQuery] = useState('')
  const [searching, setSearching] = useState(false)
  const [sheet, setSheet] = useState(false)
  const pager = useRef<HTMLDivElement>(null)
  const strip = useRef<HTMLDivElement>(null)

  const roots = store.entries.filter((e) => e.inLibrary && !e.parentId)
  const filterCount = filters.statuses.length + (filters.newOnly ? 1 : 0)
  const unreadTotal = roots.reduce((n, e) => n + unreadCount(e), 0)
  const tab = tabs[Math.min(active, tabs.length - 1)]
  const q = query.trim().toLowerCase()

  // Start on the remembered tab, without animating.
  useLayoutEffect(() => {
    const el = pager.current
    if (el) el.scrollLeft = active * el.clientWidth
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Keep the active chip in view as the pager moves.
  useLayoutEffect(() => {
    const chip = strip.current?.children[active] as HTMLElement | undefined
    const s = strip.current
    if (chip && s) s.scrollTo({ left: chip.offsetLeft - (s.clientWidth - chip.offsetWidth) / 2, behavior: 'smooth' })
  }, [active])

  const onPagerScroll = () => {
    const el = pager.current
    if (!el) return
    const i = Math.round(el.scrollLeft / el.clientWidth)
    if (i !== active && i >= 0 && i < tabs.length) setActive(i)
  }
  const goTab = (i: number) => {
    const el = pager.current
    if (!el) return
    el.scrollTo({ left: i * el.clientWidth, behavior: 'smooth' })
    setActive(i)
  }

  const toggleStatus = (s: Status) =>
    setFilters((f) => ({ ...f, statuses: f.statuses.includes(s) ? f.statuses.filter((x) => x !== s) : [...f.statuses, s] }))

  const newTab = () => {
    const name = window.prompt('Name the new tab')
    if (!name?.trim()) return
    store.createTab(name.trim())
    store.toast(`Added “${name.trim()}”. Add titles to it from their details page.`)
    setTimeout(() => goTab(tabs.length), 50)
  }
  const saveFiltersAsTab = () => {
    const name = window.prompt('Name this tab')
    if (!name?.trim()) return
    store.addTab(name.trim(), filters)
    setFilters(EMPTY)
    setSheet(false)
    setTimeout(() => goTab(tabs.length), 50)
  }
  const renameTab = () => {
    const name = window.prompt('Rename tab', tab.name)
    if (name?.trim()) store.renameTab(tab.id, name.trim())
  }
  const deleteTab = () => {
    if (!window.confirm(`Delete the “${tab.name}” tab? Its titles stay in your library.`)) return
    store.deleteTab(tab.id)
    setSheet(false)
    goTab(Math.max(0, active - 1))
  }

  const search = useMemo(() => (q ? roots.filter((e) => e.title.toLowerCase().includes(q) || e.author.toLowerCase().includes(q)).sort(sorter(sort)) : []), [roots, q, sort])

  return (
    <div className="page library">
      <PageHead kicker={`${roots.length} titles · ${unreadTotal} unread`} title="Library">
        <IconButton icon="search" label="Search library" active={searching} onClick={() => { setSearching((s) => !s); setQuery('') }} />
        <IconButton icon="sliders" label={`Filter and sort, ${filterCount} filters active`} badge={filterCount || undefined} onClick={() => setSheet(true)} />
      </PageHead>

      <ServerStatus />

      {searching && (
        <div className="pad-x pad-t-sm">
          <label className="field">
            <Icon name="search" size={18} />
            <input autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Filter by title or author" aria-label="Filter library" />
          </label>
        </div>
      )}

      {!q && (
        <div className="chips pad-x pad-t tabstrip" role="tablist" aria-label="Library tabs" ref={strip}>
          {tabs.map((t, i) => (
            <button key={t.id} type="button" role="tab" aria-selected={i === active} className={`chip chip--lg${i === active ? ' is-on' : ''}`} onClick={() => goTab(i)}>
              {t.kind === 'reading' && <Icon name="book" size={15} stroke={2} />}
              {t.kind === 'smart' && <Icon name="sparkle" size={15} stroke={2} />}
              {t.name}
              <span className="chip__count">{countFor(t)}</span>
            </button>
          ))}
          <button type="button" className="chip chip--lg chip--dashed" aria-label="New tab" onClick={newTab}><Icon name="plus" size={16} /></button>
        </div>
      )}

      {(filterCount > 0 && !q) && (
        <div className="chips pad-x pad-t-sm">
          {filters.statuses.map((s) => <Chip key={s} removable onClick={() => toggleStatus(s)}>Status: {STATUS_LABEL[s]}</Chip>)}
          {filters.newOnly && <Chip removable onClick={() => setFilters((f) => ({ ...f, newOnly: false }))}>New chapters</Chip>}
        </div>
      )}

      {q ? (
        <div className="pager__panel pager__panel--solo pad-x" data-scroll-active="true">
          {search.length ? <EntryGrid entries={search} /> : <p className="empty">No titles match “{query}”.</p>}
        </div>
      ) : (
        <div className="pager" ref={pager} onScroll={onPagerScroll}>
          {tabs.map((t, i) => (
            <div key={t.id} className="pager__panel" data-scroll-active={i === active} role="tabpanel" aria-label={t.name}>
              {/* Only the visible tab and its neighbours are rendered. */}
              {Math.abs(i - active) <= 1 && <TabPanel tab={t} filters={filters} sort={sort} groupBy={groupBy} roots={roots} />}
            </div>
          ))}
        </div>
      )}

      <Sheet open={sheet} title="Filter and sort" onClose={() => setSheet(false)}>
        <div className="label label--flush">Status</div>
        <div className="chips wrap">
          {(Object.keys(STATUS_LABEL) as Status[]).map((s) => <Chip key={s} on={filters.statuses.includes(s)} onClick={() => toggleStatus(s)}>{STATUS_LABEL[s]}</Chip>)}
        </div>
        <label className="toggle-row">
          <span><Icon name="sparkle" size={16} stroke={2} /> Only titles with new chapters</span>
          <input type="checkbox" checked={filters.newOnly} onChange={(e) => setFilters((f) => ({ ...f, newOnly: e.target.checked }))} />
        </label>
        <div className="label">Sort</div>
        <div className="segmented">
          {(Object.keys(SORT_LABEL) as SortBy[]).map((s) => (
            <button key={s} type="button" className={sort === s ? 'is-on' : ''} onClick={() => setSort(s)}>{SORT_LABEL[s]}</button>
          ))}
        </div>
        <div className="label">Group the All tab by</div>
        <div className="segmented">
          {(Object.keys(GROUP_LABEL) as GroupBy[]).map((g) => (
            <button key={g} type="button" className={groupBy === g ? 'is-on' : ''} onClick={() => setGroupBy(g)}>{GROUP_LABEL[g]}</button>
          ))}
        </div>
        {(tab.kind === 'tab' || tab.kind === 'smart') && (
          <>
            <div className="label">This tab · {tab.name}</div>
            <div className="sheet__actions sheet__actions--flush">
              <button type="button" className="btn btn--ghost" onClick={renameTab}>Rename</button>
              <button type="button" className="btn btn--ghost" onClick={deleteTab}><Icon name="trash" size={16} />Delete</button>
            </div>
          </>
        )}
        <div className="sheet__actions">
          <button type="button" className="btn btn--ghost" onClick={() => setFilters(EMPTY)}>Clear filters</button>
          <button type="button" className="btn btn--accent" onClick={saveFiltersAsTab} disabled={!filterCount}>Save as tab</button>
        </div>
      </Sheet>
    </div>
  )

  function countFor(t: LibraryTab): number {
    if (t.kind === 'reading') return store.queue.length
    if (t.kind === 'all') return roots.length
    if (t.kind === 'tab') return roots.filter((e) => e.tabs.includes(t.id)).length
    return roots.filter((e) => matches(e, t.filters)).length
  }
}

function TabPanel({ tab, filters, sort, groupBy, roots }: { tab: LibraryTab; filters: LibraryFilters; sort: SortBy; groupBy: GroupBy; roots: Entry[] }) {
  const store = useStore()
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({})
  if (tab.kind === 'reading') return <ReadingQueue />

  const base = tab.kind === 'tab' ? roots.filter((e) => e.tabs.includes(tab.id)) : roots
  const f = tab.kind === 'smart' ? { ...tab.filters, ...mergeUser(filters) } : filters
  const list = base.filter((e) => matches(e, f)).sort(sorter(sort))

  if (list.length === 0) {
    return (
      <p className="empty pad-x">
        {tab.kind === 'tab' && base.length === 0 ? 'No titles here yet. Add titles to this tab from their details page.' : 'Nothing matches these filters.'}
      </p>
    )
  }
  if (tab.kind !== 'all' || groupBy === 'none') {
    return <section className="section section--tight pad-x"><EntryGrid entries={list} /></section>
  }

  const tabName = (id: string) => store.tabs.find((t) => t.id === id)?.name ?? id
  const sections = group(list, groupBy, (id) => store.source(id)?.name ?? id, tabName)
  return (
    <>
      {sections.map((sec) => {
        const isCollapsed = !!collapsed[sec.name]
        return (
          <section key={sec.name} className="section section--tight pad-x">
            <button type="button" className="group-head" aria-expanded={!isCollapsed} onClick={() => setCollapsed((c) => ({ ...c, [sec.name]: !isCollapsed }))}>
              <span className="h2">{sec.name}</span>
              <span className="count-box">{sec.entries.length}</span>
              <span className="grow" />
              <Icon name={isCollapsed ? 'chevronRight' : 'chevronDown'} size={18} stroke={2} />
            </button>
            {isCollapsed ? (
              <div className="peek">
                {sec.entries.slice(0, 6).map((e) => <Cover key={e.id} art={e.art} title={e.title} url={e.coverUrl} className="peek__cover" />)}
                <span className="card-meta">{sec.entries.filter((e) => newCount(e) > 0).length || 'No'} with new chapters</span>
              </div>
            ) : (
              <EntryGrid entries={sec.entries} />
            )}
          </section>
        )
      })}
    </>
  )
}

function mergeUser(f: LibraryFilters): Partial<LibraryFilters> {
  const out: Partial<LibraryFilters> = {}
  if (f.statuses.length) out.statuses = f.statuses
  if (f.newOnly) out.newOnly = true
  return out
}

function group(list: Entry[], by: GroupBy, sourceName: (id: string) => string, tabName: (id: string) => string) {
  const map = new Map<string, Entry[]>()
  const add = (k: string, e: Entry) => map.set(k, [...(map.get(k) ?? []), e])
  for (const e of list) {
    if (by === 'status') add(STATUS_LABEL[statusOf(e)], e)
    else if (by === 'source') add(sourceName(e.sources.find((s) => s.main)?.sourceId ?? ''), e)
    else if (e.tabs.length === 0) add('No tab', e)
    else e.tabs.forEach((t) => add(tabName(t), e))
  }
  return [...map.entries()].map(([name, entries]) => ({ name, entries })).sort((a, b) =>
    a.name === 'No tab' ? 1 : b.name === 'No tab' ? -1 : b.entries.length - a.entries.length)
}

function ReadingQueue() {
  const store = useStore()
  const list = store.queue.map((id) => store.entry(id)).filter((e): e is Entry => !!e)
  return (
    <section className="section section--tight pad-x">
      <p className="hint">Your next reads, in order.</p>
      <div className="grid3">
        {list.map((e, i) => {
          const ch = resumeChapter(e)
          return (
            <Link key={e.id} to={`/entry/${e.id}`} className="card">
              <div className="thumb">
                <Cover art={e.art} title={e.title} url={e.coverUrl} />
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
