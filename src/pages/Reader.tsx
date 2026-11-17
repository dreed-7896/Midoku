import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { PageThumb, RemoteImage } from '../components/Art'
import { Sheet } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { Empty, Loading } from '../components/Status'
import { useNav } from '../components/Nav'
import { updateSettings, useSettings } from '../data/settings'
import { useStore, visibleChapters } from '../data/store'
import { chapterKey, getSaved } from '../data/downloads'
import { shownPages } from '../data/library'
import { getPages } from '../data/suwayomi'
import { READER_LABEL, type Chapter, type CoverArt, type ReaderMode } from '../data/types'

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
  const { readerMode } = useSettings()
  const entry = store.entry(entryId)
  // A title's own mode wins over the device default. Right to left is paged, turned the other way.
  const titleMode = entry?.custom?.reader
  const chosen: ReaderMode = titleMode ?? readerMode
  const mode = chosen === 'webtoon' ? 'webtoon' : 'paged'
  const [modes, setModes] = useState(false)
  const [zoomed, setZoomed] = useState(false)
  const tapTimer = useRef<ReturnType<typeof setTimeout>>()
  // Webtoon zoom: the strip is scaled inside a sizer as big as the scaled strip, so the scroller pans it natively.
  const sizer = useRef<HTMLDivElement>(null)
  const strip = useRef<HTMLDivElement>(null)
  const wtScale = useRef(1)
  const pinch = useRef<{ d0: number; s0: number } | null>(null)
  // Parts of split chapters and inserted chapters are found among the shown chapters.
  const chapter = entry ? visibleChapters(entry).find((c) => c.id === chapterId) ?? entry.chapters.find((c) => c.id === chapterId) : undefined
  const [versions, setVersions] = useState(false)
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
    // A downloaded chapter reads from the device; others ask the server for their pages.
    const saved = chapter.sourceUrl ? getSaved(chapterKey(chapter.sourceId, chapter.sourceUrl)) : undefined
    ;(saved ? Promise.resolve(saved.pages) : getPages(chapter.remoteId))
      .then((list) => {
        if (!alive) return
        // A part shows only its pages; the whole chapter's page count is kept on the whole chapter.
        const whole = chapter.physicalId ?? chapter.id
        const known = entry?.chapters.find((c) => c.id === whole)?.pages ?? chapter.pages
        if (known !== list.length) store.editChapters(entryId, new Set([whole]), { pages: list.length })
        setUrls(chapter.range ? shownPages(chapter, list.length).map((n) => list[n - 1]) : list)
      })
      .catch((e: Error) => alive && setPagesError(e.message))
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chapterId, loadTry, chapter?.remoteId])
  const pages = isRemote ? urls?.length ?? 0 : chapter?.pages ?? 0
  const fromDevice = !!chapter?.downloaded

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
        const z = wtScale.current
        if (before !== undefined && before !== after && (el.offsetTop + before) * z <= root.scrollTop) root.scrollTop += (after - before) * z
      }
    })
    root.querySelectorAll('[data-page]').forEach((el) => ro.observe(el))
    return () => ro.disconnect()
  }, [chapterId, mode, pages])

  // The sizer follows the strip as pages load and change height.
  useEffect(() => {
    const box = strip.current, size = sizer.current
    if (!box || !size || mode !== 'webtoon') return
    const ro = new ResizeObserver(() => { if (wtScale.current > 1) size.style.height = `${box.offsetHeight * wtScale.current}px` })
    ro.observe(box)
    return () => ro.disconnect()
  }, [mode, chapterId, pages])
  // A new chapter or mode starts unzoomed.
  useEffect(() => { wtScale.current = 1; setZoomed(false) }, [chapterId, chosen])

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
  }, [chapterId, chosen, pages])

  // The page crossing the middle of the screen is the current page.
  useEffect(() => {
    const root = scroller.current
    if (!root) return
    const io = new IntersectionObserver((items) => {
      for (const it of items) if (it.isIntersecting) setPage(Number((it.target as HTMLElement).dataset.page))
    }, { root, rootMargin: mode === 'webtoon' ? '-50% 0px -50% 0px' : '0px -50% 0px -50%' })
    root.querySelectorAll('[data-page]').forEach((el) => io.observe(el))
    // Reaching the "Finished" block counts as the last page, even after a fast fling past it.
    const end = new IntersectionObserver((items) => { if (items.some((it) => it.isIntersecting) && pages) setPage(pages) }, { root, threshold: 0.5 })
    const endEl = root.querySelector('.reader__end')
    if (endEl) end.observe(endEl)
    return () => { io.disconnect(); end.disconnect() }
  }, [chapterId, chosen, pages, urls])

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
        <Empty icon="book" title="Chapter not available" detail="It may have been removed from the source, or the title isn't loaded yet." action={{ label: 'Go back', onClick: () => nav.back('/library') }} />
      </div>
    )
  }

  const close = () => nav.back(`/entry/${entry.id}`)
  // Previous chapter slides in from the left like going back; next comes from the right.
  const goChapter = (c: Chapter) =>
    nav.go(`/read/${entry.id}/${c.id}`, { replace: true, direction: c.number < chapter.number ? 'back' : 'forward' })

  /** Scales the webtoon strip around a point of the screen (fx, fy from the scroller's top left). */
  const zoomStrip = (target: number, fx: number, fy: number) => {
    const root = scroller.current, box = strip.current, size = sizer.current
    if (!root || !box || !size) return
    const old = wtScale.current
    const s = Math.min(4, Math.max(1, target))
    const cx = (root.scrollLeft + fx) / old, cy = (root.scrollTop + fy) / old
    wtScale.current = s
    if (s <= 1.01) {
      wtScale.current = 1
      box.style.transform = ''; box.style.width = ''; size.style.width = ''; size.style.height = ''
    } else {
      const w = root.clientWidth
      box.style.width = `${w}px`
      box.style.transform = `scale(${s})`
      size.style.width = `${w * s}px`
      size.style.height = `${box.offsetHeight * s}px`
    }
    root.scrollLeft = cx * wtScale.current - fx
    root.scrollTop = cy * wtScale.current - fy
    setZoomed(wtScale.current > 1)
  }
  const rel = (x: number, y: number) => {
    const r = scroller.current!.getBoundingClientRect()
    return { fx: x - r.left, fy: y - r.top, w: r.width }
  }
  const onWtTouchStart = (e: React.TouchEvent) => {
    if (e.touches.length !== 2) return
    const [a, b] = [e.touches[0], e.touches[1]]
    pinch.current = { d0: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), s0: wtScale.current }
  }
  const onWtTouchMove = (e: React.TouchEvent) => {
    const p = pinch.current
    if (!p || e.touches.length !== 2) return
    const [a, b] = [e.touches[0], e.touches[1]]
    const { fx, fy } = rel((a.clientX + b.clientX) / 2, (a.clientY + b.clientY) / 2)
    zoomStrip(p.s0 * (Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY) / p.d0), fx, fy)
  }
  const onWtTouchEnd = (e: React.TouchEvent) => { if (e.touches.length < 2) pinch.current = null }

  /**
   * Taps. Paged: the left and right edges turn the page (reversed for right to left); elsewhere a tap shows or
   * hides the controls. A double tap zooms, so the controls wait a moment for a second tap.
   */
  const onTap = (e: React.MouseEvent) => {
    const { fx, fy, w } = rel(e.clientX, e.clientY)
    if (mode === 'paged' && !zoomed && (fx < w * 0.3 || fx > w * 0.7)) {
      const forward = (fx > w * 0.7) !== (chosen === 'rtl')
      if (tapTimer.current) { clearTimeout(tapTimer.current); tapTimer.current = undefined }
      turn(forward ? 1 : -1)
      return
    }
    if (tapTimer.current) {
      clearTimeout(tapTimer.current); tapTimer.current = undefined
      // Paged pages handle their own double tap (Zoomable); the webtoon strip zooms here.
      if (mode === 'webtoon') zoomStrip(wtScale.current > 1 ? 1 : 2.5, fx, fy)
      return
    }
    tapTimer.current = setTimeout(() => { tapTimer.current = undefined; setUi((v) => !v) }, 260)
  }
  const turn = (by: number) => {
    const n = page + by
    if (n < 1) return
    if (n > pages) { scroller.current?.querySelector('.reader__end')?.scrollIntoView({ behavior: 'smooth', inline: 'start' }); return }
    setPage(n)
    scrollToPage(n, 'smooth')
  }
  const wrapStrip = (content: React.ReactNode) => mode === 'webtoon'
    ? <div ref={sizer} className="wt-sizer"><div ref={strip} className="wt-strip">{content}</div></div>
    : content

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
    <div className={`reader reader--${mode}${chosen === 'rtl' ? ' reader--rtl' : ''}${zoomed ? ' is-zoomed' : ''}`}>
      <div ref={scroller} className="reader__scroll" onScroll={onScroll} onClick={onTap}
        onTouchStart={mode === 'webtoon' ? onWtTouchStart : undefined} onTouchMove={mode === 'webtoon' ? onWtTouchMove : undefined}
        onTouchEnd={mode === 'webtoon' ? onWtTouchEnd : undefined} onTouchCancel={mode === 'webtoon' ? onWtTouchEnd : undefined}>
        {isRemote && !urls && (
          <div className="reader__loading" onClick={(e) => e.stopPropagation()}>
            {pagesError
              ? <Empty icon="alert" tone="error" title="Couldn't load pages" detail={pagesError} action={{ label: 'Try again', onClick: () => setLoadTry((n) => n + 1) }} />
              : <Loading label={`Loading ${chapter.label}`} shape="page" />}
          </div>
        )}
        {wrapStrip(<>
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
                {near && <RemoteImage src={urls[n - 1]} alt={`Page ${n}`} className="wt-img" onLoad={onLoad} fromDevice={fromDevice} />}
              </div>
            ) : (
              <div key={n} className="pg-page" data-page={n}>{near && <Zoomable active={n === page} onZoom={setZoomed}><RemoteImage src={urls[n - 1]} alt={`Page ${n}`} className="pg-img" fromDevice={fromDevice} /></Zoomable>}</div>
            )
          }
          return mode === 'webtoon' ? (
            <div key={n} className="wt-page" data-page={n} style={!near && known ? { height: known, aspectRatio: 'auto' } : undefined}>
              {near && <WebtoonContent n={n} art={entry.art} />}
            </div>
          ) : (
            <div key={n} className="pg-page" data-page={n}>{near && <Zoomable active={n === page} onZoom={setZoomed}><PagedContent n={n} /></Zoomable>}</div>
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
            <Empty compact icon="check" tone="done" title="All caught up" detail={`That's the latest chapter of ${entry.title}.`} />
          )}
          <button type="button" className="btn btn--ghost" onClick={close}>Back to {entry.title}</button>
        </div>}
        </>)}
      </div>

      <header className={`reader__top${ui ? '' : ' is-hidden'}`}>
        <button type="button" className="icon-btn icon-btn--glass" aria-label="Close reader" onClick={close}><Icon name="back" /></button>
        <div className="reader__titles">
          <span className="reader__entry">{entry.title}</span>
          {(chapter.alts?.length ?? 0) > 1 ? (
            <button type="button" className="reader__chapter reader__version" onClick={(e) => { e.stopPropagation(); setVersions(true) }}>
              {chapter.label} · {chapter.alts!.find((a) => a.remoteId === chapter.remoteId)?.name ?? chapter.title}<Icon name="chevronDown" size={14} />
            </button>
          ) : <span className="reader__chapter">{chapter.label} · {chapter.part ?? chapter.title}</span>}
        </div>
        <button type="button" className="icon-btn icon-btn--glass" aria-label={`Reading mode: ${READER_LABEL[chosen]}`} onClick={() => setModes(true)}>
          <Icon name={mode === 'webtoon' ? 'webtoon' : 'paged'} />
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
      <Sheet open={modes} title="Reading mode" onClose={() => setModes(false)}>
        <div className="label label--flush">For {entry.title}</div>
        <div className="check-list">
          <button type="button" className="check-row" onClick={() => { store.setReaderMode(entry.id, undefined); setModes(false) }}>
            <span className="check-row__name">Default<span className="card-meta"> · {READER_LABEL[readerMode]}</span></span>
            {!titleMode && <Icon name="check" size={18} />}
          </button>
          {(Object.keys(READER_LABEL) as ReaderMode[]).map((m) => (
            <button key={m} type="button" className="check-row" onClick={() => { store.setReaderMode(entry.id, m); setModes(false) }}>
              <span className="check-row__name">{READER_LABEL[m]}</span>
              {titleMode === m && <Icon name="check" size={18} />}
            </button>
          ))}
        </div>
        <div className="label">Default for other titles</div>
        <div className="segmented">
          {(Object.keys(READER_LABEL) as ReaderMode[]).map((m) => (
            <button key={m} type="button" className={readerMode === m ? 'is-on' : ''} onClick={() => updateSettings({ readerMode: m })}>{READER_LABEL[m]}</button>
          ))}
        </div>
        <p className="hint">Paged pages zoom with a pinch or a double tap.</p>
      </Sheet>
      <Sheet open={versions} title={`${chapter.label} · versions`} onClose={() => setVersions(false)}>
        <div className="check-list">
          {chapter.alts?.map((a, i) => (
            <button key={`${a.sourceId}-${a.url}`} type="button" className="check-row" onClick={() => { setVersions(false); store.chooseVersion(entry.id, chapter.id, i) }}>
              <span className="check-row__name">{a.name}<span className="card-meta"> · {a.title}</span></span>
              {a.remoteId === chapter.remoteId && <Icon name="check" size={18} />}
            </button>
          ))}
        </div>
      </Sheet>
      <span className="reader__line" style={{ width: `${pages ? (Math.min(page, pages) / pages) * 100 : 0}%` }} aria-hidden="true" />
    </div>
  )
}

