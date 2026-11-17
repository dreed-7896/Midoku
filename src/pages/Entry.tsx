import { useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { TLink as Link, useNav } from '../components/Nav'
import { Cover, PageThumb, SourceIcon } from '../components/Art'
import { Chip, IconButton, SectionHead, Sheet } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { agoLabel, newCount, progressPct, readCount, resumeChapter, statusOf, unreadCount, useStore, visibleChapters } from '../data/store'
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

  const chapters = useMemo(() => {
    if (!entry) return []
    const list = visibleChapters(entry).filter((c) =>
      filter === 'unread' ? !c.read : filter === 'bookmarked' ? c.bookmarked : filter === 'downloaded' ? c.downloaded : true)
    return list.sort((a, b) => (descending ? b.number - a.number : a.number - b.number))
  }, [entry, filter, descending])

  if (!entry) {
    return (
      <div className="page pad-x">
        <p className="empty">This title isn't in your library.</p>
        <Link to="/library" className="btn btn--ghost">Back to library</Link>
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

  const refresh = () => {
    setRefreshing(true)
    setTimeout(() => { setRefreshing(false); store.toast('Up to date') }, 1200)
  }

  return (
    <div className="page entry">
      <div className="entry__backdrop" style={{ background: entry.art.c1 }} aria-hidden="true">
        <span style={{ background: entry.art.c2 }} />
      </div>

      <div className="entry__top">
        <IconButton icon="back" label="Back" glass onClick={() => nav.back('/library')} />
        <div className="row-gap">
          <IconButton icon="globe" label="Open source website" glass onClick={() => store.toast('Opens the source page in the browser')} />
          <IconButton icon="more" label="Entry options" glass onClick={() => store.toast('Edit, migrate and sources menu comes later')} />
        </div>
      </div>

      <div className="entry__hero">
        <button type="button" className="entry__cover" aria-label="View cover"><Cover art={entry.art} title={entry.title} /></button>
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
        <IconButton icon="download" label="Download unread chapters" onClick={() => store.toast(`Queued ${counts.unread} chapters`)} />
        <button type="button" className={`icon-btn icon-btn--xl${refreshing ? ' is-spinning' : ''}`} aria-label="Refresh entry" onClick={refresh}>
          <Icon name="refresh" />
        </button>
      </div>

      <div className="chips pad-x pad-t">
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
        <SectionHead title="Sources" count={entry.sources.length} action="Manage" onAction={() => store.toast('Source manager comes later')} />
        <div className="grid3">
          {entry.sources.map((s) => {
            const src = store.source(s.sourceId)
            if (!src) return null
            return (
              <div key={s.sourceId} className={`tile${s.main ? ' tile--main' : ''}`}>
                <div className="split">
                  <SourceIcon letter={src.letter} color={src.color} size={38} />
                  {s.main && <span className="tag tag--accent">Main</span>}
                </div>
                <div className="tile__name">{src.name}</div>
                <div className="card-meta">{s.chapters} ch · {src.lang}</div>
                <label className="switch-row">
                  <input type="checkbox" role="switch" className="switch" checked={s.following} onChange={() => store.toggleFollow(entry.id, s.sourceId)}
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
                  <Cover art={k.art} title={k.title} />
                  {newCount(k) > 0 && <span className="badge badge--tr">{newCount(k)}</span>}
                </div>
                <div className="card-title card-title--2">{k.title}</div>
                <div className="card-meta">{visibleChapters(k).length} ch · {unreadCount(k)} unread</div>
              </Link>
            ))}
            <button type="button" className="add-tile" onClick={() => store.toast('Pick a library title to nest here — comes later')}>
              <Icon name="plus" size={22} />Add title
            </button>
          </div>
        </section>
      )}

      <section className="section pad-x">
        <div className="section-head">
          <h2 className="h2">Chapters<span className="h2__count">{all.length}</span></h2>
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

      {selecting && (
        <div className="action-bar" role="toolbar" aria-label="Chapter actions">
          <span className="action-bar__count">{selected.size} selected</span>
          <button type="button" disabled={!selected.size} onClick={() => act({ read: true, isNew: false }, 'Marked read:')}><Icon name="check" size={18} />Read</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ read: false }, 'Marked unread:')}><Icon name="undo" size={18} />Unread</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ bookmarked: true }, 'Bookmarked')}><Icon name="bookmark" size={18} />Mark</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ downloaded: true }, 'Downloaded')}><Icon name="download" size={18} />Save</button>
          <button type="button" disabled={!selected.size} onClick={() => act({ removed: true }, 'Removed')}><Icon name="trash" size={18} />Remove</button>
        </div>
      )}
    </div>
  )
}
