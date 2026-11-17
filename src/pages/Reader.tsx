import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { PageThumb, RemoteImage } from '../components/Art'
import { Icon } from '../components/Icon'
import { useNav } from '../components/Nav'
import { updateSettings, useSettings } from '../data/settings'
import { useStore, visibleChapters } from '../data/store'
import { getPages } from '../data/suwayomi'
import type { Chapter, CoverArt } from '../data/types'

/**
 * Only pages within this distance of the current page are rendered; the rest are empty boxes that keep
 * the scroll length. Long chapters (hundreds of pages) then hold a handful of images in memory, not all.
 */
const WINDOW = 3

/** Placeholder webtoon strip: two panels with a figure and an occasional speech bubble. */
function WebtoonContent({ n, art }: { n: number; art: CoverArt }) {
  const a = (n * 37) % 100
  const split = 38 + (a % 24)
  const panels = [
    { top: 4, h: split, fill: n % 2 ? art.c1 : '#2B2B31', shape: art.c2 },
    { top: split + 8, h: 88 - split, fill: n % 3 === 0 ? art.c2 : '#DCD7CC', shape: art.c1 },
  ]
  return (
    <>
      {panels.map((p, i) => (
        <div key={i} className="wt-panel" style={{ top: `${p.top}%`, height: `${p.h}%`, background: p.fill }}>
          <span className="wt-shape" style={{ background: p.shape, left: `${(a + i * 30) % 55}%`, top: `${18 + (a % 30)}%` }} />
          {(n + i) % 2 === 0 && <span className="wt-bubble" style={{ left: i ? '48%' : '8%' }}><i /><i /><i /></span>}
        </div>
      ))}
      <span className="wt-num">{n}</span>
    </>
  )
}

function PagedContent({ n }: { n: number }) {
  return (
    <>
      <div className="pg-sheet"><PageThumb layout={n} /></div>
      <span className="wt-num">{n}</span>
    </>
  )
}