/**
 * Pinch and double-tap zoom for a paged page. While zoomed, one finger pans the page and the pager stops
 * turning pages; zooming back out (or leaving the page) hands swiping back to the pager.
 */
function Zoomable({ active, onZoom, children }: { active: boolean; onZoom: (zoomed: boolean) => void; children: React.ReactNode }) {
  const box = useRef<HTMLDivElement>(null)
  const view = useRef({ s: 1, x: 0, y: 0 })
  const g = useRef<{ d0: number; s0: number; mx: number; my: number; x0: number; y0: number; px?: number; py?: number; moved: boolean; t: number } | null>(null)
  const lastTap = useRef(0)
  const [isZoomed, setIsZoomed] = useState(false)
  const zoomedRef = useRef(false)

  const apply = (s: number, x: number, y: number, animate = false) => {
    const el = box.current
    if (!el) return
    const w = el.clientWidth, h = el.clientHeight
    s = Math.min(4, Math.max(1, s))
    const mx = ((s - 1) * w) / 2, my = ((s - 1) * h) / 2
    x = Math.min(mx, Math.max(-mx, x))
    y = Math.min(my, Math.max(-my, y))
    view.current = { s, x, y }
    const inner = el.firstElementChild as HTMLElement | null
    if (inner) {
      inner.style.transition = animate ? 'transform 0.2s ease-out' : 'none'
      inner.style.transform = s === 1 ? '' : `translate(${x}px, ${y}px) scale(${s})`
    }
    const z = s > 1.01
    if (z !== zoomedRef.current) { zoomedRef.current = z; setIsZoomed(z); onZoom(z) }
  }

  // Leaving the page resets it.
  useEffect(() => { if (!active && view.current.s !== 1) apply(1, 0, 0) })
  useEffect(() => () => { if (view.current.s > 1.01) onZoom(false) }, [onZoom])

  const center = (el: HTMLElement) => { const r = el.getBoundingClientRect(); return { cx: r.left + r.width / 2, cy: r.top + r.height / 2 } }
  const onTouchStart = (e: React.TouchEvent) => {
    const el = box.current
    if (!el) return
    const { s, x, y } = view.current
    if (e.touches.length === 2) {
      const [a, b] = [e.touches[0], e.touches[1]]
      const { cx, cy } = center(el)
      g.current = { d0: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), s0: s, mx: (a.clientX + b.clientX) / 2 - cx, my: (a.clientY + b.clientY) / 2 - cy, x0: x, y0: y, moved: true, t: Date.now() }
      onZoom(true)
    } else if (e.touches.length === 1) {
      g.current = { d0: 0, s0: s, mx: 0, my: 0, x0: x, y0: y, px: e.touches[0].clientX, py: e.touches[0].clientY, moved: false, t: Date.now() }
    }
  }
  const onTouchMove = (e: React.TouchEvent) => {
    const st = g.current
    const el = box.current
    if (!st || !el) return
    if (e.touches.length === 2 && st.d0) {
      const [a, b] = [e.touches[0], e.touches[1]]
      const { cx, cy } = center(el)
      const s = Math.min(4, Math.max(1, st.s0 * (Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY) / st.d0)))
      const mx = (a.clientX + b.clientX) / 2 - cx, my = (a.clientY + b.clientY) / 2 - cy
      // Keep the point under the fingers in place while scaling, and follow the fingers as they move.
      apply(s, mx - (st.mx - st.x0) * (s / st.s0), my - (st.my - st.y0) * (s / st.s0))
    } else if (e.touches.length === 1 && st.px !== undefined) {
      const dx = e.touches[0].clientX - st.px, dy = e.touches[0].clientY - st.py!
      if (Math.abs(dx) + Math.abs(dy) > 8) st.moved = true
      if (view.current.s > 1.01) apply(view.current.s, st.x0 + dx, st.y0 + dy)
    }
  }
  const onTouchEnd = (e: React.TouchEvent) => {
    const st = g.current
    if (e.touches.length === 1 && view.current.s > 1.01) {
      // One finger left after a pinch: carry on panning from here.
      const { x, y } = view.current
      g.current = { d0: 0, s0: view.current.s, mx: 0, my: 0, x0: x, y0: y, px: e.touches[0].clientX, py: e.touches[0].clientY, moved: true, t: Date.now() }
      return
    }
    if (e.touches.length) return
    g.current = null
    if (view.current.s < 1.05) apply(1, 0, 0, true)
    if (!st || st.moved || st.d0 || Date.now() - st.t > 250) return
    const now = Date.now()
    // The edges turn pages; only the middle zooms.
    const r = box.current!.getBoundingClientRect()
    if (st.px! < r.left + r.width * 0.3 || st.px! > r.left + r.width * 0.7) { lastTap.current = 0; return }
    if (now - lastTap.current < 300) {
      lastTap.current = 0
      const el = box.current!
      const { cx, cy } = center(el)
      if (view.current.s > 1.01) apply(1, 0, 0, true)
      else { const s = 2.5, px = st.px! - cx, py = st.py! - cy; apply(s, px * (1 - s), py * (1 - s), true) }
    } else lastTap.current = now
  }

  return (
    <div ref={box} className={`zoom${isZoomed ? ' is-zoomed' : ''}`} onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd} onTouchCancel={onTouchEnd}>
      <div className="zoom__inner">{children}</div>
    </div>
  )
}
