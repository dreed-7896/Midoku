import { useEffect, useState } from 'react'
import { getSourceFilters, type FilterChange, type SFilter, type TriState } from '../data/suwayomi'
import { Chip, Sheet } from './Chrome'
import { Icon } from './Icon'
import { Empty, Loading } from './Status'

/** What a filter is set to now, compared with its default, as the server's change input. */
function changeOf(now: SFilter, was: SFilter, position: number): FilterChange[] {
  switch (now.type) {
    case 'CheckBoxFilter': return now.checked !== (was as typeof now).checked ? [{ position, checkBoxState: now.checked }] : []
    case 'TriStateFilter': return now.tri !== (was as typeof now).tri ? [{ position, triState: now.tri }] : []
    case 'TextFilter': return now.text !== (was as typeof now).text ? [{ position, textState: now.text }] : []
    case 'SelectFilter': return now.selected !== (was as typeof now).selected ? [{ position, selectState: now.selected }] : []
    case 'SortFilter': {
      const a = now.sort, b = (was as typeof now).sort
      return a && (a.index !== b?.index || a.ascending !== b?.ascending) ? [{ position, sortState: a }] : []
    }
    case 'GroupFilter':
      return now.filters.flatMap((f, i) => changeOf(f, (was as typeof now).filters[i], i).map((groupChange) => ({ position, groupChange })))
    default: return []
  }
}
export const filterChanges = (now: SFilter[], defaults: SFilter[]) => now.flatMap((f, i) => changeOf(f, defaults[i], i))

const NEXT_TRI: Record<TriState, TriState> = { IGNORE: 'INCLUDE', INCLUDE: 'EXCLUDE', EXCLUDE: 'IGNORE' }

/**
 * The source's own filters (like native Midoku's Filters sheet): sort, genres to include or exclude, status…
 * Apply searches the source with them; Reset goes back to the source's defaults.
 */
export function SourceFilters({ sourceId, value, onApply, onClose }: { sourceId: string; value: SFilter[] | null; onApply: (filters: SFilter[] | null, changes: FilterChange[]) => void; onClose: () => void }) {
  const [defaults, setDefaults] = useState<SFilter[] | null>(null)
  const [draft, setDraft] = useState<SFilter[] | null>(value)
  const [error, setError] = useState<string>()

  useEffect(() => {
    getSourceFilters(sourceId).then((f) => { setDefaults(f); setDraft((d) => d ?? structuredClone(f)) }).catch((e: Error) => setError(e.message))
  }, [sourceId])

  const update = (path: number[], fn: (f: SFilter) => SFilter) => setDraft((d) => {
    if (!d) return d
    const next = structuredClone(d)
    let list = next
    for (const i of path.slice(0, -1)) list = (list[i] as Extract<SFilter, { type: 'GroupFilter' }>).filters
    const last = path[path.length - 1]
    list[last] = fn(list[last])
    return next
  })
  const changes = draft && defaults ? filterChanges(draft, defaults) : []

  const leaf = (f: SFilter, path: number[]) => {
    const key = path.join('.')
    switch (f.type) {
      case 'CheckBoxFilter':
        return <Chip key={key} on={f.checked} onClick={() => update(path, (x) => ({ ...x, checked: !(x as typeof f).checked }))}>{f.name}</Chip>
      case 'TriStateFilter':
        return (
          <Chip key={key} on={f.tri !== 'IGNORE'} onClick={() => update(path, (x) => ({ ...x, tri: NEXT_TRI[(x as typeof f).tri] }))}>
            {f.tri === 'INCLUDE' && <Icon name="check" size={13} stroke={2.4} />}{f.tri === 'EXCLUDE' && <Icon name="x" size={13} stroke={2.4} />}
            <span className={f.tri === 'EXCLUDE' ? 'strike' : undefined}>{f.name}</span>
          </Chip>
        )
      default: return null
    }
  }
  const block = (f: SFilter, path: number[]) => {
    const key = path.join('.')
    switch (f.type) {
      case 'HeaderFilter': return <div key={key} className="label">{f.name}</div>
      case 'SeparatorFilter': return <hr key={key} className="rule" />
      case 'TextFilter':
        return (
          <div key={key}>
            <div className="label">{f.name}</div>
            <input className="form-input" value={f.text} placeholder={f.name} onChange={(e) => update(path, (x) => ({ ...x, text: e.target.value }))} aria-label={f.name} />
          </div>
        )
      case 'SelectFilter':
        return (
          <div key={key}>
            <div className="label">{f.name}</div>
            {f.values.length > 12 ? (
              <label className="select-box">
                <select value={f.selected} onChange={(e) => update(path, (x) => ({ ...x, selected: Number(e.target.value) }))} aria-label={f.name}>
                  {f.values.map((v, i) => <option key={i} value={i}>{v}</option>)}
                </select>
                <Icon name="chevronDown" size={14} stroke={2} />
              </label>
            ) : (
              <div className="chips wrap">{f.values.map((v, i) => <Chip key={i} on={f.selected === i} onClick={() => update(path, (x) => ({ ...x, selected: i }))}>{v}</Chip>)}</div>
            )}
          </div>
        )
      case 'SortFilter':
        return (
          <div key={key}>
            <div className="label">{f.name}</div>
            <div className="chips wrap">
              {f.values.map((v, i) => {
                const on = f.sort?.index === i
                return (
                  <Chip key={i} on={on} onClick={() => update(path, (x) => {
                    const cur = (x as typeof f).sort
                    return { ...x, sort: { index: i, ascending: cur?.index === i ? !cur.ascending : false } }
                  })}>
                    {v}{on && <span className={`sort-dir${f.sort!.ascending ? ' is-up' : ''}`}><Icon name="chevronDown" size={13} stroke={2.4} /></span>}
                  </Chip>
                )
              })}
            </div>
          </div>
        )
      case 'GroupFilter': {
        const simple = f.filters.every((x) => x.type === 'CheckBoxFilter' || x.type === 'TriStateFilter')
        return (
          <div key={key}>
            <div className="label">{f.name}</div>
            {simple ? <div className="chips wrap">{f.filters.map((x, i) => leaf(x, [...path, i]))}</div> : f.filters.map((x, i) => block(x, [...path, i]))}
          </div>
        )
      }
      default: {
        const chip = leaf(f, path)
        return chip && <div key={key} className="chips wrap pad-t-sm">{chip}</div>
      }
    }
  }

  return (
    <Sheet open tall title="Filters" onClose={onClose}>
      {error && <Empty tone="error" icon="alert" title="Couldn't load filters" detail={error} />}
      {!draft && !error && <Loading label="Loading filters" shape="rows" count={4} />}
      {draft && !draft.length && <Empty icon="filter" title="No filters" detail="This source has no search filters." />}
      {draft?.some((f) => f.type === 'GroupFilter' && f.filters.some((x) => x.type === 'TriStateFilter')) && <p className="hint">Tap a tag once to include it, again to exclude it.</p>}
      {draft?.map((f, i) => block(f, [i]))}
      <div className="sheet__actions sheet__actions--sticky">
        <button type="button" className="btn btn--ghost" onClick={() => { if (defaults) setDraft(structuredClone(defaults)); onApply(null, []); onClose() }}>Reset</button>
        <button type="button" className="btn btn--accent" disabled={!draft} onClick={() => { onApply(changes.length ? draft : null, changes); onClose() }}>
          Apply{changes.length ? ` · ${changes.length}` : ''}
        </button>
      </div>
    </Sheet>
  )
}
