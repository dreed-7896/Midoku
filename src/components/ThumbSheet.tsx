import { useEffect, useState } from 'react'
import { useStore } from '../data/store'
import { chapterPages, partPages, pictureThumb, resetThumbs, thumbPage } from '../data/thumbs'
import type { Chapter } from '../data/types'
import { ChapterThumb, LazyImage } from './Art'
import { Sheet } from './Chrome'
import { Icon } from './Icon'
import { Empty, Loading } from './Status'

/**
 * Edit one chapter's thumbnail, like native Midoku's chapter editor: pick a page of the chapter, or a picture
 * from the device, or go back to the default (the chapter's first page).
 */
export function ThumbSheet({ entryId, chapter, onClose }: { entryId: string; chapter: Chapter; onClose: () => void }) {
  const store = useStore()
  const [pages, setPages] = useState<string[] | null>(null)
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState(false)
  const remote = !!chapter.remoteId
  const current = chapter.thumb?.startsWith('data:') ? 0 : thumbPage(chapter)

  useEffect(() => {
    if (!remote) return
    chapterPages(chapter).then(setPages).catch((e: Error) => setError(e.message))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chapter.remoteId])

  const set = (thumb: string | undefined, message: string) => {
    store.editChapters(entryId, new Set([chapter.id]), { thumb })
    store.toast(message)
    onClose()
  }
  const pick = async (file?: File) => {
    if (!file) return
    setBusy(true)
    try { set(await pictureThumb(file), `Thumbnail of ${chapter.label} changed`) } catch (e) { store.toast((e as Error).message) } finally { setBusy(false) }
  }
  const reset = async () => {
    await resetThumbs([chapter])
    set(undefined, `Thumbnail of ${chapter.label} reset`)
  }
  const shown = pages ? partPages(chapter, pages.length) : []

  return (
    <Sheet open tall title={`Thumbnail · ${chapter.label}`} onClose={onClose}>
      <div className="edit-cover">
        <div className="edit-cover__img thumb-preview"><ChapterThumb chapter={chapter} /></div>
        <div className="edit-cover__actions">
          <label className="btn btn--ghost btn--sm">
            <Icon name="image" size={15} />{busy ? 'Reading…' : 'Choose picture'}
            <input type="file" accept="image/*" hidden onChange={(e) => void pick(e.target.files?.[0])} />
          </label>
          {chapter.thumb && <button type="button" className="btn btn--ghost btn--sm" onClick={() => void reset()}><Icon name="undo" size={15} />Reset</button>}
        </div>
      </div>
      {remote && <>
        <div className="label">Or use a page</div>
        {error && <Empty tone="error" icon="alert" title="Couldn't load the pages" detail={error} />}
        {!pages && !error && <Loading label="Loading pages" shape="page" count={6} />}
        <div className="splitter__grid">
          {shown.map((n) => (
            <button key={n} type="button" className={`splitter__page${n === current ? ' is-start' : ''}`} aria-pressed={n === current} aria-label={`Use page ${n}`}
              onClick={() => set(n === (chapter.range?.[0] ?? 1) ? undefined : `page:${n}`, `Thumbnail of ${chapter.label} is page ${n}`)}>
              <div className="splitter__img"><LazyImage src={pages![n - 1]} fromDevice={chapter.downloaded} placeholder={n} /></div>
              <span className="splitter__num">{n}</span>
            </button>
          ))}
        </div>
      </>}
      {!remote && <p className="hint">Sample chapters have no pages to pick from.</p>}
    </Sheet>
  )
}
