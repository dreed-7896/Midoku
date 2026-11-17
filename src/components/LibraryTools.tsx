import { useMemo, useState } from 'react'
import { totalCount, useStore } from '../data/store'
import type { Entry } from '../data/types'
import { Cover } from './Art'
import { Sheet } from './Chrome'
import { Icon } from './Icon'
import { useNav } from './Nav'
import { Empty } from './Status'

/**
 * Groups the picked titles into a new title. Nested keeps them as titles inside a series; merged puts
 * all their chapters into one title, one after another (progress, sources and bookmarks come along).
 */
export function GroupSheet({ ids, initialMode = 'nest', onClose, onDone }: { ids: string[]; initialMode?: 'nest' | 'merge'; onClose: () => void; onDone?: () => void }) {
  const store = useStore()
  const nav = useNav()
  const [order, setOrder] = useState(ids)
  const [mode, setMode] = useState<'nest' | 'merge'>(initialMode)
  const [inherit, setInherit] = useState(ids[0])
  const [title, setTitle] = useState('')
  const [renumber, setRenumber] = useState(false)
  const [busy, setBusy] = useState(false)
  const list = order.map((id) => store.entry(id)).filter((e): e is Entry => !!e)
  const from = list.find((e) => e.id === inherit) ?? list[0]
  const mergeable = store.server.status === 'off' || list.every((e) => e.remote)

  const move = (i: number, by: number) => setOrder((o) => {
    const next = [...o]
    const j = i + by
    if (j < 0 || j >= next.length) return o
    ;[next[i], next[j]] = [next[j], next[i]]
    return next
  })
  const go = async () => {
    setBusy(true)
    const id = await store.groupTitles(order, { mode, title, inheritFrom: inherit, renumber })
    setBusy(false)
    if (!id) return
    onDone?.()
    onClose()
    nav.go(`/entry/${id}`)
  }

  return (
    <Sheet open tall title={`Group ${list.length} titles`} onClose={onClose}>
      <div className="segmented segmented--lg">
        <button type="button" className={mode === 'nest' ? 'is-on' : ''} onClick={() => setMode('nest')}>Keep nested</button>
        <button type="button" className={mode === 'merge' ? 'is-on' : ''} onClick={() => setMode('merge')} disabled={!mergeable}>Merge chapters</button>
      </div>
      <p className="hint pad-t-sm">
        {mode === 'nest' ? 'A new series holds these titles; each keeps its own chapters.'
          : 'One title with every chapter, in this order. Progress, bookmarks and linked sources come along; new chapters keep arriving.'}
        {!mergeable && ' Only titles from the server can be merged.'}
      </p>

      <div className="label">Order</div>
      <div className="check-list">
        {list.map((e, i) => (
          <div key={e.id} className="order-row">
            <Cover art={e.art} title={e.title} url={e.coverUrl} className="order-row__cover" />
            <span className="check-row__name check-row__name--stack grow">
              <strong className="ellipsis">{e.title}</strong>
              <span className="card-meta">{totalCount(e)} chapters</span>
            </span>
            <button type="button" className="icon-btn icon-btn--sm icon-btn--up" aria-label="Move up" disabled={i === 0} onClick={() => move(i, -1)}><Icon name="chevronDown" size={16} /></button>
            <button type="button" className="icon-btn icon-btn--sm" aria-label="Move down" disabled={i === list.length - 1} onClick={() => move(i, 1)}><Icon name="chevronDown" size={16} /></button>
          </div>
        ))}
      </div>

      {mode === 'merge' && (
        <>
          <div className="label">Chapter names</div>
          <div className="segmented">
            <button type="button" className={!renumber ? 'is-on' : ''} onClick={() => setRenumber(false)}>Keep original names</button>
            <button type="button" className={renumber ? 'is-on' : ''} onClick={() => setRenumber(true)}>Chapter 1, 2, 3…</button>
          </div>
        </>
      )}

      <div className="label">Details from</div>
      <div className="check-list">
        {list.map((e) => (
          <label key={e.id} className="check-row">
            <span className="check-row__name ellipsis">{e.title}</span>
            <input type="radio" name="inherit" checked={inherit === e.id} onChange={() => setInherit(e.id)} />
          </label>
        ))}
      </div>
      <div className="label">Name</div>
      <input className="form-input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder={from?.title ?? 'Title'} aria-label="Name of the new title" />
      <p className="hint">Everything can be edited afterwards from the title's ⋯ menu.</p>

      <div className="sheet__actions">
        <button type="button" className="btn btn--ghost" onClick={onClose}>Cancel</button>
        <button type="button" className="btn btn--accent" onClick={() => void go()} disabled={busy || list.length < 2}>{busy ? 'Working…' : mode === 'nest' ? 'Group' : 'Merge'}</button>
      </div>
    </Sheet>
  )
}

