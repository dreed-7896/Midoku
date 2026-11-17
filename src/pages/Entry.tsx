import { useCallback, useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { ChapterThumb, Cover, CoverViewer } from '../components/Art'
import { Chip, IconButton, Sheet } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { TLink as Link, useNav } from '../components/Nav'
import { useLongPress } from '../components/LongPress'
import { PageSplitter } from '../components/PageSplitter'
import { ThumbSheet } from '../components/ThumbSheet'
import { resetThumbs } from '../data/thumbs'
import { AddToEntrySheet, EditDetailsSheet, MoveSheet } from '../components/EntryTools'
import { CoverCorner } from '../components/LibraryCards'
import { SourcePicker, type PickedTitle } from '../components/SourcePicker'
import { Banner, Empty, Loading } from '../components/Status'
import { chapterKey, useDownloads } from '../data/downloads'
import { layoutOf, physicalIdOf } from '../data/library'
import { agoText, progressPct, readCount, resumeChapter, statusOf, totalCount, unreadCount, useStore, visibleChapters } from '../data/store'
import { getChapters, SChapter, toChapter } from '../data/suwayomi'
import { STATUS_LABEL, type Chapter } from '../data/types'

type ChapterFilter = 'all' | 'unread' | 'bookmarked' | 'downloaded'
type Panel = null | 'marks' | 'chfilter' | 'migrate' | 'options' | 'tabs' | 'sources' | 'link' | 'series' | 'insert' | 'edit' | 'addTo' | 'move'

export default function EntryPage() {
  const { id = '' } = useParams()
  const store = useStore()
  const nav = useNav()
  const entry = store.entry(id)
  const [expanded, setExpanded] = useState(false)
  const [filter, setFilter] = useState<ChapterFilter>('all')
  const [descending, setDescending] = useState(true)
  /** Chapter list filters: one linked source, one scanlation group, and sorting by number or upload date. */
  const [bySource, setBySource] = useState<string>()
  const [byGroup, setByGroup] = useState<string>()
  const [sortBy, setSortBy] = useState<'number' | 'date'>('number')
  const [selecting, setSelecting] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [showRemoved, setShowRemoved] = useState(false)
  const [refreshing, setRefreshing] = useState(false)
  const [shown, setShown] = useState(24)
  const [panel, setPanel] = useState<Panel>(null)
  const [sheetFor, setSheetFor] = useState<string | null>(null)
  const [insertAfter, setInsertAfter] = useState<Chapter | null>(null)
  const [pickedTitle, setPickedTitle] = useState<PickedTitle | null>(null)
  const [moving, setMoving] = useState<Chapter | null>(null)
  const [adding, setAdding] = useState<Set<string>>(new Set())
  const [migrating, setMigrating] = useState(false)
  const [viewing, setViewing] = useState(false)
  const downloads = useDownloads()
  const longPress = useLongPress<Chapter>((c) => setSheetFor(c.id))
  const libraryPress = useLongPress<void>(() => setPanel('tabs'))

  // Titles from the server (ids like "s42") load their details and chapters here.
  const remoteId = /^s\d+$/.test(id) ? Number(id.slice(1)) : null
  const [remote, setRemote] = useState<{ loading: boolean; error?: string; saved?: boolean }>({ loading: false })
  const loadRemote = useCallback(async (refresh = false) => {
    if (remoteId === null) return
    setRemote({ loading: true })
    try {
      const from = await store.loadEntry(id, refresh)
      setRemote({ loading: false, saved: from === 'saved' })
      if (refresh) store.toast(from === 'saved' ? 'Offline · showing the saved copy' : 'Up to date')
    } catch (e) {
      setRemote({ loading: false, error: (e as Error).message })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [remoteId, id])
  useEffect(() => {
    if (remoteId !== null && !entry?.remote?.chaptersLoaded) loadRemote()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [remoteId])

  const all = useMemo(() => (entry ? visibleChapters(entry) : []), [entry])
  const chapters = useMemo(() => {
    const versionsOf = (c: Chapter) => (c.alts?.length ? c.alts : [{ sourceId: c.sourceId, scanlator: c.scanlator }])
    const list = all.filter((c) =>
      (filter === 'unread' ? !c.read : filter === 'bookmarked' ? c.bookmarked || !!c.marks?.length : filter === 'downloaded' ? c.downloaded : true)
      && (!bySource || versionsOf(c).some((v) => v.sourceId === bySource))
      && (!byGroup || versionsOf(c).some((v) => v.scanlator === byGroup)))
    const key = (c: Chapter) => (sortBy === 'date' ? c.uploadedAt ?? 0 : c.number)
    return list.sort((a, b) => (descending ? key(b) - key(a) : key(a) - key(b)) || (descending ? b.number - a.number : a.number - b.number))
  }, [all, filter, descending, bySource, byGroup, sortBy])
  const groups = useMemo(() => [...new Set(all.flatMap((c) => (c.alts?.length ? c.alts.map((a) => a.scanlator) : [c.scanlator])).filter((g): g is string => !!g))].sort(), [all])

  if (!entry) {
    return (
      <div className="page">
        <div className="entry__top"><IconButton icon="back" label="Back" onClick={() => nav.back('/library')} /></div>
        <div className="pad-x pad-t">
          {remoteId !== null && !remote.error ? <Loading label="Loading title" shape="rows" count={3} /> : (
            <Empty icon="alert" tone="error" title={remote.error ? "Couldn't open this title" : 'Not in your library'}
              detail={remote.error ?? 'It may have been removed.'} action={remoteId !== null ? { label: 'Try again', onClick: () => loadRemote() } : undefined} />
          )}
        </div>
      </div>
    )
  }

  const loaded = !entry.remote || entry.remote.chaptersLoaded
  /** A series made in Midoku: it only holds titles. */
  const ownSeries = entry.sources.length === 0 && !entry.chapters.length
  const moved = entry.chapters.filter((c) => c.order != null).length
  const userTabs = store.tabs.filter((t) => t.kind === 'tab')
  const removed = entry.chapters.filter((c) => c.removed)
  const kids = store.children(entry.id)
  const parent = entry.parentId ? store.entry(entry.parentId) : undefined
  const nestable = store.entries.filter((e) => e.inLibrary && e.id !== entry.id && !e.parentId && !store.children(e.id).length)
  const resume = resumeChapter(entry)
  /** Chapters as a grid of thumbnails: off by default, turned on per title (Edit details, or the button here). */
  const thumbs = !!entry.custom?.thumbs
  const resetAllThumbs = async () => {
    if (!window.confirm(`Reset all chapter thumbnails of ${entry.title}?`)) return
    await resetThumbs(entry.chapters)
    const picked = new Set(entry.chapters.filter((x) => x.thumb).map((x) => x.id))
    if (picked.size) store.editChapters(entry.id, picked, { thumb: undefined })
    store.toast('Thumbnails reset')
  }
  const bm = libraryPress()
  /** Filing a title into a tab puts it in the library too. */
  const fileIn = (tabId: string) => {
    if (!entry.inLibrary && !entry.tabs.includes(tabId)) store.toggleLibrary(entry.id)
    store.toggleInTab(entry.id, tabId)
  }
  const main = entry.sources.find((s) => s.main) ?? entry.sources[0]
  const unread = unreadCount(entry)
  const downloaded = all.filter((c) => c.downloaded).length
  const bookmarked = all.filter((c) => c.bookmarked || c.marks?.length).length
  /** Page bookmarks, oldest chapter first; each opens the part of a split chapter that holds the page. */
  const pageMarks = entry.chapters.filter((c) => c.marks?.length && !c.removed).sort((a, b) => a.number - b.number)
    .flatMap((c) => c.marks!.map((n) => ({ c, n, open: all.find((p) => p.physicalId === c.id && p.range && n >= p.range[0] && n <= p.range[1]) ?? c })))
  const sheetChapter = sheetFor ? all.find((c) => c.id === sheetFor) ?? entry.chapters.find((c) => c.id === sheetFor) : undefined

  const openChapter = (c: Chapter) => {
    if (selecting) {
      setSelected((s) => {
        const next = new Set(s)
        next.has(c.id) ? next.delete(c.id) : next.add(c.id)
        return next
      })
    } else {
      nav.go(`/read/${entry.id}/${c.id}`)
    }
  }

  const addSelectedTo = () => {
    setAdding(new Set(selected))
    setPanel('addTo')
    setSelected(new Set())
    setSelecting(false)
  }
  const act = (patch: Partial<Chapter>, message: string) => {
    store.editChapters(entry.id, selected, patch)
    store.toast(`${message} ${selected.size} chapter${selected.size === 1 ? '' : 's'}`)
    setSelected(new Set())
    setSelecting(false)
  }
  // Saves the selected chapters on the device, or removes them when all are saved already.
  const saveSelected = () => {
    const picked = all.filter((c) => selected.has(c.id))
    if (picked.length && picked.every((c) => c.downloaded)) store.removeDownloads(entry.id, selected)
    else if (entry.remote) store.downloadChapters(entry.id, selected)
    else act({ downloaded: true }, 'Downloaded')
    setSelected(new Set())
    setSelecting(false)
  }
  const downloadUnread = () => {
    if (!entry.remote) { store.toast(`Queued ${unread} chapters`); return }
    const ids = all.filter((c) => !c.read && !c.downloaded).map((c) => c.id)
    if (!ids.length) { store.toast(unread ? 'Unread chapters are downloaded' : 'Nothing unread to download'); return }
    store.downloadChapters(entry.id, new Set(ids))
  }
  const progressOf = (c: Chapter) => {
    if (!c.sourceUrl) return undefined
    const key = chapterKey(c.sourceId, c.sourceUrl)
    if (downloads.active?.key === key) return downloads.active.progress
    return downloads.queued.has(key) ? 0 : undefined
  }
  const refresh = async () => {
    setRefreshing(true)
    if (entry.remote) await loadRemote(true)
    else await new Promise((r) => setTimeout(r, 900)).then(() => store.toast('Up to date'))
    setRefreshing(false)
  }
  const openWebsite = () => (entry.remote?.url ? window.open(entry.remote.url, '_blank', 'noopener') : store.toast('No web page for this title'))

  // Number for a chapter inserted after another: halfway to the next one.
  const insertNumber = (after: Chapter) => {
    const next = [...all].sort((a, b) => a.number - b.number).find((c) => c.number > after.number)
    return next ? Number(((after.number + next.number) / 2).toFixed(3)) : after.number + 0.5
  }

  const emptyFor: Record<ChapterFilter, { title: string; detail: string; icon: 'check' | 'bookmark' | 'download' | 'book'; done?: boolean }> = {
    all: { title: 'No chapters yet', detail: 'The source has not published any chapters for this title.', icon: 'book' },
    unread: { title: 'All caught up', detail: 'Every chapter is read. New ones show up here.', icon: 'check', done: true },
    bookmarked: { title: 'No bookmarks', detail: 'Long-press a chapter to bookmark it.', icon: 'bookmark' },
    downloaded: { title: 'Nothing downloaded', detail: 'Download chapters to read them offline.', icon: 'download' },
  }

  return (
    <div className="page entry">
      <div className="entry__backdrop" style={{ background: entry.art.c1 }} aria-hidden="true">
        <span style={{ background: entry.art.c2 }} />
      </div>

      <div className="entry__top">
        <IconButton icon="back" label="Back" glass onClick={() => nav.back('/library')} />
        <div className="row-gap">
          <IconButton icon="globe" label="Open source website" glass onClick={openWebsite} />
          <IconButton icon="more" label="Title options" glass onClick={() => setPanel('options')} />
        </div>
      </div>

      <div className="entry__hero">
        <button type="button" className="entry__cover" aria-label="View cover" onClick={() => setViewing(true)}><Cover art={entry.art} title={entry.title} url={entry.coverUrl} /></button>
        <h1 className="entry__title">{entry.title}</h1>
        <div className="entry__author">
          {entry.author}
          {parent && <> · <Link to={`/entry/${parent.id}`} className="accent-text">in {parent.title}</Link></>}
        </div>
      </div>

      {ownSeries ? (() => {
        const next = kids.find((k) => k.lastReadAgo !== undefined && resumeChapter(k)) ?? kids.find((k) => resumeChapter(k)) ?? kids[0]
        return (
          <div className="entry__actions pad-x">
            <button type="button" className="btn btn--accent btn--xl grow" disabled={!next} onClick={() => next && nav.go(`/entry/${next.id}`)}>
              <Icon name="play" size={16} />
              <span className="btn__stack"><span>{next ? 'Continue' : 'No titles yet'}</span><small>{next?.title ?? 'Add titles from Library → Select'}</small></span>
            </button>
            <button type="button" className={`icon-btn icon-btn--xl${entry.inLibrary ? ' is-accent' : ''}`} aria-pressed={entry.inLibrary}
              aria-label={entry.inLibrary ? 'Remove from library' : 'Add to library'} onClick={() => store.toggleLibrary(entry.id)}>
              <Icon name={entry.inLibrary ? 'bookmarkFill' : 'bookmark'} />
            </button>
          </div>
        )
      })() : <div className="entry__actions pad-x">
        <button type="button" className="btn btn--accent btn--xl grow" disabled={!resume} onClick={() => resume && openChapter(resume)}>
          <Icon name={resume ? 'play' : 'check'} size={16} />
          <span className="btn__stack">
            <span>{!resume ? 'All caught up' : readCount(entry) ? 'Resume' : 'Start reading'}</span>
            <small>{resume ? `${resume.label}${resume.page ? ` · page ${resume.page}` : ''}` : `${totalCount(entry)} chapters read`}</small>
          </span>
        </button>
        <button type="button" className={`icon-btn icon-btn--xl${entry.inLibrary ? ' is-accent' : ''}`} aria-pressed={entry.inLibrary}
          aria-label={entry.inLibrary ? 'Remove from library' : 'Add to library'} title="Hold to pick tabs"
          onClick={() => { if (!bm.wasLongPress()) store.toggleLibrary(entry.id) }}
          onPointerDown={bm.onPointerDown} onPointerMove={bm.onPointerMove} onPointerUp={bm.onPointerUp} onPointerLeave={bm.onPointerLeave} onContextMenu={bm.onContextMenu}>
          <Icon name={entry.inLibrary ? 'bookmarkFill' : 'bookmark'} />
        </button>
        <IconButton icon="download" label="Download unread chapters" onClick={downloadUnread} />
        <button type="button" className={`icon-btn icon-btn--xl${refreshing ? ' is-spinning' : ''}`} aria-label="Refresh title" onClick={refresh}>
          <Icon name="refresh" />
        </button>
      </div>}

      {migrating && <div className="pad-x pad-t-sm"><Banner tone="busy">Migrating… loading chapters from the new source</Banner></div>}
      {remote.saved && <div className="pad-x pad-t-sm"><Banner icon="info">Offline · showing the copy saved on this device</Banner></div>}

      {!ownSeries && <div className="facts pad-x pad-t">
        <div className="fact"><span>Chapters</span><strong>{loaded ? totalCount(entry) : '…'}</strong></div>
        <div className="fact"><span>Unread</span><strong className={unread ? 'accent-text' : ''}>{loaded || entry.counts ? unread : '…'}</strong></div>
        <div className="fact"><span>Read</span><strong>{progressPct(entry)}%</strong><span className="bar"><span style={{ width: `${progressPct(entry)}%` }} /></span></div>
        <button type="button" className="fact fact--btn" onClick={() => setPanel('sources')}>
          <span>Source</span><strong className="ellipsis">{main?.name ?? store.source(main?.sourceId ?? '')?.name ?? '—'}</strong>
          {entry.sources.length > 1 && <em>+{entry.sources.length - 1} more</em>}
        </button>
        <div className="fact"><span>Status</span><strong><span className={`dot dot--${entry.publishing.toLowerCase()}`} />{entry.publishing}</strong></div>
        <button type="button" className="fact fact--btn" onClick={() => setPanel('edit')}><span>Reading</span><strong>{STATUS_LABEL[statusOf(entry)]}</strong><em>{entry.lastReadAgo !== undefined ? `read ${agoText(entry.lastReadAgo)}` : 'never read'}</em></button>
      </div>}

      {(entry.description || entry.tags.length > 0) && (
        <div className="pad-x pad-t">
          {entry.description && <>
            <p className={`desc${expanded ? ' is-open' : ''}`}>{entry.description}</p>
            <button type="button" className="link-btn" onClick={() => setExpanded((x) => !x)}>{expanded ? 'Less' : 'More'}</button>
          </>}
          {entry.tags.length > 0 && <div className="chips pad-t-sm">{entry.tags.map((t) => <span key={t} className="tag">{t}</span>)}</div>}
        </div>
      )}

      {kids.length > 0 && (
        <section className="section pad-x">
          <div className="section-head">
            <h2 className="h2">Titles<span className="h2__count">{kids.length}</span></h2>
            <button type="button" className="link-btn" onClick={() => setPanel('series')}>Edit</button>
          </div>
          <div className="grid3">
            {kids.map((k) => (
              <Link key={k.id} to={`/entry/${k.id}`} className="card">
                <div className="thumb"><Cover art={k.art} title={k.title} url={k.coverUrl} /><CoverCorner entry={k} />
                  <span className="thumb__bar"><span style={{ width: `${progressPct(k)}%` }} /></span></div>
                <div className="card-title card-title--2">{k.title}</div>
              </Link>
            ))}
          </div>
        </section>
      )}

      {!ownSeries && <section className="section pad-x">
        <div className="section-head">
          <h2 className="h2">Chapters<span className="h2__count">{loaded ? all.length : '…'}</span></h2>
          <div className="row-gap">
            <IconButton icon={thumbs ? 'list' : 'grid'} label={thumbs ? 'Show chapters as a list' : 'Show chapter thumbnails'} onClick={() => store.editDetails(entry.id, { thumbs: thumbs ? undefined : true })} />
            <IconButton icon="sliders" label="Filter and sort chapters" badge={(bySource ? 1 : 0) + (byGroup ? 1 : 0) + (sortBy === 'date' ? 1 : 0) || undefined} onClick={() => setPanel('chfilter')} />
            <IconButton icon="sort" label={descending ? 'Show oldest first' : 'Show newest first'} onClick={() => setDescending((d) => !d)} />
            <IconButton icon="select" label={selecting ? 'Done selecting' : 'Select chapters'} active={selecting}
              onClick={() => { setSelecting((s) => !s); setSelected(new Set()) }} />
          </div>
        </div>
        <div className="chips">
          <Chip on={filter === 'all'} onClick={() => setFilter('all')}>All</Chip>
          <Chip on={filter === 'unread'} onClick={() => setFilter('unread')}>Unread {unread}</Chip>
          <Chip on={filter === 'bookmarked'} onClick={() => setFilter('bookmarked')}>Bookmarked {bookmarked}</Chip>
          <Chip on={filter === 'downloaded'} onClick={() => setFilter('downloaded')}>Downloaded {downloaded}</Chip>
        </div>

        {pageMarks.length > 0 && filter !== 'bookmarked' && (
          <button type="button" className="mark-strip" onClick={() => setFilter('bookmarked')}>
            <Icon name="bookmarkFill" size={14} />{pageMarks.length} bookmarked page{pageMarks.length === 1 ? '' : 's'}<span className="grow" /><Icon name="chevronRight" size={14} />
          </button>
        )}
        {filter === 'bookmarked' && pageMarks.length > 0 && (
          <div className="pad-t-sm">
            <div className="label label--flush">Bookmarked pages</div>
            <div className="check-list">
              {pageMarks.map(({ c, n, open }) => (
                <div key={`${c.id}-${n}`} className="check-row">
                  <button type="button" className="check-row__name grow plain-btn" onClick={() => nav.go(`/read/${entry.id}/${open.id}?page=${n}`)}>
                    <Icon name="bookmarkFill" size={14} /><span className="ellipsis">{open.label} · page {open.range ? n - open.range[0] + 1 : n}</span>
                  </button>
                  <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove bookmark on ${c.label} page ${n}`} onClick={() => store.toggleMark(entry.id, c.id, n)}><Icon name="x" size={16} /></button>
                </div>
              ))}
            </div>
            <div className="label">Bookmarked chapters</div>
          </div>
        )}
        {!loaded && (remote.error
          ? <div className="pad-t"><Empty icon="alert" tone="error" title="Couldn't load chapters" detail={remote.error} action={{ label: 'Try again', onClick: () => loadRemote() }} /></div>
          : <div className="pad-t"><Loading label="Loading chapters" /></div>)}
        {loaded && remote.error && <div className="pad-t"><Banner icon="alert" tone="error">Refresh failed: {remote.error}</Banner></div>}
        {loaded && chapters.length === 0 && (
          <div className="pad-t"><Empty icon={emptyFor[filter].icon} tone={emptyFor[filter].done ? 'done' : 'neutral'} title={emptyFor[filter].title} detail={emptyFor[filter].detail} /></div>
        )}

        <div className={thumbs ? 'grid3 pad-t' : 'ch-list pad-t-sm'}>
          {chapters.slice(0, shown).map((c) => {
            const current = resume?.id === c.id
            const isSelected = selected.has(c.id)
            const lp = longPress(c)
            const progress = !c.downloaded ? progressOf(c) : undefined
            const press = {
              onClick: () => { if (!lp.wasLongPress()) openChapter(c) },
              onPointerDown: lp.onPointerDown, onPointerMove: lp.onPointerMove, onPointerUp: lp.onPointerUp, onPointerLeave: lp.onPointerLeave, onContextMenu: lp.onContextMenu,
            }
            const versions = c.versions > 1 && (
              <span role="button" tabIndex={0} className="badge badge--glass chapter__versions" aria-label={`${c.versions} versions, choose one`}
                onClick={(e) => { e.stopPropagation(); setSheetFor(c.id) }}>
                <Icon name="layers" size={11} />{c.versions}
              </span>
            )
            const badges = <>
              {c.isNew && !c.read && <span className="badge">New</span>}
              {!!c.newPages && <span className="badge">+{c.newPages} pages</span>}
              {c.insertedFrom && <span className="badge badge--glass">Added</span>}
              {c.physicalId && <span className="badge badge--glass">Part</span>}
            </>
            const flags = <>
              {(c.bookmarked || !!c.marks?.length) && <span className="flag flag--accent"><Icon name="bookmarkFill" size={11} label={c.marks?.length ? `${c.marks.length} bookmarked page${c.marks.length === 1 ? '' : 's'}` : 'Bookmarked'} /></span>}
              {c.downloaded && <span className="flag"><Icon name="download" size={12} stroke={2.2} label="Downloaded" /></span>}
              {progress !== undefined && <span className="flag">{Math.round(progress * 100)}%</span>}
            </>
            const check = selecting && <span className={`chapter__check${isSelected ? ' is-on' : ''}`}>{isSelected && <Icon name="check" size={14} stroke={2.6} />}</span>
            const meta = c.part ?? (c.insertedFrom ? `from ${c.insertedFrom}` : current && c.page ? `${c.title} · p. ${c.page}` : `${c.title}${c.date ? ` · ${c.date}` : ''}`)
            if (!thumbs) return (
              <button key={c.id} type="button" className={`ch-row${current ? ' is-current' : ''}${isSelected ? ' is-selected' : ''}${c.read ? ' is-read' : ''}`}
                aria-pressed={selecting ? isSelected : undefined} {...press}>
                <span className="ch-row__text">
                  <span className="ch-row__label"><span>{c.label}</span>{badges}</span>
                  <span className="ch-row__meta">{c.read ? 'Read · ' : ''}{meta}</span>
                  {current && c.page > 0 && c.pages > 0 && <span className="ch-row__bar"><span style={{ width: `${(c.page / c.pages) * 100}%` }} /></span>}
                </span>
                <span className="ch-row__end">{versions && <span className="chapter__versions--inline">{versions}</span>}{flags}{check}</span>
              </button>
            )
            return (
              <button key={c.id} type="button" className={`chapter${current ? ' is-current' : ''}${isSelected ? ' is-selected' : ''}`}
                aria-pressed={selecting ? isSelected : undefined} {...press}>
                <div className={`chapter__thumb${c.read ? ' is-read' : ''}`}>
                  <ChapterThumb chapter={c} />
                  <span className="chapter__badges">{badges}</span>
                  {versions}
                  <span className="chapter__flags">{flags}</span>
                  {c.read && <span className="badge badge--bl badge--glass"><Icon name="check" size={11} stroke={2.6} />Read</span>}
                  {current && c.page > 0 && c.pages > 0 && <span className="chapter__progress"><span style={{ width: `${(c.page / c.pages) * 100}%` }} /></span>}
                  {check}
                </div>
                <div className="card-title">{c.label}</div>
                <div className="card-meta">{meta}</div>
              </button>
            )
          })}
        </div>
        {chapters.length > shown && (
          <div className="center pad-t">
            <button type="button" className="btn btn--ghost" onClick={() => setShown((n) => n + 24)}>Show more · {chapters.length - shown} left</button>
          </div>
        )}
        {loaded && all.length > 0 && <p className="hint pad-t">Long-press a chapter for versions, splitting and more.</p>}

        {removed.length > 0 && (
          <div className="center pad-t">
            <button type="button" className="btn btn--ghost" onClick={() => setShowRemoved((x) => !x)}>
              <Icon name="undo" size={15} /> {removed.length} removed chapter{removed.length === 1 ? '' : 's'} · {showRemoved ? 'Hide' : 'Restore'}
            </button>
            {showRemoved && (
              <div className="chips wrap pad-t-sm" style={{ justifyContent: 'center' }}>
                {removed.map((c) => (
                  <Chip key={c.id} onClick={() => { store.editChapters(entry.id, new Set([c.id]), { removed: false }); store.toast(`${c.label} restored`) }}>
                    <Icon name="plus" size={13} />{c.label}
                  </Chip>
                ))}
              </div>
            )}
          </div>
        )}
        {moved > 0 && (
          <div className="center pad-t-sm">
            <button type="button" className="btn btn--ghost" onClick={() => store.resetOrder(entry.id)}><Icon name="undo" size={15} /> {moved} moved chapter{moved === 1 ? '' : 's'} · Put back</button>
          </div>
        )}
      </section>}

      <Sheet open={panel === 'marks'} title="Bookmarks" onClose={() => setPanel(null)}>
        {!pageMarks.length && <Empty compact icon="bookmark" title="No bookmarked pages" detail="Tap the bookmark button in the reader to mark the page you're on." />}
        <div className="check-list">
          {pageMarks.map(({ c, n, open }) => (
            <div key={`${c.id}-${n}`} className="check-row">
              <button type="button" className="check-row__name check-row__name--stack grow plain-btn" onClick={() => { setPanel(null); nav.go(`/read/${entry.id}/${open.id}?page=${n}`) }}>
                <strong className="ellipsis">{open.label} · page {open.range ? n - open.range[0] + 1 : n}</strong>
                <span className="card-meta ellipsis">{c.title}</span>
              </button>
              <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove bookmark on ${c.label} page ${n}`} onClick={() => store.toggleMark(entry.id, c.id, n)}><Icon name="x" size={16} /></button>
            </div>
          ))}
        </div>
      </Sheet>

      <Sheet open={panel === 'chfilter'} title="Chapters" onClose={() => setPanel(null)}>
        <div className="label label--flush">Sort by</div>
        <div className="segmented">
          <button type="button" className={sortBy === 'number' ? 'is-on' : ''} onClick={() => setSortBy('number')}>Chapter number</button>
          <button type="button" className={sortBy === 'date' ? 'is-on' : ''} onClick={() => setSortBy('date')}>Upload date</button>
        </div>
        <div className="segmented pad-t-sm">
          <button type="button" className={descending ? 'is-on' : ''} onClick={() => setDescending(true)}>{sortBy === 'date' ? 'Newest first' : 'Highest first'}</button>
          <button type="button" className={!descending ? 'is-on' : ''} onClick={() => setDescending(false)}>{sortBy === 'date' ? 'Oldest first' : 'Lowest first'}</button>
        </div>
        {entry.sources.length > 1 && <>
          <div className="label">Source</div>
          <div className="chips wrap">
            <Chip on={!bySource} onClick={() => setBySource(undefined)}>All</Chip>
            {entry.sources.map((s, i) => <Chip key={`${s.sourceId}-${i}`} on={bySource === s.sourceId} onClick={() => setBySource(s.sourceId)}>{s.name ?? store.source(s.sourceId)?.name ?? s.sourceId}</Chip>)}
          </div>
        </>}
        {groups.length > 0 && <>
          <div className="label">Scanlator</div>
          <div className="chips wrap">
            <Chip on={!byGroup} onClick={() => setByGroup(undefined)}>All</Chip>
            {groups.map((g) => <Chip key={g} on={byGroup === g} onClick={() => setByGroup(g)}>{g}</Chip>)}
          </div>
        </>}
        <div className="sheet__actions">
          <button type="button" className="btn btn--ghost" onClick={() => { setBySource(undefined); setByGroup(undefined); setSortBy('number'); setDescending(true) }}>Reset</button>
          <button type="button" className="btn btn--accent" onClick={() => setPanel(null)}>Done</button>
        </div>
      </Sheet>

      <Sheet open={panel === 'options'} title={entry.title} onClose={() => setPanel(null)}>
        <div className="menu">
          <MenuRow icon="settings" title="Edit details" detail="Title, author, description, cover" onClick={() => setPanel('edit')} />
          {!ownSeries && statusOf(entry) !== 'completed' && <MenuRow icon="check" title="Mark all read" detail={`${unread} unread chapter${unread === 1 ? '' : 's'}`} onClick={() => { setPanel(null); void store.markEntry(entry.id, true) }} />}
          {!ownSeries && statusOf(entry) !== 'unread' && <MenuRow icon="undo" title="Mark all unread" detail="Clears read marks and page progress" onClick={() => { setPanel(null); if (window.confirm(`Mark every chapter of ${entry.title} unread?`)) void store.markEntry(entry.id, false) }} />}
          {thumbs && <MenuRow icon="image" title="Reset thumbnails" detail="Clears picked and made chapter thumbnails" onClick={() => { setPanel(null); void resetAllThumbs() }} />}
          <MenuRow icon="bookmark" title="Bookmarks" detail={pageMarks.length ? `${pageMarks.length} bookmarked page${pageMarks.length === 1 ? '' : 's'}` : 'Bookmark pages from the reader'} onClick={() => setPanel('marks')} />
          {store.queue.includes(entry.id)
            ? <MenuRow icon="undo" title="Remove from Reading" detail="Your hand-kept reading list" onClick={() => { setPanel(null); store.removeFromReading([entry.id]); store.toast(`Removed ${entry.title} from Reading`) }} />
            : <MenuRow icon="book" title="Add to Reading" detail="Your hand-kept reading list" onClick={() => { setPanel(null); store.addToReading([entry.id]) }} />}
          <MenuRow icon="folder" title="Library tabs" detail={userTabs.filter((t) => entry.tabs.includes(t.id)).map((t) => t.name).join(', ') || 'Not in any tab'} onClick={() => setPanel('tabs')} />
          <MenuRow icon="sources" title="Sources" detail={`${entry.sources.length} linked · main: ${main?.name ?? '—'}`} onClick={() => setPanel('sources')} />
          {entry.remote && <MenuRow icon="migrate" title="Migrate" detail={`Move to another source · progress comes along`} onClick={() => setPanel('migrate')} />}
          <MenuRow icon="books" title="Series" detail={kids.length ? `${kids.length} title${kids.length === 1 ? '' : 's'} inside` : parent ? `Part of ${parent.title}` : 'Group volumes or seasons together'} onClick={() => setPanel('series')} />
          <MenuRow icon="globe" title="Open website" detail={entry.remote?.url ? new URL(entry.remote.url).hostname : 'Not available'} onClick={() => { setPanel(null); openWebsite() }} />
        </div>
      </Sheet>

      <Sheet open={panel === 'tabs'} title="Library tabs" onClose={() => setPanel(null)}>
        <p className="hint">{entry.inLibrary ? 'Pick the tabs this title shows in. A title can be in more than one.' : 'Picking a tab also adds this title to your library.'}</p>
        {userTabs.length === 0 && <Empty compact icon="folder" title="No tabs yet" detail="Create one to sort your library." />}
        <div className="check-list">
          {userTabs.map((t) => (
            <label key={t.id} className="check-row">
              <span className="check-row__name">{t.name}</span>
              <input type="checkbox" checked={entry.tabs.includes(t.id)} onChange={() => fileIn(t.id)} />
            </label>
          ))}
        </div>
        <button type="button" className="btn btn--ghost btn--block" onClick={() => {
          const name = window.prompt('Name the new tab')
          if (name?.trim()) fileIn(store.createTab(name.trim()))
        }}><Icon name="plus" size={16} />New tab</button>
      </Sheet>

      <Sheet open={panel === 'sources'} title="Sources" onClose={() => setPanel(null)}>
        <p className="hint">Chapters from every source are merged; numbers that match become versions. The main source supplies the details and is read first.</p>
        <div className="check-list">
          {entry.sources.map((s, i) => (
            <div key={`${s.sourceId}-${s.mangaUrl ?? i}`} className="check-row">
              <span className="check-row__name check-row__name--stack">
                <strong>{s.name ?? store.source(s.sourceId)?.name ?? s.sourceId}</strong>
                <span className="card-meta">{s.chapters} chapters · {s.following ? 'checked for new chapters' : 'not checked'}</span>
              </span>
              <span className="row-gap">
                <input type="checkbox" role="switch" className="switch" checked={s.following} aria-label="Check this source for new chapters"
                  onChange={() => store.toggleFollow(entry.id, s.sourceId, s.mangaUrl)} />
                {s.main ? <span className="tag tag--accent">Main</span> : (
                  <button type="button" className="icon-btn icon-btn--sm" aria-label="Source actions" onClick={() => {
                    if (window.confirm(`Make ${s.name ?? 'this source'} the main source? Choose Cancel to unlink it instead.`)) void store.setMainSource(entry.id, s.sourceId, s.mangaUrl)
                    else if (window.confirm(`Unlink ${s.name ?? 'this source'}?`)) void store.unlinkSource(entry.id, s.sourceId, s.mangaUrl)
                  }}><Icon name="more" size={16} /></button>
                )}
              </span>
            </div>
          ))}
        </div>
        {entry.remote
          ? <button type="button" className="btn btn--ghost btn--block" onClick={() => setPanel('link')}><Icon name="plus" size={16} />Link another source</button>
          : <p className="hint">Linking sources needs a server.</p>}
      </Sheet>

      {panel === 'migrate' && <SourcePicker query={entry.title} title={`Migrate from ${main?.name ?? 'source'}`} onClose={() => setPanel(null)}
        onPick={(m) => {
          if (!window.confirm(`Move ${entry.title} from ${main?.name ?? 'its source'} to ${m.name ?? 'this source'}${m.title ? ` (${m.title})` : ''}?\n\nRead chapters, pages, bookmarks and thumbnails move over by chapter number. ${main?.name ?? 'The old source'} is unlinked.`)) return
          setPanel(null)
          setMigrating(true)
          void store.migrateSource(entry.id, m).catch((e: Error) => store.toast(`Migration failed: ${e.message}`)).finally(() => setMigrating(false))
        }} />}
      {panel === 'link' && <SourcePicker query={entry.title} title="Link a source" onClose={() => setPanel(null)}
        onPick={(m) => { setPanel(null); void store.linkSource(entry.id, m) }} />}

      <Sheet open={panel === 'series'} title="Series" onClose={() => setPanel(null)}>
        {parent && (
          <div className="pad-b">
            <Empty compact icon="books" title={`Part of ${parent.title}`} action={{ label: 'Take out', onClick: () => store.setParent(entry.id, undefined) }} />
          </div>
        )}
        {kids.length > 0 && <div className="grid3 pad-b">
          {kids.map((k) => (
            <Link key={k.id} to={`/entry/${k.id}`} className="card" onClick={() => setPanel(null)}>
              <div className="thumb"><Cover art={k.art} title={k.title} url={k.coverUrl} /><CoverCorner entry={k} /></div>
              <div className="card-title card-title--2">{k.title}</div>
            </Link>
          ))}
        </div>}
        {!parent && <>
          <p className="hint">Titles inside “{entry.title}” show as one series in your library.</p>
          <div className="check-list">
            {[...kids, ...nestable].map((t) => (
              <label key={t.id} className="check-row">
                <span className="check-row__name">{t.title}</span>
                <input type="checkbox" checked={t.parentId === entry.id} onChange={() => store.setParent(t.id, t.parentId === entry.id ? undefined : entry.id)} />
              </label>
            ))}
          </div>
          {!kids.length && !nestable.length && <Empty compact icon="books" title="Nothing to group" detail="Add more titles to your library first." />}
        </>}
      </Sheet>

      {viewing && <CoverViewer url={entry.coverUrl} art={entry.art} title={entry.title} onClose={() => setViewing(false)} onEdit={() => { setViewing(false); setPanel('edit') }} />}
      {panel === 'edit' && <EditDetailsSheet entry={entry} onClose={() => setPanel(null)} />}
      {panel === 'addTo' && adding.size > 0 && <AddToEntrySheet entry={entry} chapterIds={adding} onClose={() => { setPanel(null); setAdding(new Set()) }} />}
      {panel === 'move' && moving && <MoveSheet entry={entry} chapter={moving} onClose={() => { setPanel(null); setMoving(null) }} />}

      {sheetChapter && (
        <ChapterSheet entryId={entry.id} chapter={sheetChapter} onClose={() => setSheetFor(null)}
          onMove={() => { setMoving(sheetChapter); setSheetFor(null); setPanel('move') }}
          onAddTo={() => { setAdding(new Set([sheetChapter.id])); setSheetFor(null); setPanel('addTo') }}
          onInsert={() => { setInsertAfter(sheetChapter); setSheetFor(null); setPanel('insert') }} canEdit={!!entry.remote} />
      )}

      {panel === 'insert' && insertAfter && !pickedTitle && (
        <SourcePicker query={entry.title} title={`Insert after ${insertAfter.label}`} onClose={() => { setPanel(null); setInsertAfter(null) }}
          onPick={(m) => setPickedTitle(m)} />
      )}
      {panel === 'insert' && insertAfter && pickedTitle && (
        <ChapterPicker title={pickedTitle} onClose={() => { setPanel(null); setPickedTitle(null); setInsertAfter(null) }}
          onPick={(raw) => {
            const c = toChapter(raw, pickedTitle.sourceId)
            store.insertChapter(entry.id, {
              sourceId: pickedTitle.sourceId, mangaUrl: pickedTitle.mangaUrl, chapterUrl: raw.url, remoteId: raw.id,
              number: insertNumber(insertAfter), label: c.label, fromTitle: pickedTitle.title ?? pickedTitle.name ?? '',
            })
            setPanel(null); setPickedTitle(null); setInsertAfter(null)
          }} />
      )}

      {selecting && (
        <div className="action-bar" role="toolbar" aria-label="Chapter actions">
          <span className="action-bar__count">{selected.size} selected</span>
          <button type="button" disabled={!selected.size} onClick={() => act({ read: true, isNew: false }, 'Marked read:')}><Icon name="check" size={18} />Read</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ read: false }, 'Marked unread:')}><Icon name="undo" size={18} />Unread</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ bookmarked: true }, 'Bookmarked')}><Icon name="bookmark" size={18} />Mark</button>
          <button type="button" disabled={!selected.size} onClick={saveSelected}><Icon name="download" size={18} />Save</button>
          {entry.remote && <button type="button" disabled={!selected.size} onClick={addSelectedTo}><Icon name="plus" size={18} />Add to</button>}
          <button type="button" disabled={!selected.size} onClick={() => act({ removed: true }, 'Removed')}><Icon name="trash" size={18} />Remove</button>
        </div>
      )}
    </div>
  )
}

