import { useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Cover } from '../components/Art'
import { Chip, IconButton, PageHead, ServerStatus, Sheet } from '../components/Chrome'
import { Icon, type IconName } from '../components/Icon'
import { Banner, Empty, Loading } from '../components/Status'
import { CardMenu, EntryGrid, LibraryCard, type Pick } from '../components/LibraryCards'
import { useLongPress } from '../components/LongPress'
import { BulkMigrateSheet, DuplicatesSheet, GroupSheet } from '../components/LibraryTools'
import { useNav } from '../components/Nav'
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
  const [active, setActive] = useState(() => Math.max(0, tabs.findIndex((t) => t.kind === 'all')))
  const [filters, setFilters] = useState<LibraryFilters>(EMPTY)
  const [groupBy, setGroupBy] = useState<GroupBy>('none')
  const [sort, setSort] = useState<SortBy>('recent')
  const [query, setQuery] = useState('')
  const [searching, setSearching] = useState(false)
  const [sheet, setSheet] = useState(false)
  const [picking, setPicking] = useState(false)
  const [picked, setPicked] = useState<string[]>([])
  const [tool, setTool] = useState<null | 'group' | 'tabs' | 'dupes' | 'migrate'>(null)
  const nav = useNav()
  const [more, setMore] = useState(false)
  const [menuFor, setMenuFor] = useState<Entry | null>(null)
  const [readingAdd, setReadingAdd] = useState(false)
  // Shuffle (Reading tab): a tap picks from Reading, a long press (or an empty Reading list) from the whole library.
  const shufflePress = useLongPress<void>(() => shuffle(true))
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

  const pick: Pick | undefined = picking ? {
    selected: new Set(picked),
    toggle: (id) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : [...p, id])),
  } : undefined
  const stopPicking = () => { setPicking(false); setPicked([]) }

  /** Opens a random title from the Reading list, or from the whole library. */
  const shuffle = (everything: boolean) => {
    const reading = store.queue.map((id) => store.entry(id)).filter((e): e is Entry => !!e)
    const fromAll = everything || !reading.length
    const pool = (fromAll ? store.entries.filter((e) => e.inLibrary) : reading).filter((e) => e.sources.length || e.chapters.length)
    if (!pool.length) { store.toast('Nothing to pick from'); return }
    const e = pool[Math.floor(Math.random() * pool.length)]
    if (fromAll && !everything) store.toast('Reading is empty · picked from your whole library')
    nav.go(`/entry/${e.id}`)
  }

  const search = useMemo(() => (q ? roots.filter((e) => e.title.toLowerCase().includes(q) || e.author.toLowerCase().includes(q)).sort(sorter(sort)) : []), [roots, q, sort])

  return (
    <div className="page library">
      <PageHead kicker={`${roots.length} titles · ${unreadTotal} unread`} title="Library">
        <IconButton icon="search" label="Search library" active={searching} onClick={() => { setSearching((s) => !s); setQuery('') }} />
        <IconButton icon="sliders" label={`Filter and sort, ${filterCount} filters active`} badge={filterCount || undefined} onClick={() => setSheet(true)} />
        <IconButton icon="more" label="More library actions" active={!!store.updating} onClick={() => setMore(true)} />
      </PageHead>

      <ServerStatus />
      {store.offline && <div className="pad-x pad-t"><Banner icon="info">Offline · showing your library as saved on this device. Changes sync when you're back online.</Banner></div>}
      {store.updating && <div className="pad-x pad-t"><Banner tone="busy">Checking for new chapters… {store.updating.done} of {store.updating.total}</Banner></div>}

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

      <CardMenu.Provider value={picking ? null : setMenuFor}>
      {q ? (
        <div className="pager__panel pager__panel--solo pad-x" data-scroll-active="true">
          {search.length ? <EntryGrid entries={search} pick={pick} /> : <Empty icon="search" title={`No titles match “${query}”`} detail="This searches titles and authors in your library. Use Search to find new titles." />}
        </div>
      ) : (
        <div className="pager" ref={pager} onScroll={onPagerScroll}>
          {tabs.map((t, i) => (
            <div key={t.id} className="pager__panel" data-scroll-active={i === active} role="tabpanel" aria-label={t.name}>
              {/* Only the visible tab and its neighbours are rendered. */}
              {Math.abs(i - active) <= 1 && <TabPanel tab={t} filters={filters} sort={sort} groupBy={groupBy} roots={roots} pick={pick} onAddReading={() => setReadingAdd(true)} />}
            </div>
          ))}
        </div>
      )}
      </CardMenu.Provider>

      {tab.kind === 'reading' && !picking && !q && (
        <button type="button" className="fab" aria-label="Random title from Reading (hold for the whole library)" title="Tap: from Reading · Hold: whole library"
          onClick={() => { if (!shufflePress().wasLongPress()) shuffle(false) }}
          onPointerDown={shufflePress().onPointerDown} onPointerMove={shufflePress().onPointerMove} onPointerUp={shufflePress().onPointerUp} onPointerLeave={shufflePress().onPointerLeave} onContextMenu={shufflePress().onContextMenu}>
          <Icon name="shuffle" size={22} />
        </button>
      )}
      {readingAdd && <ReadingAddSheet onClose={() => setReadingAdd(false)} />}

      {menuFor && (() => {
        const e = store.entry(menuFor.id) ?? menuFor
        const st = statusOf(e)
        const next = resumeChapter(e)
        const close = () => setMenuFor(null)
        return (
          <Sheet open title={e.title} onClose={close}>
            <p className="hint">{STATUS_LABEL[st]}{store.children(e.id).length ? ` · series of ${store.children(e.id).length} titles` : ''}</p>
            <div className="menu">
              {next && <MenuRow icon="play" title={st === 'unread' ? 'Start reading' : 'Continue reading'} detail={next.label} onClick={() => { close(); nav.go(`/read/${e.id}/${next.id}`) }} />}
              <MenuRow icon="book" title="Open" onClick={() => { close(); nav.go(`/entry/${e.id}`) }} />
              {st !== 'completed' && <MenuRow icon="check" title="Mark all read" onClick={() => { close(); void store.markEntry(e.id, true) }} />}
              {st !== 'unread' && <MenuRow icon="undo" title="Mark all unread" detail="Clears read marks and page progress" onClick={() => { close(); if (window.confirm(`Mark every chapter of ${e.title} unread?`)) void store.markEntry(e.id, false) }} />}
              {store.queue.includes(e.id) ? <>
                <MenuRow icon="undo" title="Remove from Reading" onClick={() => { close(); store.removeFromReading([e.id]) }} />
                {store.queue.indexOf(e.id) > 0 && <MenuRow icon="chevronRight" title="Move earlier in Reading" onClick={() => { close(); store.moveInReading(e.id, -1) }} />}
                {store.queue.indexOf(e.id) < store.queue.length - 1 && <MenuRow icon="chevronRight" title="Move later in Reading" onClick={() => { close(); store.moveInReading(e.id, 1) }} />}
              </> : <MenuRow icon="book" title="Add to Reading" onClick={() => { close(); store.addToReading([e.id]) }} />}
              <MenuRow icon="folder" title="Library tabs" onClick={() => { close(); setPicked([e.id]); setTool('tabs') }} />
              <MenuRow icon="select" title="Select" detail="Pick more titles to group, file or remove" onClick={() => { close(); setPicking(true); setPicked([e.id]) }} />
              <MenuRow icon="trash" title="Remove from library" detail="Progress is kept if you add it back" onClick={() => {
                close()
                if (!window.confirm(`Remove ${e.title} from your library?`)) return
                store.removeFromLibrary([e.id]); store.toast(`Removed ${e.title}`)
              }} />
            </div>
          </Sheet>
        )
      })()}

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

      <Sheet open={more} title="Library" onClose={() => setMore(false)}>
        <div className="menu">
          {store.server.status !== 'off' && (
            <MenuRow icon="refresh" title={store.updating ? `Checking ${store.updating.done} of ${store.updating.total}…` : 'Check for new chapters'}
              detail="Asks the server for new chapters of followed titles" onClick={() => { setMore(false); void store.checkUpdates() }} />
          )}
          <MenuRow icon="select" title="Select titles" detail="Group, file into tabs, migrate or remove several at once" onClick={() => { setMore(false); setPicking(true) }} />
          <MenuRow icon="plus" title="Add to Reading" detail="Pick titles for your reading list" onClick={() => { setMore(false); setReadingAdd(true) }} />
          {store.queue.length > 0 && <MenuRow icon="undo" title="Clear Reading" detail={`Takes ${store.queue.length} title${store.queue.length === 1 ? '' : 's'} out of the list`} onClick={() => { setMore(false); if (window.confirm('Clear the Reading list? The titles stay in your library.')) store.removeFromReading() }} />}
          <MenuRow icon="shuffle" title="Random from the whole library" onClick={() => { setMore(false); shuffle(true) }} />
          <MenuRow icon="bookmark" title="Bookmarks" detail="Every bookmarked page, by title" onClick={() => { setMore(false); nav.go('/bookmarks') }} />
          <MenuRow icon="clock" title="History" detail="Chapters you read, newest first" onClick={() => { setMore(false); nav.go('/history') }} />
          <MenuRow icon="layers" title="Find duplicates" detail="Same name or same source title" onClick={() => { setMore(false); setTool('dupes') }} />
        </div>
      </Sheet>

      {picking && (
        <div className="action-bar" role="toolbar" aria-label="Title actions">
          <button type="button" onClick={stopPicking} aria-label="Done selecting"><Icon name="x" size={18} />Done</button>
          <span className="action-bar__count">{picked.length} selected</span>
          <button type="button" disabled={picked.length < 2} onClick={() => setTool('group')}><Icon name="layers" size={18} />Group</button>
          <button type="button" disabled={!picked.length} onClick={() => setTool('tabs')}><Icon name="folder" size={18} />Tabs</button>
          {store.server.status !== 'off' && <button type="button" disabled={!picked.length} onClick={() => setTool('migrate')}><Icon name="migrate" size={18} />Migrate</button>}
          <button type="button" disabled={!picked.length} onClick={() => {
            if (!window.confirm(`Remove ${picked.length} title${picked.length === 1 ? '' : 's'} from your library? Progress is kept if you add them back.`)) return
            store.removeFromLibrary(picked)
            store.toast(`Removed ${picked.length} title${picked.length === 1 ? '' : 's'}`)
            stopPicking()
          }}><Icon name="trash" size={18} />Remove</button>
        </div>
      )}
      {tool === 'group' && <GroupSheet ids={picked} onClose={() => setTool(null)} onDone={stopPicking} />}
      {tool === 'dupes' && <DuplicatesSheet onClose={() => setTool(null)} />}
      {tool === 'migrate' && <BulkMigrateSheet ids={picked} onClose={() => setTool(null)} onDone={stopPicking} />}
      <Sheet open={tool === 'tabs'} title={`Tabs for ${picked.length} title${picked.length === 1 ? '' : 's'}`} onClose={() => { setTool(null); if (!picking) setPicked([]) }}>
        <p className="hint">Tick a tab to add every selected title to it; untick to take them all out.</p>
        {!tabs.some((t) => t.kind === 'tab') && <Empty compact icon="folder" title="No tabs yet" detail="Create one with + in the tab strip." />}
        <div className="check-list">
          {tabs.filter((t) => t.kind === 'tab').map((t) => {
            const list = picked.map((id) => store.entry(id)).filter((e): e is Entry => !!e)
            const all = list.length > 0 && list.every((e) => e.tabs.includes(t.id))
            return (
              <label key={t.id} className="check-row">
                <span className="check-row__name">{t.name}</span>
                <input type="checkbox" checked={all} onChange={() => list.forEach((e) => { if (e.tabs.includes(t.id) === all) store.toggleInTab(e.id, t.id) })} />
              </label>
            )
          })}
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

function MenuRow({ icon, title, detail, onClick }: { icon: IconName; title: string; detail?: string; onClick: () => void }) {
  return (
    <button type="button" className="menu__row" onClick={onClick}>
      <span className="menu__icon"><Icon name={icon} size={20} /></span>
      <span className="menu__text"><strong>{title}</strong>{detail && <span>{detail}</span>}</span>
    </button>
  )
}

function TabPanel({ tab, filters, sort, groupBy, roots, pick, onAddReading }: { tab: LibraryTab; filters: LibraryFilters; sort: SortBy; groupBy: GroupBy; roots: Entry[]; pick?: Pick; onAddReading: () => void }) {
  const store = useStore()
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({})
  if (tab.kind === 'reading' && !pick) return <ReadingQueue onAdd={onAddReading} />

  const base = tab.kind === 'tab' ? roots.filter((e) => e.tabs.includes(tab.id))
    : tab.kind === 'reading' ? store.queue.map((id) => store.entry(id)).filter((e): e is Entry => !!e)
    : roots
  const f = tab.kind === 'smart' ? { ...tab.filters, ...mergeUser(filters) } : filters
  const list = base.filter((e) => matches(e, f)).sort(sorter(sort))

  if (list.length === 0) {
    if (store.server.status === 'loading') return <div className="pad-x pad-t"><Loading label="Loading your library" /></div>
    return (
      <div className="pad-x pad-t">
        {roots.length === 0 ? <Empty icon="library" title="Your library is empty" detail="Find titles in Search or Sources and tap the bookmark to add them." />
          : tab.kind === 'tab' && base.length === 0 ? <Empty icon="folder" title={`Nothing in ${tab.name} yet`} detail="Open a title, tap ⋯ and choose Library tabs to file it here." />
          : <Empty icon="filter" title="Nothing matches these filters" detail="Clear a filter to see more titles." />}
      </div>
    )
  }
  if (tab.kind !== 'all' || groupBy === 'none') {
    return <section className="section section--tight pad-x"><EntryGrid entries={list} pick={pick} /></section>
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
              <EntryGrid entries={sec.entries} pick={pick} />
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

/** The Reading list: titles added by hand, in order (like native Midoku). */
function ReadingQueue({ onAdd }: { onAdd: () => void }) {
  const store = useStore()
  const list = store.queue.map((id) => store.entry(id)).filter((e): e is Entry => !!e)
  return (
    <section className="section section--tight pad-x">
      {list.length === 0
        ? <Empty icon="book" title="Nothing in Reading" detail="Keep the titles you're reading here. Long-press a title → Add to Reading, or add several at once." action={{ label: 'Add titles', onClick: onAdd }} />
        : <p className="hint">Your reading list, in order. Long-press a title to move it or take it out.</p>}
      <div className="grid3">{list.map((e, i) => <LibraryCard key={e.id} entry={e} index={i + 1} />)}</div>
    </section>
  )
}

/** Adds library titles to the Reading list. */
function ReadingAddSheet({ onClose }: { onClose: () => void }) {
  const store = useStore()
  const [q, setQ] = useState('')
  const [picked, setPicked] = useState<string[]>([])
  const inList = new Set(store.queue)
  const list = store.entries.filter((e) => e.inLibrary && !inList.has(e.id) && (!q.trim() || e.title.toLowerCase().includes(q.trim().toLowerCase())))
    .sort((a, b) => a.title.localeCompare(b.title))
  return (
    <Sheet open tall title="Add to Reading" onClose={onClose}>
      <label className="field"><Icon name="search" size={18} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search your library" aria-label="Search your library" /></label>
      {!list.length && <Empty compact icon="library" title={q ? 'No matches' : 'Everything is in Reading'} />}
      <div className="check-list pad-t-sm">
        {list.map((e) => (
          <label key={e.id} className="check-row">
            <span className="check-row__name grow"><Cover art={e.art} title={e.title} url={e.coverUrl} className="order-row__cover" /><span className="ellipsis">{e.title}</span></span>
            <input type="checkbox" checked={picked.includes(e.id)} onChange={() => setPicked((p) => (p.includes(e.id) ? p.filter((x) => x !== e.id) : [...p, e.id]))} />
          </label>
        ))}
      </div>
      <div className="sheet__actions sheet__actions--sticky">
        <button type="button" className="btn btn--ghost" onClick={onClose}>Cancel</button>
        <button type="button" className="btn btn--accent" disabled={!picked.length} onClick={() => { store.addToReading(picked); onClose() }}>Add{picked.length ? ` ${picked.length}` : ''}</button>
      </div>
    </Sheet>
  )
}
