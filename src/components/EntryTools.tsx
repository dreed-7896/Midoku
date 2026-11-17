import { useMemo, useState } from 'react'
import { statusOf, useStore, visibleChapters } from '../data/store'
import { STATUS_LABEL, type Chapter, type CustomDetails, type Entry, type ManualStatus } from '../data/types'
import { Cover } from './Art'
import { Sheet } from './Chrome'
import { Icon } from './Icon'
import { Empty } from './Status'

const MANUAL: ManualStatus[] = ['planned', 'onhold', 'dropped']

/** Turns a picked picture into a small JPEG data URL, so it can be kept with the title. */
function shrinkImage(file: File, width = 360): Promise<string> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      const scale = Math.min(1, width / img.naturalWidth)
      const canvas = document.createElement('canvas')
      canvas.width = Math.round(img.naturalWidth * scale)
      canvas.height = Math.round(img.naturalHeight * scale)
      canvas.getContext('2d')!.drawImage(img, 0, 0, canvas.width, canvas.height)
      URL.revokeObjectURL(url)
      resolve(canvas.toDataURL('image/jpeg', 0.82))
    }
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("That picture couldn't be read")) }
    img.src = url
  })
}

/** Title, author, description, cover and reading status, kept over what the source says. */
export function EditDetailsSheet({ entry, onClose }: { entry: Entry; onClose: () => void }) {
  const store = useStore()
  const o = entry.original ?? { title: entry.title, author: entry.author, description: entry.description, coverUrl: entry.coverUrl }
  const c = entry.custom ?? {}
  const own = entry.sources.length === 0
  const [title, setTitle] = useState(c.title ?? (own ? entry.title : ''))
  const [author, setAuthor] = useState(c.author ?? '')
  const [description, setDescription] = useState(c.description ?? '')
  const [cover, setCover] = useState(c.cover ?? '')
  const [status, setStatus] = useState<ManualStatus | undefined>(c.status)
  const [busy, setBusy] = useState(false)
  const auto = statusOf({ ...entry, custom: { ...c, status: undefined } })

  const pick = async (file?: File) => {
    if (!file) return
    setBusy(true)
    try { setCover(await shrinkImage(file)) } catch (e) { store.toast((e as Error).message) } finally { setBusy(false) }
  }
  const save = () => {
    const patch: CustomDetails = {
      title: title.trim() || undefined,
      author: author.trim() || undefined,
      description: description.trim() || undefined,
      cover: cover.trim() || undefined,
      status,
    }
    store.editDetails(entry.id, patch)
    store.toast('Details saved')
    onClose()
  }

  return (
    <Sheet open tall title="Edit details" onClose={onClose}>
      <div className="edit-cover">
        <Cover art={entry.art} title={title || o.title} url={cover || o.coverUrl} className="edit-cover__img" />
        <div className="edit-cover__actions">
          <label className="btn btn--ghost btn--sm">
            <Icon name="plus" size={15} />{busy ? 'Reading…' : 'Choose picture'}
            <input type="file" accept="image/*" hidden onChange={(e) => void pick(e.target.files?.[0])} />
          </label>
          {cover && <button type="button" className="btn btn--ghost btn--sm" onClick={() => setCover('')}><Icon name="undo" size={15} />{own ? 'Remove' : "Source's cover"}</button>}
        </div>
      </div>
      <input className="form-input" value={cover.startsWith('data:') ? '' : cover} onChange={(e) => setCover(e.target.value)}
        placeholder={cover.startsWith('data:') ? 'Picture from this device' : 'Or paste an image address'} aria-label="Cover image address" inputMode="url" />

      <div className="label">Title</div>
      <input className="form-input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder={o.title || 'Title'} aria-label="Title" />
      <div className="label">Author</div>
      <input className="form-input" value={author} onChange={(e) => setAuthor(e.target.value)} placeholder={o.author || 'Author'} aria-label="Author" />
      <div className="label">Description</div>
      <textarea className="form-input form-input--area" value={description} onChange={(e) => setDescription(e.target.value)} placeholder={o.description || 'Description'} aria-label="Description" rows={5} />
      {!own && <p className="hint">Leave a field empty to use the source's.</p>}

      <div className="label">Reading status</div>
      <div className="segmented">
        <button type="button" className={!status ? 'is-on' : ''} onClick={() => setStatus(undefined)}>Auto · {STATUS_LABEL[auto]}</button>
        {MANUAL.map((s) => <button key={s} type="button" className={status === s ? 'is-on' : ''} onClick={() => setStatus(s)}>{STATUS_LABEL[s]}</button>)}
      </div>
      <p className="hint">Auto is Reading until every chapter is read, then Completed.</p>

      <div className="sheet__actions">
        <button type="button" className="btn btn--ghost" onClick={onClose}>Cancel</button>
        <button type="button" className="btn btn--accent" onClick={save} disabled={busy}>Save</button>
      </div>
    </Sheet>
  )
}

type PasteAction = 'add' | 'skip' | 'separate' | 'version' | 'replace'
const ACTION_LABEL: Record<PasteAction, string> = { add: 'Add', skip: 'Skip', separate: 'Separate', version: 'Version', replace: 'Replace' }

/** Reviews copied chapters before pasting: chapters already here can be skipped, kept separately, added as a version or replace the old one. */
export function PasteSheet({ entry, onClose }: { entry: Entry; onClose: () => void }) {
  const store = useStore()
  const [place, setPlace] = useState<'number' | 'end'>('number')
  const shown = useMemo(() => visibleChapters(entry).filter((c) => !c.physicalId), [entry])
  const last = Math.max(0, ...entry.chapters.map((c) => c.number))

  const rows = useMemo(() => store.clipboard.map((copy, i) => {
    const same = entry.chapters.find((c) => c.sourceUrl === copy.chapterUrl && c.sourceId === copy.sourceId)
      ?? entry.chapters.find((c) => c.alts?.some((a) => a.url === copy.chapterUrl && a.sourceId === copy.sourceId))
    const number = place === 'end' ? last + i + 1 : copy.number
    const clash = place === 'number' ? shown.find((c) => Math.abs(c.number - number) < 1e-6 && !c.insertId) : undefined
    return { copy, number, same, clash }
  }), [store.clipboard, entry.chapters, shown, place, last])

  const [choice, setChoice] = useState<Record<number, PasteAction>>({})
  const actionOf = (i: number): PasteAction => choice[i] ?? (rows[i].same ? 'skip' : rows[i].clash ? 'version' : 'add')
  const optionsOf = (i: number): PasteAction[] => (rows[i].same ? ['skip', 'separate'] : rows[i].clash ? ['skip', 'separate', 'version', 'replace'] : ['add', 'skip'])
  const setAll = (a: PasteAction) => setChoice(Object.fromEntries(rows.map((_, i) => [i, optionsOf(i).includes(a) ? a : actionOf(i)])))
  const dupes = rows.filter((r) => r.same || r.clash).length

  const paste = () => {
    const plan = rows.flatMap((r, i) => {
      const a = actionOf(i)
      if (a === 'skip') return []
      // A separate copy of a chapter with the same number goes right after it.
      const number = a === 'separate' ? r.number + 0.001 : r.number
      return [{ copy: r.copy, action: a === 'add' ? 'add' as const : a, number, replaces: a === 'replace' ? r.clash?.id : undefined }]
    })
    if (!plan.length) { store.toast('Nothing to paste'); return }
    store.pasteChapters(entry.id, plan)
    store.clearClipboard()
    onClose()
  }

  return (
    <Sheet open tall title={`Paste ${rows.length} chapter${rows.length === 1 ? '' : 's'}`} onClose={onClose}>
      <p className="hint">From {[...new Set(store.clipboard.map((c) => c.fromTitle))].join(', ')}.</p>
      <div className="label label--flush">Place them</div>
      <div className="segmented">
        <button type="button" className={place === 'number' ? 'is-on' : ''} onClick={() => setPlace('number')}>By chapter number</button>
        <button type="button" className={place === 'end' ? 'is-on' : ''} onClick={() => setPlace('end')}>After the last chapter</button>
      </div>
      {dupes > 0 && <>
        <div className="label">{dupes} already here · set all to</div>
        <div className="chips wrap">
          {(['skip', 'separate', 'version', 'replace'] as PasteAction[]).map((a) => <button key={a} type="button" className="chip" onClick={() => setAll(a)}>{ACTION_LABEL[a]}</button>)}
        </div>
      </>}
      <div className="check-list pad-t">
        {rows.map((r, i) => (
          <div key={`${r.copy.sourceId}-${r.copy.chapterUrl}`} className="paste-row">
            <span className="check-row__name check-row__name--stack">
              <strong>{r.copy.label}</strong>
              <span className="card-meta">{r.same ? 'Already in this title' : r.clash ? `Same number as ${r.clash.label}` : place === 'end' ? `As chapter ${r.number}` : 'New here'}</span>
            </span>
            <div className="segmented segmented--sm">
              {optionsOf(i).map((a) => <button key={a} type="button" className={actionOf(i) === a ? 'is-on' : ''} onClick={() => setChoice((c) => ({ ...c, [i]: a }))}>{ACTION_LABEL[a]}</button>)}
            </div>
          </div>
        ))}
      </div>
      <p className="hint pad-t-sm">Version adds it as another way to read that chapter. Replace hides the old one; it can be restored.</p>
      <div className="sheet__actions">
        <button type="button" className="btn btn--ghost" onClick={() => { store.clearClipboard(); onClose() }}>Discard copied</button>
        <button type="button" className="btn btn--accent" onClick={paste}>Paste</button>
      </div>
    </Sheet>
  )
}

/** Picks where a chapter goes in the reading order. */
export function MoveSheet({ entry, chapter, onClose }: { entry: Entry; chapter: Chapter; onClose: () => void }) {
  const store = useStore()
  const moving = chapter.physicalId ?? chapter.id
  const list = entry.chapters.filter((c) => !c.removed && c.id !== moving).sort((a, b) => a.number - b.number)
  const move = (after: string | null) => { store.moveChapter(entry.id, moving, after); onClose() }
  return (
    <Sheet open tall title={`Move ${chapter.label.split(' · ')[0]}`} onClose={onClose}>
      <p className="hint">Pick the chapter it should come after.</p>
      {!list.length && <Empty compact icon="book" title="No other chapters" />}
      <div className="check-list">
        <button type="button" className="check-row" onClick={() => move(null)}>
          <span className="check-row__name"><strong>At the start</strong></span><Icon name="arrowRight" size={18} />
        </button>
        {list.map((c) => (
          <button key={c.id} type="button" className="check-row" onClick={() => move(c.id)}>
            <span className="check-row__name check-row__name--stack"><strong>After {c.label}</strong><span className="card-meta">{c.insertedFrom ? `from ${c.insertedFrom}` : c.title}</span></span>
            {c.order != null && <span className="tag">Moved</span>}
          </button>
        ))}
      </div>
    </Sheet>
  )
}