function MenuRow({ icon, title, detail, onClick }: { icon: Parameters<typeof Icon>[0]['name']; title: string; detail?: string; onClick: () => void }) {
  return (
    <button type="button" className="menu__row" onClick={onClick}>
      <span className="menu__icon"><Icon name={icon} size={20} /></span>
      <span className="menu__text"><strong>{title}</strong>{detail && <span>{detail}</span>}</span>
      <Icon name="chevronRight" size={18} />
    </button>
  )
}

/** Everything for one chapter: which version to read, marks, download, splitting and inserting after it. */
function ChapterSheet({ entryId, chapter, onClose, onInsert, onMove, onAddTo, canEdit }: { entryId: string; chapter: Chapter; onClose: () => void; onInsert: () => void; onMove: () => void; onAddTo: () => void; canEdit: boolean }) {
  const store = useStore()
  const entry = store.entry(entryId)!
  const whole = entry.chapters.find((c) => c.id === physicalIdOf(chapter.id)) ?? chapter
  const splitKey = whole.sourceUrl ? chapterKey(whole.sourceId, whole.sourceUrl) : ''
  const layout = layoutOf(entry.splits?.[splitKey])
  const [splitting, setSplitting] = useState(false)
  const [thumbing, setThumbing] = useState(false)
  const ids = new Set([chapter.id])
  const done = (fn: () => void) => { fn(); onClose() }

  if (splitting) return <PageSplitter entryId={entryId} chapter={whole} layout={layout} onClose={onClose} />
  if (thumbing) return <ThumbSheet entryId={entryId} chapter={chapter} onClose={onClose} />

  return (
    <Sheet open title={chapter.label} onClose={onClose}>
      <p className="hint">{chapter.insertedFrom ? `From ${chapter.insertedFrom}` : chapter.part ?? chapter.title}</p>

      {(whole.alts?.length ?? 0) > 1 && <>
        <div className="label label--flush">Read from</div>
        <div className="check-list">
          {whole.alts!.map((a, i) => (
            <button key={`${a.sourceId}-${a.url}`} type="button" className="check-row" onClick={() => done(() => store.chooseVersion(entryId, whole.id, i))}>
              <span className="check-row__name check-row__name--stack"><strong>{a.name}</strong><span className="card-meta">{a.title}</span></span>
              {a.remoteId === whole.remoteId && <span className="tag tag--accent">Reading</span>}
            </button>
          ))}
        </div>
      </>}

      <div className="sheet-actions">
        <button type="button" onClick={() => done(() => store.editChapters(entryId, ids, chapter.read ? { read: false } : { read: true, isNew: false }))}>
          <Icon name={chapter.read ? 'undo' : 'check'} size={18} />{chapter.read ? 'Mark unread' : 'Mark read'}
        </button>
        <button type="button" onClick={() => done(() => store.editChapters(entryId, ids, { bookmarked: !chapter.bookmarked }))}>
          <Icon name={chapter.bookmarked ? 'bookmarkFill' : 'bookmark'} size={18} />{chapter.bookmarked ? 'Remove bookmark' : 'Bookmark'}
        </button>
        {canEdit && (
          <button type="button" onClick={() => done(() => (chapter.downloaded ? store.removeDownloads(entryId, ids) : store.downloadChapters(entryId, ids)))}>
            <Icon name={chapter.downloaded ? 'trash' : 'download'} size={18} />{chapter.downloaded ? 'Remove download' : 'Download'}
          </button>
        )}
        {canEdit && !chapter.insertId && (
          <button type="button" onClick={() => setSplitting(true)}>
            <Icon name="layers" size={18} />{layout ? 'Edit pages & parts' : 'Split or trim pages'}
          </button>
        )}
        {canEdit && entry.custom?.thumbs && <button type="button" onClick={() => setThumbing(true)}><Icon name="image" size={18} />Edit thumbnail</button>}
        {canEdit && <button type="button" onClick={onInsert}><Icon name="plus" size={18} />Insert after</button>}
        <button type="button" onClick={onMove}><Icon name="sort" size={18} />Move</button>
        {whole.order != null && <button type="button" onClick={() => done(() => store.resetOrder(entryId, whole.id))}><Icon name="undo" size={18} />Original place</button>}
        {canEdit && <button type="button" onClick={onAddTo}><Icon name="plus" size={18} />Add to entry</button>}
        <button type="button" onClick={() => done(() => store.editChapters(entryId, ids, { removed: true }))}>
          <Icon name="trash" size={18} />{chapter.insertId ? 'Remove insert' : 'Hide chapter'}
        </button>
      </div>

    </Sheet>
  )
}