const normal = (t: string) => t.toLowerCase().normalize('NFKD').replace(/[^\p{L}\p{N}]+/gu, '')

/** Library titles that look like the same thing: the same name, or the same title on a source. */
export function findDuplicates(entries: Entry[]): Entry[][] {
  const list = entries.filter((e) => e.inLibrary)
  const parent = list.map((_, i) => i)
  const root = (i: number): number => (parent[i] === i ? i : (parent[i] = root(parent[i])))
  const join = (a: number, b: number) => { parent[root(a)] = root(b) }
  const seen = new Map<string, number>()
  list.forEach((e, i) => {
    const keys = [normal(e.title), ...e.sources.filter((s) => s.mangaUrl).map((s) => `${s.sourceId}|${s.mangaUrl}`)].filter((k) => k.length > 1)
    for (const k of keys) {
      const j = seen.get(k)
      if (j === undefined) seen.set(k, i)
      else join(i, j)
    }
  })
  const groups = new Map<number, Entry[]>()
  list.forEach((e, i) => groups.set(root(i), [...(groups.get(root(i)) ?? []), e]))
  return [...groups.values()].filter((g) => g.length > 1)
}

export function DuplicatesSheet({ onClose }: { onClose: () => void }) {
  const store = useStore()
  const nav = useNav()
  const groups = useMemo(() => findDuplicates(store.entries), [store.entries])
  const [merging, setMerging] = useState<string[] | null>(null)
  if (merging) return <GroupSheet ids={merging} initialMode="merge" onClose={() => setMerging(null)} onDone={onClose} />
  return (
    <Sheet open tall title="Duplicates" onClose={onClose}>
      {!groups.length && <Empty icon="check" tone="done" title="No duplicates" detail="No two titles in your library share a name or a source." />}
      {groups.length > 0 && <p className="hint">Titles with the same name, or the same title on a source. Merge them, or take one out of your library.</p>}
      {groups.map((g) => (
        <div key={g.map((e) => e.id).join()} className="dupe-group">
          {g.map((e) => (
            <div key={e.id} className="order-row">
              <Cover art={e.art} title={e.title} url={e.coverUrl} className="order-row__cover" />
              <button type="button" className="check-row__name check-row__name--stack grow plain-btn" onClick={() => { onClose(); nav.go(`/entry/${e.id}`) }}>
                <strong className="ellipsis">{e.title}</strong>
                <span className="card-meta">{totalCount(e)} ch · {e.sources.map((s) => s.name ?? s.sourceId).join(', ') || 'Made in Midoku'}{e.parentId ? ' · in a series' : ''}</span>
              </button>
              <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove ${e.title} from library`}
                onClick={() => { store.removeFromLibrary([e.id]); store.toast(`Removed ${e.title}`) }}><Icon name="trash" size={16} /></button>
            </div>
          ))}
          <button type="button" className="btn btn--ghost btn--block" onClick={() => setMerging(g.map((e) => e.id))}><Icon name="layers" size={16} />Merge these</button>
        </div>
      ))}
    </Sheet>
  )
}
