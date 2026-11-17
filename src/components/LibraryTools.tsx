import { useEffect, useMemo, useState } from 'react'
import { totalCount, useStore } from '../data/store'
import type { Entry } from '../data/types'
import { artFor, assetUrl, browseSource, getSources, type SMangaCard, type SSource } from '../data/suwayomi'
import { Cover, SourceIcon } from './Art'
import { Sheet } from './Chrome'
import { Icon } from './Icon'
import { useNav } from './Nav'
import { Empty, Loading } from './Status'

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

type Match = { state: 'searching' } | { state: 'none' } | { state: 'error'; message: string } | { state: 'found'; results: SMangaCard[]; pick: number | null }

/**
 * Migrates several titles to one source: each is looked up there by name and the first result is
 * picked; tap a title to choose another result or skip it. Progress moves over by chapter number.
 */
export function BulkMigrateSheet({ ids, onClose, onDone }: { ids: string[]; onClose: () => void; onDone?: () => void }) {
  const store = useStore()
  const titles = ids.map((id) => store.entry(id)).filter((e): e is Entry => !!e && !!e.remote)
  const skipped = ids.length - titles.length
  const [sources, setSources] = useState<SSource[] | null>(null)
  const [filter, setFilter] = useState('')
  const [target, setTarget] = useState<SSource | null>(null)
  const [matches, setMatches] = useState<Record<string, Match>>({})
  const [open, setOpen] = useState<string>()
  const [running, setRunning] = useState<{ done: number; total: number } | null>(null)
  const [error, setError] = useState<string>()

  useEffect(() => { getSources().then((l) => setSources(l.filter((s) => s.id !== '0'))).catch((e: Error) => setError(e.message)) }, [])
  // Look every title up on the chosen source, two at a time.
  useEffect(() => {
    if (!target) return
    let alive = true
    const queue = [...titles]
    setMatches(Object.fromEntries(titles.map((e) => [e.id, { state: 'searching' } as Match])))
    const worker = async () => {
      for (let e = queue.shift(); e && alive; e = queue.shift()) {
        const id = e.id
        const m: Match = await browseSource(target.id, 'SEARCH', 1, e.original?.title ?? e.title)
          .then((r) => (r.mangas.length ? { state: 'found', results: r.mangas.slice(0, 9), pick: 0 } as Match : { state: 'none' } as Match))
          .catch((err: Error) => ({ state: 'error', message: err.message }))
        if (alive) setMatches((all) => ({ ...all, [id]: m }))
      }
    }
    void Promise.all([worker(), worker()])
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target])

  /** The pick is the title's current main source already: nothing to move. */
  const same = (e: Entry) => { const m = matches[e.id]; return m?.state === 'found' && m.pick !== null && e.remote?.sourceId === target?.id && m.results[m.pick].url === e.remote?.mangaUrl }
  const ready = titles.filter((e) => { const m = matches[e.id]; return m?.state === 'found' && m.pick !== null && !same(e) })
  const searching = titles.some((e) => matches[e.id]?.state === 'searching')
  const run = async () => {
    if (!target || !ready.length) return
    if (!window.confirm(`Migrate ${ready.length} title${ready.length === 1 ? '' : 's'} to ${target.displayName}? Reading progress moves over by chapter number; the old sources are unlinked.`)) return
    setRunning({ done: 0, total: ready.length })
    let ok = 0, moved = 0, failed = 0
    for (const e of ready) {
      const m = matches[e.id] as Extract<Match, { state: 'found' }>
      const r = m.results[m.pick!]
      const res = await store.migrateSource(e.id, { mangaId: r.id, mangaUrl: r.url, sourceId: target.id, name: target.displayName, iconUrl: target.iconUrl ? assetUrl(target.iconUrl) : undefined }, true).catch(() => false as const)
      if (res) { ok++; moved += res.moved } else failed++
      setRunning((x) => x && { ...x, done: x.done + 1 })
    }
    store.toast(`Migrated ${ok} title${ok === 1 ? '' : 's'} to ${target.displayName} · ${moved} chapters carried over${failed ? ` · ${failed} failed` : ''}`)
    onDone?.()
    onClose()
  }

  if (!target) {
    const q = filter.trim().toLowerCase()
    return (
      <Sheet open tall title={`Migrate ${titles.length} title${titles.length === 1 ? '' : 's'}`} onClose={onClose}>
        {skipped > 0 && <p className="hint">{skipped} picked title{skipped === 1 ? ' has' : 's have'} no source and can't be migrated.</p>}
        <p className="hint">Pick the source to move them to.</p>
        <label className="field"><Icon name="search" size={18} /><input value={filter} onChange={(e) => setFilter(e.target.value)} placeholder="Find a source" aria-label="Find a source" /></label>
        {error && <Empty compact tone="error" icon="alert" title="Couldn't load sources" detail={error} />}
        {!sources && !error && <Loading label="Loading sources" shape="rows" count={4} />}
        <div className="check-list pad-t-sm">
          {sources?.filter((s) => !q || s.displayName.toLowerCase().includes(q)).map((s) => (
            <button key={s.id} type="button" className="check-row" onClick={() => setTarget(s)}>
              <SourceIcon letter={s.name[0] ?? '?'} color="#22222A" size={28} url={assetUrl(s.iconUrl)} />
              <span className="check-row__name grow">{s.displayName}</span>
              <Icon name="chevronRight" size={18} />
            </button>
          ))}
        </div>
      </Sheet>
    )
  }

  return (
    <Sheet open tall title={`Migrate to ${target.displayName}`} onClose={onClose}>
      <button type="button" className="link-btn" disabled={!!running} onClick={() => { setTarget(null); setMatches({}) }}>Other source</button>
      <p className="hint">The first result is picked for each title. Tap one to choose another match or skip it.</p>
      <div className="check-list">
        {titles.map((e) => {
          const m = matches[e.id]
          const pick = m?.state === 'found' && m.pick !== null ? m.results[m.pick] : undefined
          const expanded = open === e.id && m?.state === 'found'
          return (
            <div key={e.id} className="dl-title">
              <button type="button" className="order-row history-row plain-btn" style={{ width: '100%' }} onClick={() => setOpen(expanded ? undefined : e.id)}>
                <Cover art={e.art} title={e.title} url={e.coverUrl} className="order-row__cover" />
                <span className="check-row__name check-row__name--stack grow">
                  <strong className="ellipsis">{e.title}</strong>
                  <span className={`card-meta ellipsis${m?.state === 'none' || m?.state === 'error' || same(e) ? ' accent-text' : ''}`}>
                    {!m || m.state === 'searching' ? 'Searching…' : m.state === 'none' ? 'No match · skipped' : m.state === 'error' ? `Search failed · ${m.message}` : same(e) ? 'Already on this source · skipped' : pick ? `→ ${pick.title}` : 'Skipped'}
                  </span>
                </span>
                {pick && <Cover art={artFor(pick.id)} title={pick.title} url={assetUrl(pick.thumbnailUrl)} className="order-row__cover" />}
              </button>
              {expanded && m.state === 'found' && (
                <div className="grid3 pad-t-sm pad-b">
                  {m.results.map((r, i) => (
                    <button key={r.id} type="button" className={`card plain-btn${m.pick === i ? ' is-picked' : ''}`} onClick={() => { setMatches((all) => ({ ...all, [e.id]: { ...m, pick: i } })); setOpen(undefined) }}>
                      <div className={`thumb${m.pick === i ? ' thumb--on' : ''}`}><Cover art={artFor(r.id)} title={r.title} url={assetUrl(r.thumbnailUrl)} /></div>
                      <div className="card-title card-title--2">{r.title}</div>
                    </button>
                  ))}
                  <button type="button" className="btn btn--ghost" onClick={() => { setMatches((all) => ({ ...all, [e.id]: { ...m, pick: null } })); setOpen(undefined) }}>Skip</button>
                </div>
              )}
            </div>
          )
        })}
      </div>
      <div className="sheet__actions sheet__actions--sticky">
        <button type="button" className="btn btn--ghost" onClick={onClose} disabled={!!running}>Cancel</button>
        <button type="button" className="btn btn--accent" disabled={!ready.length || searching || !!running} onClick={() => void run()}>
          {running ? `Migrating ${running.done + 1} of ${running.total}…` : searching ? 'Searching…' : `Migrate ${ready.length}`}
        </button>
      </div>
    </Sheet>
  )
}