/** Lists a title's chapters on its source, to insert one into an entry. */
function ChapterPicker({ title, onPick, onClose }: { title: PickedTitle; onPick: (c: SChapter) => void; onClose: () => void }) {
  const [list, setList] = useState<SChapter[] | null>(null)
  const [error, setError] = useState<string>()
  useEffect(() => {
    getChapters(title.mangaId).then((l) => setList([...l].sort((a, b) => b.chapterNumber - a.chapterNumber))).catch((e: Error) => setError(e.message))
  }, [title.mangaId])
  return (
    <Sheet open title={title.title ?? 'Pick a chapter'} onClose={onClose}>
      {error && <Empty tone="error" icon="alert" title="Couldn't load chapters" detail={error} />}
      {!list && !error && <Loading label="Loading chapters" shape="rows" />}
      {list && !list.length && <Empty icon="book" title="No chapters" detail="This source has no chapters for the title." />}
      <div className="check-list">
        {list?.map((c) => (
          <button key={c.id} type="button" className="check-row" onClick={() => onPick(c)}>
            <span className="check-row__name check-row__name--stack"><strong>{toChapter(c, title.sourceId).label}</strong><span className="card-meta">{c.name}{c.scanlator ? ` · ${c.scanlator}` : ''}</span></span>
            <Icon name="plus" size={18} />
          </button>
        ))}
      </div>
    </Sheet>
  )
}
