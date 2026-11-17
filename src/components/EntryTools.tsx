import { useMemo, useState } from 'react'
import { statusOf, suggestedChapterName, totalCount, useStore } from '../data/store'
import { STATUS_LABEL, type Chapter, type CustomDetails, type Entry } from '../data/types'
import { Cover } from './Art'
import { Sheet } from './Chrome'
import { Icon } from './Icon'
import { Empty } from './Status'

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

/** Title, author, description and cover, kept over what the source says; reading status follows progress. */
export function EditDetailsSheet({ entry, onClose }: { entry: Entry; onClose: () => void }) {
  const store = useStore()
  const o = entry.original ?? { title: entry.title, author: entry.author, description: entry.description, coverUrl: entry.coverUrl }
  const c = entry.custom ?? {}
  const own = entry.sources.length === 0
  const [title, setTitle] = useState(c.title ?? (own ? entry.title : ''))
  const [author, setAuthor] = useState(c.author ?? '')
  const [description, setDescription] = useState(c.description ?? '')
  const [cover, setCover] = useState(c.cover ?? '')
  const [busy, setBusy] = useState(false)
  const status = statusOf(entry)

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

      <div className="label">Reading status · {STATUS_LABEL[status]}</div>
      <div className="segmented">
        <button type="button" disabled={status === 'completed'} onClick={() => { void store.markEntry(entry.id, true); onClose() }}>Mark all read</button>
        <button type="button" disabled={status === 'unread'} onClick={() => { void store.markEntry(entry.id, false); onClose() }}>Mark all unread</button>
      </div>
      <p className="hint">Unread, Reading and Completed follow your reading progress.</p>

      <div className="sheet__actions">
        <button type="button" className="btn btn--ghost" onClick={onClose}>Cancel</button>
        <button type="button" className="btn btn--accent" onClick={save} disabled={busy}>Save</button>
      </div>
    </Sheet>
  )
}

/**
 * Midoku's "Add to entry": search the library, pick an entry, and the chapters are added to it. The name
 * starts as the entry's next chapter ("Chapter 13"); its number places the chapter, the rest follow.
 */
export function AddToEntrySheet({ entry, chapterIds, onClose }: { entry: Entry; chapterIds: Set<string>; onClose: () => void }) {
  const store = useStore()
  const [query, setQuery] = useState('')
  const [target, setTarget] = useState<string>()
  const [name, setName] = useState('')
  const count = chapterIds.size
  const q = query.trim().toLowerCase()
  const list = useMemo(() => store.entries
    .filter((e) => e.inLibrary && e.id !== entry.id && (!q || e.title.toLowerCase().includes(q)))
    .sort((a, b) => a.title.localeCompare(b.title)), [store.entries, entry.id, q])
  const picked = target ? store.entry(target) : undefined
  const pick = (e: Entry) => { setTarget(e.id); setName(suggestedChapterName(e)) }
  const add = () => {
    if (!picked) return
    store.addToEntry(entry.id, chapterIds, picked.id, name)
    onClose()
  }
  return (
    <Sheet open tall title="Add to entry" onClose={onClose}>
      <div className="label label--flush">{count === 1 ? 'Chapter name' : `First of ${count} chapters`}</div>
      <input className="form-input" value={name} onChange={(e) => setName(e.target.value)} placeholder={picked ? suggestedChapterName(picked) : 'Pick an entry first'} aria-label="Chapter name" />
      {count > 1 && <p className="hint">The others are numbered after it.</p>}
      <div className="label">Library entry</div>
      <label className="field">
        <Icon name="search" size={18} />
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search library" aria-label="Search library" />
      </label>
      {!list.length && <Empty compact icon="library" title={q ? 'No entries found' : 'Library empty'} detail={q ? 'Try another search.' : 'Save an entry to the Library first.'} />}
      <div className="check-list pad-t-sm">
        {list.map((e) => {
          const parent = e.parentId ? store.entry(e.parentId) : undefined
          return (
            <button key={e.id} type="button" className="check-row" onClick={() => pick(e)}>
              <span className="check-row__name check-row__name--stack">
                <strong>{e.title}</strong>
                <span className="card-meta">{parent ? `in ${parent.title} · ` : ''}{totalCount(e)} chapters · {STATUS_LABEL[statusOf(e)]}</span>
              </span>
              {target === e.id && <span className="pick-dot"><Icon name="check" size={14} stroke={2.6} /></span>}
            </button>
          )
        })}
      </div>
      <div className="sheet__actions">
        <button type="button" className="btn btn--ghost" onClick={onClose}>Cancel</button>
        <button type="button" className="btn btn--accent" onClick={add} disabled={!picked}><Icon name="plus" size={16} />{count === 1 ? 'Add chapter' : `Add ${count} chapters`}</button>
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
