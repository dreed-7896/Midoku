import { useEffect, useMemo, useState } from 'react'
import { chapterKey, getSaved } from '../data/downloads'
import { useStore } from '../data/store'
import { chapterPages } from '../data/thumbs'
import type { Chapter, PageLayout } from '../data/types'
import { LazyImage } from './Art'
import { Sheet } from './Chrome'
import { Icon } from './Icon'
import { Empty, Loading } from './Status'

type Mode = 'split' | 'skip'

/**
 * Shows every page of a chapter as a thumbnail. Page 1 starts part 1; tapping a page makes it the start
 * of the next part (tap again to undo). In "Leave out" mode, tapping a page hides it from reading.
 */
export function PageSplitter({ entryId, chapter, layout, onClose }: { entryId: string; chapter: Chapter; layout?: PageLayout; onClose: () => void }) {
  const store = useStore()
  const saved = chapter.sourceUrl ? getSaved(chapterKey(chapter.sourceId, chapter.sourceUrl)) : undefined
  const [urls, setUrls] = useState<string[] | null>(chapter.remoteId ? null : Array.from({ length: chapter.pages }, () => ''))
  const [error, setError] = useState<string>()
  const [mode, setMode] = useState<Mode>('split')
  const [breaks, setBreaks] = useState(() => new Set(layout?.breaks ?? []))
  const [skip, setSkip] = useState(() => new Set(layout?.skip ?? []))

  useEffect(() => {
    if (!chapter.remoteId) return
    chapterPages(chapter)
      .then((list) => {
        setUrls(list)
        if (list.length !== chapter.pages) store.editChapters(entryId, new Set([chapter.id]), { pages: list.length })
      })
      .catch((e: Error) => setError(e.message))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chapter.remoteId])

  const total = urls?.length ?? 0
  const starts = useMemo(() => [1, ...[...breaks].filter((b) => b > 1 && b <= total).sort((a, b) => a - b)], [breaks, total])
  const partOf = (n: number) => starts.filter((s) => s <= n).length
  const counts = starts.map((s, i) => {
    let k = 0
    for (let n = s; n < (starts[i + 1] ?? total + 1); n++) if (!skip.has(n)) k++
    return k
  })

  const toggle = (set: Set<number>, n: number) => { const next = new Set(set); if (next.has(n)) next.delete(n); else next.add(n); return next }
  const tap = (n: number) => {
    navigator.vibrate?.(5)
    if (mode === 'skip') setSkip((s) => toggle(s, n))
    else if (n > 1) setBreaks((b) => toggle(b, n))
  }

  /** Breaks that would leave a part with no pages are dropped (the empty part joins its neighbour). */
  const cleanBreaks = () => {
    const has = (a: number, b: number) => { for (let n = a; n <= b; n++) if (!skip.has(n)) return true; return false }
    const kept: number[] = []
    let from = 1
    for (const b of starts.slice(1)) if (has(from, b - 1)) { kept.push(b); from = b }
    if (kept.length && !has(from, total)) kept.pop()
    return kept
  }
  const shownCount = counts.reduce((a, b) => a + b, 0)
  const save = () => {
    store.splitChapter(entryId, chapter.id, { breaks: cleanBreaks(), skip: [...skip].filter((n) => n <= total) })
    onClose()
  }

  return (
    <Sheet open tall title={`Pages · ${chapter.label}`} onClose={onClose}>
      <p className="hint">{mode === 'split' ? 'Page 1 starts part 1. Tap a page to start the next part there; tap it again to undo.' : 'Tap pages to leave them out (credits, ads). Tap again to bring one back.'}</p>

      {error && <Empty tone="error" icon="alert" title="Couldn't load the pages" detail={error} />}
      {!urls && !error && <Loading label="Loading pages" shape="page" count={6} />}
      {urls && !urls.length && <Empty icon="book" title="No pages" detail="The source returned no pages for this chapter." />}

      <div className="splitter__grid">
        {urls?.map((u, i) => {
          const n = i + 1
          const start = starts.includes(n)
          const out = skip.has(n)
          const part = partOf(n)
          return (
            <button key={n} type="button" className={`splitter__page${start ? ' is-start' : ''}${out ? ' is-out' : ''}${part % 2 ? '' : ' is-even'}`}
              aria-pressed={mode === 'skip' ? out : start} aria-label={`Page ${n}${start ? `, starts part ${part}` : ''}${out ? ', left out' : ''}`} onClick={() => tap(n)}>
              <div className="splitter__img">
                <LazyImage src={u} fromDevice={!!saved} placeholder={(n * 7) % 4} />
                {out && <span className="splitter__out"><Icon name="x" size={22} stroke={2.6} /></span>}
              </div>
              {start && starts.length > 1 && <span className="splitter__part">Part {part}</span>}
              <span className="splitter__num">{n}</span>
            </button>
          )
        })}
      </div>

      {urls && urls.length > 0 && (
        <div className="splitter__bar">
          <div className="segmented splitter__mode">
            <button type="button" className={mode === 'split' ? 'is-on' : ''} onClick={() => setMode('split')}>Start parts</button>
            <button type="button" className={mode === 'skip' ? 'is-on' : ''} onClick={() => setMode('skip')}>Leave out pages</button>
          </div>
          <div className="splitter__row">
            <div className="splitter__sum">
              <strong>{starts.length > 1 ? `${starts.length} parts` : 'One part'}{skip.size ? ` · ${skip.size} left out` : ''}</strong>
              <small>{starts.length > 1 ? `${counts.join(' · ')} pages` : `${shownCount} of ${total} pages`}</small>
            </div>
            <button type="button" className="btn btn--ghost" disabled={!breaks.size && !skip.size} onClick={() => { setBreaks(new Set()); setSkip(new Set()) }}>Reset</button>
            <button type="button" className="btn btn--accent" disabled={!shownCount} onClick={save}><Icon name="check" size={16} />Save</button>
          </div>
        </div>
      )}
    </Sheet>
  )
}
