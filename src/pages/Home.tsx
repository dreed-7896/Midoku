import { useEffect, useMemo, useRef, useState } from 'react'
import { TLink as Link, useNav } from '../components/Nav'
import { Cover } from '../components/Art'
import { IconButton, PageHead, SectionHead, ServerStatus } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { Empty, Loading } from '../components/Status'
import { UpdateRow } from '../components/UpdateRow'
import { openChapter } from '../data/openChapter'
import { useUpdates, type Update } from '../data/updates'
import { catalogFor } from '../data/mock'
import { artFor, assetUrl, browseSource, getSources, type SMangaCard, type SSource } from '../data/suwayomi'
import { agoText, resumeChapter, useStore } from '../data/store'

export default function Home() {
  const store = useStore()
  const nav = useNav()
  const { entries, queue } = store
  const feed = useUpdates(store)
  const [opening, setOpening] = useState<string>()
  const [slide, setSlide] = useState(0)
  const rail = useRef<HTMLDivElement>(null)

  const library = entries.filter((e) => e.inLibrary)
  const continuing = library.filter((e) => e.lastReadAgo !== undefined && resumeChapter(e))
    .sort((a, b) => (a.lastReadAgo ?? 0) - (b.lastReadAgo ?? 0)).slice(0, 3)
  const totalNew = feed.unseen
  // Home previews the newest updates; the full list (and its actions) is on the Updates screen.
  const preview = (feed.items ?? []).filter((u) => !u.read).slice(0, 6)
  const open = async (u: Update) => {
    setOpening(u.key)
    try { await openChapter(store, (to) => nav.go(to), u.entryId, { chapterId: u.chapterId, sourceId: u.sourceId, url: u.url }) }
    catch (err) { store.toast(`Couldn't open it: ${(err as Error).message}`) }
    finally { setOpening(undefined) }
  }
  const trending = useMemo(() => catalogFor('mangadex').slice(0, 3), [])
  const weekday = new Date().toLocaleDateString('en', { weekday: 'long' })

  const onScroll = () => {
    const el = rail.current
    if (el) setSlide(Math.round(el.scrollLeft / el.clientWidth))
  }

  return (
    <div className="page">
      <PageHead kicker={`${weekday} · ${totalNew} new`} title="Feed">
        <IconButton icon="clock" label="History" onClick={() => nav.go('/history')} />
        <IconButton icon="settings" label="Settings" onClick={() => nav.go('/settings')} />
        <IconButton icon="bell" label={`Updates, ${totalNew} new`} badge={totalNew || undefined} onClick={() => nav.go('/updates')} />
      </PageHead>

      {continuing.length > 0 && (
        <section aria-label="Continue reading" className="pad-t">
          <div className="hero-rail" ref={rail} onScroll={onScroll}>
            {continuing.map((e) => {
              const ch = resumeChapter(e)!
              const pct = ch.pages ? Math.round((Math.max(ch.page, 0) / ch.pages) * 100) : 0
              return (
                <div key={e.id} className="hero" style={{ background: e.art.c1 }}>
                  <span className="hero__glow" style={{ background: e.art.c2 }} />
                  <Link to={`/entry/${e.id}`} className="hero__cover"><Cover art={e.art} title={e.title} url={e.coverUrl} /></Link>
                  <div className="hero__body">
                    <span className="tag tag--glass">Continue · {agoText(e.lastReadAgo ?? 0)}</span>
                    <div className="hero__title">{e.title}</div>
                    <div className="hero__sub">{ch.label} · {ch.title}</div>
                    <div className="hero__progress">
                      <span className="bar bar--light"><span style={{ width: `${pct}%` }} /></span>
                      <span>{ch.page} / {ch.pages}</span>
                    </div>
                    <button type="button" className="btn btn--light" onClick={() => nav.go(`/read/${e.id}/${ch.id}`)}>
                      <Icon name="play" size={14} /> Resume
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
          <div className="dots" aria-hidden="true">
            {continuing.map((e, i) => <span key={e.id} className={i === slide ? 'is-on' : ''} />)}
          </div>
        </section>
      )}

      <ServerStatus />

      {queue.length > 0 && <section className="section">
        <SectionHead title="Reading queue" count={queue.length} />
        <div className="rail">
          {queue.map((id) => store.entry(id)).filter(Boolean).map((e) => {
            const ch = resumeChapter(e!)
            return (
              <Link key={e!.id} to={`/entry/${e!.id}`} className="rail__item">
                <Cover art={e!.art} title={e!.title} url={e!.coverUrl} />
                <div className="card-title">{e!.title}</div>
                <div className="card-meta">{ch ? ch.label : 'Caught up'}</div>
              </Link>
            )
          })}
        </div>
      </section>}

      <section className="section pad-x">
        <div className="section-head section-head--flush">
          <h2 className="h2">Updates{totalNew > 0 && <span className="h2__count">{totalNew} new</span>}</h2>
          <button type="button" className="link-btn" onClick={() => nav.go('/updates')}>See all</button>
        </div>
        {!feed.items && !feed.error && <Loading label="Loading updates" shape="rows" count={2} />}
        {feed.error && <Empty compact icon="alert" tone="error" title="Couldn't load updates" detail={feed.error.slice(0, 140)} />}
        {feed.items && !preview.length && <Empty compact icon="check" tone="done" title="All caught up" detail="New chapters, and new pages in recent chapters, show up here." />}
        {preview.length > 0 && (
          <div className="check-list">
            {preview.map((u) => <UpdateRow key={u.key} u={u} fresh={u.at > feed.seenAt} busy={opening === u.key} onOpen={() => void open(u)} />)}
          </div>
        )}
      </section>

      <section className="section pad-x">
        {store.server.status !== 'off' && <PopularPanel />}

        {store.server.status === 'off' && <div className="panel">
          <div className="panel__head">
            <span className="source-icon" style={{ width: 30, height: 30, background: '#5A3415', fontSize: 14 }} aria-hidden="true">M</span>
            <div className="grow">
              <div className="panel__title">Trending on MangaDex</div>
              <div className="card-meta">From your sources</div>
            </div>
            <Link to="/sources/mangadex" className="link-btn">Browse</Link>
          </div>
          <div className="grid3">
            {trending.map((t) => (
              <Link key={t.id} to={t.entryId ? `/entry/${t.entryId}` : '/sources/mangadex'} className="card">
                <Cover art={t.art} title={t.title} />
                <div className="card-title">{t.title}</div>
                <div className="card-meta">{t.publishing}</div>
              </Link>
            ))}
          </div>
        </div>}
      </section>
    </div>
  )
}

// Kept for the session so Home doesn't ask the source again on every visit.
let popularCache: { sourceId: string; items: SMangaCard[] } | null = null
let sourcesCache: (SSource & { extension: { pkgName: string } | null })[] | null = null
const HOME_SOURCE = 'midoku.homeSource'

/** Popular titles from one source: the one chosen here, or the source most of the library comes from. */
function PopularPanel() {
  const store = useStore()
  const [sources, setSources] = useState(sourcesCache)
  const [chosen, setChosen] = useState<string>(() => { try { return localStorage.getItem(HOME_SOURCE) ?? '' } catch { return '' } })
  const [items, setItems] = useState<SMangaCard[] | null>(null)
  const [error, setError] = useState<string>()

  useEffect(() => { getSources().then((l) => { sourcesCache = l; setSources(l) }).catch((e: Error) => setError(e.message)) }, [])
  const sourceId = useMemo(() => {
    if (!sources?.length) return ''
    if (chosen && sources.some((s) => s.id === chosen)) return chosen
    const count = new Map<string, number>()
    for (const e of store.entries) if (e.inLibrary) { const m = e.sources.find((s) => s.main)?.sourceId; if (m) count.set(m, (count.get(m) ?? 0) + 1) }
    return [...sources].sort((a, b) => (count.get(b.id) ?? 0) - (count.get(a.id) ?? 0))[0].id
  }, [sources, chosen, store.entries])
  const source = sources?.find((s) => s.id === sourceId)

  useEffect(() => {
    if (!sourceId) return
    if (popularCache?.sourceId === sourceId) { setItems(popularCache.items); return }
    let alive = true
    setItems(null); setError(undefined)
    browseSource(sourceId, 'POPULAR', 1)
      .then((r) => { if (!alive) return; popularCache = { sourceId, items: r.mangas.slice(0, 12) }; setItems(popularCache.items) })
      .catch((e: Error) => alive && setError(e.message))
    return () => { alive = false }
  }, [sourceId])

  if (sources && !sources.length) return null
  const pick = (id: string) => { setChosen(id); try { localStorage.setItem(HOME_SOURCE, id) } catch { /* per session then */ } }
  return (
    <div className="panel">
      <div className="panel__head">
        <div className="grow">
          <div className="panel__title">Popular{source ? ` on ${source.displayName}` : ''}</div>
          <label className="select-box select-box--inline">
            <select value={sourceId} onChange={(e) => pick(e.target.value)} aria-label="Source for popular titles">
              {sources?.map((s) => <option key={s.id} value={s.id}>{s.displayName}</option>)}
            </select>
            <Icon name="chevronDown" size={12} stroke={2} />
          </label>
        </div>
        {source?.extension && <Link to={`/sources/${encodeURIComponent(source.extension.pkgName)}`} className="link-btn">Browse</Link>}
      </div>
      {error && <Empty compact icon="alert" tone="error" title="Couldn't load popular titles" detail={error.split('\n')[0].slice(0, 140)} />}
      {!items && !error && <div className="card-meta">Loading…</div>}
      {items && (
        <div className="rail rail--flush">
          {items.map((m) => (
            <Link key={m.id} to={`/entry/s${m.id}`} className="rail__item">
              <Cover art={artFor(m.id)} title={m.title} url={assetUrl(m.thumbnailUrl)} />
              <div className="card-title">{m.title}</div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