export default function Reader() {
  const { entryId = '', chapterId = '' } = useParams()
  const store = useStore()
  const nav = useNav()
  const { readerMode: mode } = useSettings()
  const entry = store.entry(entryId)
  const chapter = entry?.chapters.find((c) => c.id === chapterId)
  const ordered = entry ? [...visibleChapters(entry)].sort((a, b) => a.number - b.number) : []
  const index = ordered.findIndex((c) => c.id === chapterId)
  // Measured page heights, so pages that leave the window keep their size (real images vary in height).
  const heights = useRef(new Map<number, number>())
  const prev: Chapter | undefined = ordered[index - 1]
  const next: Chapter | undefined = ordered[index + 1]

  // Server chapters fetch their page list first; sample chapters draw placeholder pages.
  const isRemote = !!chapter?.remoteId
  const [urls, setUrls] = useState<string[] | null>(null)
  const [pagesError, setPagesError] = useState<string>()
  const [loadTry, setLoadTry] = useState(0)
  const loaded = useRef(new Set<number>())
  const [, bump] = useState(0)
  useEffect(() => {
    setUrls(null)
    setPagesError(undefined)
    loaded.current = new Set()
    heights.current = new Map()
    if (!chapter?.remoteId) return
    let alive = true
    getPages(chapter.remoteId)
      .then((list) => {
        if (!alive) return
        setUrls(list)
        if (chapter.pages !== list.length) store.editChapters(entryId, new Set([chapter.id]), { pages: list.length })
      })
      .catch((e: Error) => alive && setPagesError(e.message))
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chapterId, loadTry])
  const pages = isRemote ? urls?.length ?? 0 : chapter?.pages ?? 0

  const scroller = useRef<HTMLDivElement>(null)
  const lastTop = useRef(0)
  const jumping = useRef(false)
  const startPage = useRef(1)
  const [page, setPage] = useState(1)
  const [ui, setUi] = useState(true)

  // When a page above the viewport changes height, shift the scroll so the visible page stays put.
  useEffect(() => {
    const root = scroller.current
    if (!root || mode !== 'webtoon') return
    const ro = new ResizeObserver((items) => {
      for (const it of items) {
        const el = it.target as HTMLElement
        const n = Number(el.dataset.page)
        const before = heights.current.get(n)
        const after = el.offsetHeight
        heights.current.set(n, after)
        if (before !== undefined && before !== after && el.offsetTop + before <= root.scrollTop) root.scrollTop += after - before
      }
    })
    root.querySelectorAll('[data-page]').forEach((el) => ro.observe(el))
    return () => ro.disconnect()
  }, [chapterId, mode, pages])

  // Jumps (opening at a saved page, the slider) must not count as reading-scroll that hides the controls.
  const scrollToPage = useCallback((n: number, behavior: ScrollBehavior = 'auto') => {
    jumping.current = true
    scroller.current?.querySelector(`[data-page="${n}"]`)?.scrollIntoView({ behavior, block: 'start', inline: 'start' })
    setTimeout(() => {
      jumping.current = false
      lastTop.current = scroller.current?.scrollTop ?? 0
    }, behavior === 'smooth' ? 600 : 120)
  }, [])

  // Open at the saved page, or the first page for a finished chapter.
  useLayoutEffect(() => {
    if (!chapter) return
    startPage.current = chapter.read || !chapter.page ? 1 : chapter.page
    setPage(startPage.current)
    scrollToPage(startPage.current)
    setUi(true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chapterId, mode, pages])

  // The page crossing the middle of the screen is the current page.
  useEffect(() => {
    const root = scroller.current
    if (!root) return
    const io = new IntersectionObserver((items) => {
      for (const it of items) if (it.isIntersecting) setPage(Number((it.target as HTMLElement).dataset.page))
    }, { root, rootMargin: mode === 'webtoon' ? '-50% 0px -50% 0px' : '0px -50% 0px -50%' })
    root.querySelectorAll('[data-page]').forEach((el) => io.observe(el))
    return () => io.disconnect()
  }, [chapterId, mode, pages])

  // Save progress shortly after the page settles; the last page marks the chapter read.
  useEffect(() => {
    if (!entry || !chapter || page === startPage.current && page !== pages) return
    const t = setTimeout(() => store.setProgress(entry.id, chapter.id, page), 350)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page])

  if (!entry || !chapter) {
    return (
      <div className="reader reader--empty">
        <p>This chapter isn't available.</p>
        <button type="button" className="btn btn--ghost" onClick={() => nav.back('/library')}>Go back</button>
      </div>
    )
  }

  const close = () => nav.back(`/entry/${entry.id}`)
  // Previous chapter slides in from the left like going back; next comes from the right.
  const goChapter = (c: Chapter) =>
    nav.go(`/read/${entry.id}/${c.id}`, { replace: true, direction: c.number < chapter.number ? 'back' : 'forward' })

  const onScroll = () => {
    const el = scroller.current
    if (!el || mode !== 'webtoon') return
    const delta = el.scrollTop - lastTop.current
    lastTop.current = el.scrollTop
    if (jumping.current) return
    if (delta > 12 && ui) setUi(false)
  }

  const list = Array.from({ length: pages }, (_, i) => i + 1)

  return (
    <div className={`reader reader--${mode}`}>
      <div ref={scroller} className="reader__scroll" onScroll={onScroll} onClick={() => setUi((v) => !v)}>
        {isRemote && !urls && (
          <div className="reader__loading" onClick={(e) => e.stopPropagation()}>
            {pagesError ? (
              <>
                <p>{pagesError}</p>
                <button type="button" className="btn btn--ghost" onClick={() => setLoadTry((n) => n + 1)}>Try again</button>
              </>
            ) : <p className="hint">Loading pages…</p>}
          </div>
        )}
        {list.map((n) => {
          const near = Math.abs(n - page) <= WINDOW
          const known = heights.current.get(n)
          if (isRemote && urls) {
            const onLoad = () => { loaded.current.add(n); bump((x) => x + 1) }
            // Until an image has loaded the box keeps a page-like shape (or its measured height), so scrolling stays steady.
            const style = near
              ? (loaded.current.has(n) ? { aspectRatio: 'auto', minHeight: known } : known ? { height: known, aspectRatio: 'auto' } : undefined)
              : (known ? { height: known, aspectRatio: 'auto' } : undefined)
            return mode === 'webtoon' ? (
              <div key={n} className="wt-page wt-page--img" data-page={n} style={style}>
                {near && <RemoteImage src={urls[n - 1]} alt={`Page ${n}`} className="wt-img" onLoad={onLoad} />}
              </div>
            ) : (
              <div key={n} className="pg-page" data-page={n}>{near && <RemoteImage src={urls[n - 1]} alt={`Page ${n}`} className="pg-img" />}</div>
            )
          }
          return mode === 'webtoon' ? (
            <div key={n} className="wt-page" data-page={n} style={!near && known ? { height: known, aspectRatio: 'auto' } : undefined}>
              {near && <WebtoonContent n={n} art={entry.art} />}
            </div>
          ) : (
            <div key={n} className="pg-page" data-page={n}>{near && <PagedContent n={n} />}</div>
          )
        })}
        {(!isRemote || urls) && <div className="reader__end" onClick={(e) => e.stopPropagation()}>
          <div className="label label--flush">Finished</div>
          <div className="reader__end-title">{chapter.label}</div>
          {next ? (
            <button type="button" className="btn btn--accent btn--xl" onClick={() => goChapter(next)}>
              Next: {next.label} <Icon name="arrowRight" size={18} />
            </button>
          ) : (
            <p className="hint">You're caught up on {entry.title}.</p>
          )}
          <button type="button" className="btn btn--ghost" onClick={close}>Back to {entry.title}</button>
        </div>}
      </div>

      <header className={`reader__top${ui ? '' : ' is-hidden'}`}>
        <button type="button" className="icon-btn icon-btn--glass" aria-label="Close reader" onClick={close}><Icon name="back" /></button>
        <div className="reader__titles">
          <span className="reader__entry">{entry.title}</span>
          <span className="reader__chapter">{chapter.label} · {chapter.part ?? chapter.title}</span>
        </div>
        <button type="button" className="icon-btn icon-btn--glass" aria-label={mode === 'webtoon' ? 'Switch to paged mode' : 'Switch to webtoon mode'}
          onClick={() => updateSettings({ readerMode: mode === 'webtoon' ? 'paged' : 'webtoon' })}>
          <Icon name={mode === 'webtoon' ? 'paged' : 'webtoon'} />
        </button>
      </header>

      <footer className={`reader__bottom${ui ? '' : ' is-hidden'}`}>
        <button type="button" className="icon-btn icon-btn--glass" aria-label="Previous chapter" disabled={!prev} onClick={() => prev && goChapter(prev)}>
          <Icon name="prev" />
        </button>
        <label className="reader__slider">
          <input type="range" min={1} max={Math.max(pages, 1)} value={Math.min(page, Math.max(pages, 1))} disabled={!pages} aria-label="Page"
            onChange={(e) => { const n = Number(e.target.value); setPage(n); scrollToPage(n) }} />
          <span>{pages ? `${Math.min(page, pages)} / ${pages}` : '–'}</span>
        </label>
        <button type="button" className="icon-btn icon-btn--glass" aria-label="Next chapter" disabled={!next} onClick={() => next && goChapter(next)}>
          <Icon name="next" />
        </button>
      </footer>
      <span className="reader__line" style={{ width: `${pages ? (Math.min(page, pages) / pages) * 100 : 0}%` }} aria-hidden="true" />
    </div>
  )
}
