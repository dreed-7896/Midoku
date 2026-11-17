import { useMemo, useRef, useState } from 'react'
import { TLink as Link, useNav } from '../components/Nav'
import { Cover } from '../components/Art'
import { IconButton, PageHead, SectionHead } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { catalogFor, WEEK } from '../data/mock'
import { agoLabel, newCount, resumeChapter, useStore } from '../data/store'

const DAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S']

export default function Home() {
  const store = useStore()
  const nav = useNav()
  const { entries, queue, updatesSeen } = store
  const [slide, setSlide] = useState(0)
  const rail = useRef<HTMLDivElement>(null)

  const library = entries.filter((e) => e.inLibrary)
  const continuing = library.filter((e) => e.lastReadAgo !== undefined && resumeChapter(e))
    .sort((a, b) => (a.lastReadAgo ?? 0) - (b.lastReadAgo ?? 0)).slice(0, 3)
  const updates = updatesSeen ? [] : library.filter((e) => newCount(e) > 0).sort((a, b) => a.updatedAgo - b.updatedAgo)
  const today = updates.filter((e) => e.updatedAgo < 24)
  const earlier = updates.filter((e) => e.updatedAgo >= 24)
  const totalNew = updates.reduce((n, e) => n + newCount(e), 0)
  const trending = useMemo(() => catalogFor('mangadex').slice(0, 3), [])
  const weekday = new Date().toLocaleDateString('en', { weekday: 'long' })
  const todayIndex = (new Date().getDay() + 6) % 7

  const onScroll = () => {
    const el = rail.current
    if (el) setSlide(Math.round(el.scrollLeft / el.clientWidth))
  }

  return (
    <div className="page">
      <PageHead kicker={`${weekday} · ${totalNew} new chapters`} title="Feed">
        <IconButton icon="settings" label="Settings" onClick={() => nav.go('/settings')} />
        <IconButton icon="bell" label={`Notifications, ${totalNew} new`} badge={totalNew || undefined} />
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
                  <Link to={`/entry/${e.id}`} className="hero__cover"><Cover art={e.art} title={e.title} /></Link>
                  <div className="hero__body">
                    <span className="tag tag--glass">Continue · {agoLabel(e.lastReadAgo ?? 0)} ago</span>
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

      <section className="section">
        <SectionHead title="Reading queue" count={queue.length} />
        <div className="rail">
          {queue.map((id) => store.entry(id)).filter(Boolean).map((e) => {
            const ch = resumeChapter(e!)
            return (
              <Link key={e!.id} to={`/entry/${e!.id}`} className="rail__item">
                <Cover art={e!.art} title={e!.title} />
                <div className="card-title">{e!.title}</div>
                <div className="card-meta">{ch ? ch.label : 'Caught up'}</div>
              </Link>
            )
          })}
        </div>
      </section>

      <section className="section pad-x">
        <div className="section-head section-head--flush">
          <h2 className="h2">New chapters<span className="h2__count">{totalNew}</span></h2>
          {updates.length > 0 && <button type="button" className="link-btn" onClick={store.markUpdatesSeen}>Mark all seen</button>}
        </div>
        {updates.length === 0 && <p className="empty">You're all caught up.</p>}
        {[{ label: 'Today', list: today }, { label: 'Earlier', list: earlier }].filter((g) => g.list.length).map((g) => (
          <div key={g.label}>
            <div className="label">{g.label}</div>
            <div className="grid3">
              {g.list.map((e) => {
                const latest = [...e.chapters].sort((a, b) => b.number - a.number)[0]
                const src = store.source(e.sources.find((s) => s.main)?.sourceId ?? '')
                return (
                  <Link key={e.id} to={`/entry/${e.id}`} className="card">
                    <div className="thumb">
                      <Cover art={e.art} title={e.title} plain />
                      <span className="thumb__scrim" />
                      <span className="thumb__label">{latest.label}</span>
                      <span className="badge badge--tr">+{newCount(e)}</span>
                    </div>
                    <div className="card-title">{e.title}</div>
                    <div className="card-meta">{src?.name} · {agoLabel(e.updatedAgo)}</div>
                  </Link>
                )
              })}
            </div>
          </div>
        ))}

        <div className="panel stats">
          <div>
            <div className="label label--flush">This week</div>
            <div className="stats__big">46 chapters</div>
            <div className="stats__sub">5 h 12 m reading · 4 titles</div>
          </div>
          <div className="stats__bars" aria-label="Chapters read per day this week">
            {WEEK.map((h, i) => (
              <div key={i} className="stats__bar">
                <span style={{ height: h, background: i === todayIndex ? 'var(--accent)' : 'var(--line-2)' }} />
                <small>{DAYS[i]}</small>
              </div>
            ))}
          </div>
        </div>

        <div className="panel">
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
        </div>
      </section>
    </div>
  )
}
