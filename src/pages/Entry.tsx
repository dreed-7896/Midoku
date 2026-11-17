import { useCallback, useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { TLink as Link, useNav } from '../components/Nav'
import { Cover, PageThumb, SourceIcon } from '../components/Art'
import { Chip, IconButton, SectionHead, Sheet } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { agoLabel, newCount, progressPct, readCount, resumeChapter, statusOf, unreadCount, useStore, visibleChapters } from '../data/store'
import { chapterKey, useDownloads } from '../data/downloads'
import { SourcePicker } from '../components/SourcePicker'
import { Chapter, STATUS_LABEL } from '../data/types'

type ChapterFilter = 'all' | 'unread' | 'bookmarked' | 'downloaded'

export default function EntryPage() {
  const { id = '' } = useParams()
  const store = useStore()
  const nav = useNav()
  const entry = store.entry(id)
  const [expanded, setExpanded] = useState(false)
  const [filter, setFilter] = useState<ChapterFilter>('all')
  const [descending, setDescending] = useState(true)
  const [selecting, setSelecting] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [showRemoved, setShowRemoved] = useState(false)
  const [filing, setFiling] = useState(false)
  const [refreshing, setRefreshing] = useState(false)
  const [shown, setShown] = useState(24)

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
  const [sourcesOpen, setSourcesOpen] = useState(false)
  const [linking, setLinking] = useState(false)
  const [nesting, setNesting] = useState(false)
  const downloads = useDownloads()
  useEffect(() => {
    if (remoteId !== null && !entry?.remote?.chaptersLoaded) loadRemote()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [remoteId])

  const chapters = useMemo(() => {
    if (!entry) return []
    const list = visibleChapters(entry).filter((c) =>
      filter === 'unread' ? !c.read : filter === 'bookmarked' ? c.bookmarked : filter === 'downloaded' ? c.downloaded : true)
    return list.sort((a, b) => (descending ? b.number - a.number : a.number - b.number))
  }, [entry, filter, descending])

  if (!entry) {
    return (
      <div className="page">
        <div className="entry__top"><IconButton icon="back" label="Back" onClick={() => nav.back('/library')} /></div>
        <div className="pad-x pad-t">
          {remoteId !== null && !remote.error ? <p className="hint">Loading…</p> : (
            <>
              <p className="empty">{remote.error ?? "This title isn't in your library."}</p>
              {remoteId !== null && <button type="button" className="btn btn--ghost" onClick={() => loadRemote()}>Try again</button>}
            </>
          )}
        </div>
      </div>
    )
  }

  const all = visibleChapters(entry)
  const userTabs = store.tabs.filter((t) => t.kind === 'tab')
  const removed = entry.chapters.filter((c) => c.removed)
  const kids = store.children(entry.id)
  const resume = resumeChapter(entry)
  const counts = {
    unread: unreadCount(entry),
    bookmarked: all.filter((c) => c.bookmarked).length,
    downloaded: all.filter((c) => c.downloaded).length,
  }

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

  const act = (patch: Partial<Chapter>, message: string) => {
    store.editChapters(entry.id, selected, patch)
    store.toast(`${message} ${selected.size} chapter${selected.size === 1 ? '' : 's'}`)
    setSelected(new Set())
    setSelecting(false)
  }
  // Saves the selected chapters on the device, or removes them when all are saved already.
  const saveSelected = () => {
    const picked = entry.chapters.filter((c) => selected.has(c.id))
    if (picked.length && picked.every((c) => c.downloaded)) store.removeDownloads(entry.id, selected)
    else if (entry.remote) store.downloadChapters(entry.id, selected)
    else act({ downloaded: true }, 'Downloaded')
    setSelected(new Set())
    setSelecting(false)
  }
  const downloadUnread = () => {
    if (!entry.remote) { store.toast(`Queued ${counts.unread} chapters`); return }
    store.downloadChapters(entry.id, new Set(all.filter((c) => !c.read && !c.downloaded).map((c) => c.id)))
  }
  const progressOf = (c: Chapter) => {
    if (!c.sourceUrl) return undefined
    const key = chapterKey(c.sourceId, c.sourceUrl)
    if (downloads.active?.key === key) return downloads.active.progress
    return downloads.queued.has(key) ? 0 : undefined
  }
  const library = store.entries.filter((e) => e.inLibrary && e.id !== entry.id && !e.parentId && !store.children(e.id).length)
  const parent = entry.parentId ? store.entry(entry.parentId) : undefined

  const refresh = async () => {
    setRefreshing(true)
    if (entry.remote) await loadRemote(true)
    else await new Promise((r) => setTimeout(r, 1200)).then(() => store.toast('Up to date'))
    setRefreshing(false)
  }

  return (
    <div className="page entry">
      <div className="entry__backdrop" style={{ background: entry.art.c1 }} aria-hidden="true">
        <span style={{ background: entry.art.c2 }} />
      </div>

      <div className="entry__top">
        <IconButton icon="back" label="Back" glass onClick={() => nav.back('/library')} />
        <div className="row-gap">
          <IconButton icon="globe" label="Open source website" glass onClick={() => (entry.remote?.url ? window.open(entry.remote.url, '_blank', 'noopener') : store.toast('No web page for this title'))} />
          <IconButton icon="more" label="Entry options" glass onClick={() => store.toast('Edit, migrate and sources menu comes later')} />
        </div>
      </div>

      <div className="entry__hero">
        <button type="button" className="entry__cover" aria-label="View cover"><Cover art={entry.art} title={entry.title} url={entry.coverUrl} /></button>
        <h1 className="entry__title">{entry.title}</h1>
        <div className="entry__author">{entry.author}</div>
        <div className="entry__meta">
          <span className="tag tag--glass"><span className={`dot dot--${entry.publishing.toLowerCase()}`} />{entry.publishing}</span>
          <span className="tag tag--glass">{all.length} chapters</span>
          <span className="tag tag--glass">{entry.sources.length} source{entry.sources.length === 1 ? '' : 's'}</span>
        </div>
      </div>

      <div className="entry__actions pad-x">
        <button type="button" className="btn btn--accent btn--xl grow" disabled={!resume} onClick={() => resume && openChapter(resume)}>
          <Icon name="play" size={16} />
          <span className="btn__stack">
            <span>{readCount(entry) ? 'Resume' : 'Start reading'}</span>
            <small>{resume ? `${resume.label}${resume.page ? ` · page ${resume.page}` : ''}` : 'All caught up'}</small>
          </span>
        </button>
        <button type="button" className={`icon-btn icon-btn--xl${entry.inLibrary ? ' is-accent' : ''}`} aria-pressed={entry.inLibrary}
          aria-label={entry.inLibrary ? 'Remove from library' : 'Add to library'} onClick={() => store.toggleLibrary(entry.id)}>
          <Icon name={entry.inLibrary ? 'bookmarkFill' : 'bookmark'} />
        </button>
        <IconButton icon="download" label="Download unread chapters" onClick={downloadUnread} />
        <button type="button" className={`icon-btn icon-btn--xl${refreshing ? ' is-spinning' : ''}`} aria-label="Refresh entry" onClick={refresh}>
          <Icon name="refresh" />
        </button>
      </div>

      {remote.saved && <p className="hint pad-x pad-t">Offline · showing the copy saved on this device.</p>}

      <div className="chips pad-x pad-t">
        {parent && <Link to={`/entry/${parent.id}`} className="chip"><Icon name="library" size={14} />{parent.title}</Link>}
        <span className="chip chip--static" title="Set automatically from your reading progress">
          <span className={`dot dot--status-${statusOf(entry)}`} />{STATUS_LABEL[statusOf(entry)]}
        </span>
        {userTabs.filter((t) => entry.tabs.includes(t.id)).map((t) => (
          <button key={t.id} type="button" className="chip" onClick={() => setFiling(true)}>{t.name}</button>
        ))}
        <button type="button" className="chip chip--dashed" onClick={() => setFiling(true)}>
          <Icon name="plus" size={15} />{entry.tabs.length ? '' : 'Add to tab'}
        </button>
      </div>

      <div className="pad-x pad-t">
        <div className="panel panel--flush">
          <div className="split">
            <strong>{readCount(entry)} of {all.length} read</strong>
            <span className="accent-text">{counts.unread} unread</span>
          </div>
          <span className="bar bar--thick"><span style={{ width: `${progressPct(entry)}%` }} /></span>
          <div className="card-meta">
            {entry.lastReadAgo !== undefined ? `Last read ${agoLabel(entry.lastReadAgo)} ago` : 'Not started'} · {counts.bookmarked} bookmarks · {counts.downloaded} downloaded
          </div>
        </div>
      </div>

      <div className="pad-x pad-t">
        <p className={`desc${expanded ? ' is-open' : ''}`}>{entry.description}</p>
        <button type="button" className="link-btn" onClick={() => setExpanded((x) => !x)}>{expanded ? 'Less' : 'More'}</button>
      </div>

      <div className="chips pad-x pad-t-sm">
        {entry.tags.map((t) => <span key={t} className="tag">{t}</span>)}
      </div>

      <section className="section pad-x">
        <SectionHead title="Sources" count={entry.sources.length} action="Manage"
          onAction={() => (entry.remote ? setSourcesOpen(true) : store.toast('Linking sources needs a server'))} />
        <div className="grid3">
          {entry.sources.map((s, i) => {
            // Server sources are not in the local list; their name and icon travel with the title.
            const src = store.source(s.sourceId) ?? (s.name ? { name: s.name, letter: s.name[0], color: '#22222A', lang: '' } : undefined)
            if (!src) return null
            return (
              <div key={`${s.sourceId}-${s.mangaUrl ?? i}`} className={`tile${s.main ? ' tile--main' : ''}`}>
                <div className="split">
                  <SourceIcon letter={src.letter} color={src.color} size={38} url={s.iconUrl} />
                  {s.main && <span className="tag tag--accent">Main</span>}
                </div>
                <div className="tile__name">{src.name}</div>
                <div className="card-meta">{s.chapters} ch{src.lang ? ` · ${src.lang}` : ''}</div>
                <label className="switch-row">
                  <input type="checkbox" role="switch" className="switch" checked={s.following} onChange={() => store.toggleFollow(entry.id, s.sourceId, s.mangaUrl)}
                    aria-label={`Follow new chapters from ${src.name}`} />
                  <span>{s.following ? 'Following' : 'Paused'}</span>
                </label>
              </div>
            )
          })}
        </div>
      </section>

      {(kids.length > 0 || !entry.parentId) && (
        <section className="section pad-x">
          <SectionHead title="Titles in this entry" count={kids.length} />
          <div className="grid3">
            {kids.map((k) => (
              <Link key={k.id} to={`/entry/${k.id}`} className="card">
                <div className="thumb">
                  <Cover art={k.art} title={k.title} url={k.coverUrl} />
                  {newCount(k) > 0 && <span className="badge badge--tr">{newCount(k)}</span>}
                </div>
                <div className="card-title card-title--2">{k.title}</div>
                <div className="card-meta">{visibleChapters(k).length} ch · {unreadCount(k)} unread</div>
              </Link>
            ))}
            <button type="button" className="add-tile" onClick={() => (entry.remote || !store.entries.some((e) => e.remote) ? setNesting(true) : store.toast('Nesting needs a server title'))}>
              <Icon name="plus" size={22} />Add title
            </button>
          </div>
        </section>
      )}

      <section className="section pad-x">
        <div className="section-head">
          <h2 className="h2">Chapters<span className="h2__count">{entry.remote && !entry.remote.chaptersLoaded ? '…' : all.length}</span></h2>
          <div className="row-gap">
            <IconButton icon="sort" label={descending ? 'Show oldest first' : 'Show newest first'} onClick={() => setDescending((d) => !d)} />
            <IconButton icon="select" label={selecting ? 'Done selecting' : 'Select chapters'} active={selecting}
              onClick={() => { setSelecting((s) => !s); setSelected(new Set()) }} />
          </div>
        </div>
        <div className="chips">
          <Chip on={filter === 'all'} onClick={() => setFilter('all')}>All</Chip>
          <Chip on={filter === 'unread'} onClick={() => setFilter('unread')}>Unread {counts.unread}</Chip>
          <Chip on={filter === 'bookmarked'} onClick={() => setFilter('bookmarked')}>Bookmarked {counts.bookmarked}</Chip>
          <Chip on={filter === 'downloaded'} onClick={() => setFilter('downloaded')}>Downloaded {counts.downloaded}</Chip>
        </div>

        {entry.remote && !entry.remote.chaptersLoaded && <p className="hint pad-t">{remote.error ? `Couldn't load chapters: ${remote.error}` : 'Loading chapters…'}</p>}
        {entry.remote && remote.error && entry.remote.chaptersLoaded && <p className="hint pad-t">Refresh failed: {remote.error}</p>}
        <div className="grid3 pad-t">
          {chapters.slice(0, shown).map((c) => {
            const current = resume?.id === c.id
            const isSelected = selected.has(c.id)
            return (
              <button key={c.id} type="button" className={`chapter${current ? ' is-current' : ''}${isSelected ? ' is-selected' : ''}`}
                aria-pressed={selecting ? isSelected : undefined} onClick={() => openChapter(c)}>
                <div className={`chapter__thumb${c.read ? ' is-read' : ''}`}>
                  <PageThumb layout={c.layout} />
                  {c.isNew && !c.read && <span className="badge badge--tl">New</span>}
                  {!c.isNew && c.versions > 1 && <span className="badge badge--tl badge--glass">{c.versions} versions</span>}
                  {c.insertedFrom && <span className="badge badge--tl badge--glass">Added</span>}
                  {c.part && <span className="badge badge--tl badge--glass">Split</span>}
                  <span className="chapter__flags">
                    {c.bookmarked && <span className="flag flag--accent"><Icon name="bookmarkFill" size={11} label="Bookmarked" /></span>}
                    {c.downloaded && <span className="flag"><Icon name="download" size={12} stroke={2.2} label="Downloaded" /></span>}
                    {!c.downloaded && progressOf(c) !== undefined && <span className="flag">{Math.round(progressOf(c)! * 100)}%</span>}
                  </span>
                  {c.read && <span className="badge badge--bl badge--glass"><Icon name="check" size={11} stroke={2.6} />Read</span>}
                  {current && c.page > 0 && <span className="chapter__progress"><span style={{ width: `${(c.page / c.pages) * 100}%` }} /></span>}
                  {selecting && <span className={`chapter__check${isSelected ? ' is-on' : ''}`}>{isSelected && <Icon name="check" size={14} stroke={2.6} />}</span>}
                </div>
                <div className="card-title">{c.label}</div>
                <div className="card-meta">{c.part ?? (c.insertedFrom ? `${c.title} · from ${c.insertedFrom}` : current && c.page ? `${c.title} · p. ${c.page}` : `${c.title} · ${c.date}`)}</div>
              </button>
            )
          })}
        </div>
        {chapters.length > shown && (
          <div className="center pad-t">
            <button type="button" className="btn btn--ghost" onClick={() => setShown((n) => n + 24)}>Show more · {chapters.length - shown} left</button>
          </div>
        )}

        {removed.length > 0 && (
          <div className="center pad-t">
            <button type="button" className="btn btn--ghost" onClick={() => setShowRemoved((x) => !x)}>
              <Icon name="undo" size={15} /> {removed.length} removed chapters · {showRemoved ? 'Hide' : 'Restore'}
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
      </section>

      <Sheet open={filing} title="Library tabs" onClose={() => setFiling(false)}>
        <p className="hint">Pick the tabs this title shows in. A title can be in more than one.</p>
        <div className="check-list">
          {userTabs.map((t) => (
            <label key={t.id} className="check-row">
              <span className="check-row__name">{t.name}</span>
              <input type="checkbox" checked={entry.tabs.includes(t.id)} onChange={() => store.toggleInTab(entry.id, t.id)} />
            </label>
          ))}
        </div>
        <button type="button" className="btn btn--ghost btn--block" onClick={() => {
          const name = window.prompt('Name the new tab')
          if (name?.trim()) store.toggleInTab(entry.id, store.createTab(name.trim()))
        }}><Icon name="plus" size={16} />New tab</button>
      </Sheet>

      <Sheet open={sourcesOpen} title="Sources" onClose={() => setSourcesOpen(false)}>
        <p className="hint">Chapters from every source are merged; the main source is the one read and supplies the details.</p>
        <div className="check-list">
          {entry.sources.map((s, i) => (
            <div key={`${s.sourceId}-${s.mangaUrl ?? i}`} className="check-row">
              <span className="check-row__name">{s.name ?? s.sourceId}<span className="card-meta"> · {s.chapters} ch{s.following ? '' : ' · paused'}</span></span>
              {s.main ? <span className="tag tag--accent">Main</span> : (
                <span className="row-gap">
                  <button type="button" className="btn btn--ghost btn--sm" onClick={() => store.setMainSource(entry.id, s.sourceId, s.mangaUrl)}>Make main</button>
                  <button type="button" className="btn btn--ghost btn--sm" onClick={() => store.unlinkSource(entry.id, s.sourceId, s.mangaUrl)}>Unlink</button>
                </span>
              )}
            </div>
          ))}
        </div>
        <button type="button" className="btn btn--ghost btn--block" onClick={() => { setSourcesOpen(false); setLinking(true) }}><Icon name="plus" size={16} />Link another source</button>
      </Sheet>

      {linking && <SourcePicker query={entry.title} onClose={() => setLinking(false)}
        onPick={(m) => { setLinking(false); void store.linkSource(entry.id, m) }} />}

      <Sheet open={nesting} title="Titles in this entry" onClose={() => setNesting(false)}>
        <p className="hint">Pick library titles to show inside “{entry.title}”, like volumes or seasons of a series.</p>
        <div className="check-list">
          {[...kids, ...library].map((t) => (
            <label key={t.id} className="check-row">
              <span className="check-row__name">{t.title}</span>
              <input type="checkbox" checked={t.parentId === entry.id} onChange={() => store.setParent(t.id, t.parentId === entry.id ? undefined : entry.id)} />
            </label>
          ))}
          {!kids.length && !library.length && <p className="hint">No other library titles to nest.</p>}
        </div>
      </Sheet>

      {selecting && (
        <div className="action-bar" role="toolbar" aria-label="Chapter actions">
          <span className="action-bar__count">{selected.size} selected</span>
          <button type="button" disabled={!selected.size} onClick={() => act({ read: true, isNew: false }, 'Marked read:')}><Icon name="check" size={18} />Read</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ read: false }, 'Marked unread:')}><Icon name="undo" size={18} />Unread</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ bookmarked: true }, 'Bookmarked')}><Icon name="bookmark" size={18} />Mark</button>
          <button type="button" disabled={!selected.size} onClick={saveSelected}><Icon name="download" size={18} />Save</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ removed: true }, 'Removed')}><Icon name="trash" size={18} />Remove</button>
        </div>
      )}
    </div>
  )
}
