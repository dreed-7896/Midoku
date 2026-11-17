import { useEffect, useState } from 'react'
import { useStore } from '../data/store'
import { getSourcePreferences, setSourcePreference, type PreferenceChange, type SPreference } from '../data/suwayomi'
import { Sheet } from './Chrome'
import { Icon } from './Icon'
import { Empty, Loading } from './Status'

/**
 * An extension's own settings for one source (like native Midoku's source settings): switches, choices,
 * multi-choices and text. Each change is saved on the server at once.
 */
export function SourceSettings({ sourceId, title, onClose }: { sourceId: string; title: string; onClose: () => void }) {
  const store = useStore()
  const [prefs, setPrefs] = useState<SPreference[] | null>(null)
  const [error, setError] = useState<string>()
  const [saving, setSaving] = useState<number | null>(null)
  const [open, setOpen] = useState<number | null>(null)
  const [draft, setDraft] = useState('')

  useEffect(() => { getSourcePreferences(sourceId).then(setPrefs).catch((e: Error) => setError(e.message)) }, [sourceId])

  const save = async (position: number, change: Omit<PreferenceChange, 'position'>) => {
    setSaving(position)
    try { setPrefs(await setSourcePreference(sourceId, { position, ...change })) } catch (e) { store.toast(`Couldn't save: ${(e as Error).message}`) } finally { setSaving(null) }
  }

  const row = (p: SPreference, i: number) => {
    if (!p.visible) return null
    const busy = saving === i
    const disabled = !p.enabled || saving !== null
    switch (p.type) {
      case 'CheckBoxPreference':
      case 'SwitchPreference': {
        const on = p.on ?? p.onDefault ?? false
        return (
          <label key={i} className="check-row">
            <span className="check-row__name check-row__name--stack"><strong>{p.title}</strong>{p.summary && <span className="card-meta card-meta--wrap">{p.summary}</span>}</span>
            <input type="checkbox" role="switch" className="switch" checked={on} disabled={disabled}
              onChange={() => void save(i, p.type === 'SwitchPreference' ? { switchState: !on } : { checkBoxState: !on })} />
          </label>
        )
      }
      case 'ListPreference': {
        const value = p.value ?? p.valueDefault ?? ''
        const label = p.entries[p.entryValues.indexOf(value)] ?? value
        return (
          <div key={i}>
            <button type="button" className="check-row" style={{ width: '100%' }} disabled={disabled} aria-expanded={open === i} onClick={() => setOpen(open === i ? null : i)}>
              <span className="check-row__name check-row__name--stack grow"><strong>{p.title}</strong><span className="card-meta card-meta--wrap">{busy ? 'Saving…' : label || p.summary}</span></span>
              <Icon name={open === i ? 'chevronDown' : 'chevronRight'} size={16} />
            </button>
            {open === i && (
              <div className="check-list check-list--inset">
                {p.entries.map((e, k) => (
                  <button key={k} type="button" className="check-row" onClick={() => { setOpen(null); if (p.entryValues[k] !== value) void save(i, { listState: p.entryValues[k] }) }}>
                    <span className="check-row__name">{e}</span>{p.entryValues[k] === value && <Icon name="check" size={18} />}
                  </button>
                ))}
              </div>
            )}
          </div>
        )
      }
      case 'MultiSelectListPreference': {
        const values = p.values ?? p.valuesDefault ?? []
        const label = p.entries.filter((_, k) => values.includes(p.entryValues[k])).join(', ')
        return (
          <div key={i}>
            <button type="button" className="check-row" style={{ width: '100%' }} disabled={disabled} aria-expanded={open === i} onClick={() => setOpen(open === i ? null : i)}>
              <span className="check-row__name check-row__name--stack grow"><strong>{p.title}</strong><span className="card-meta card-meta--wrap">{busy ? 'Saving…' : label || 'None'}</span></span>
              <Icon name={open === i ? 'chevronDown' : 'chevronRight'} size={16} />
            </button>
            {open === i && (
              <div className="check-list check-list--inset">
                {p.entries.map((e, k) => {
                  const v = p.entryValues[k]
                  const on = values.includes(v)
                  return (
                    <label key={k} className="check-row">
                      <span className="check-row__name">{e}</span>
                      <input type="checkbox" checked={on} disabled={saving !== null} onChange={() => void save(i, { multiSelectState: on ? values.filter((x) => x !== v) : [...values, v] })} />
                    </label>
                  )
                })}
              </div>
            )}
          </div>
        )
      }
      case 'EditTextPreference': {
        const text = p.text ?? p.textDefault ?? ''
        return (
          <div key={i}>
            <button type="button" className="check-row" style={{ width: '100%' }} disabled={disabled} onClick={() => { setDraft(text); setOpen(open === i ? null : i) }}>
              <span className="check-row__name check-row__name--stack grow"><strong>{p.title}</strong><span className="card-meta card-meta--wrap">{busy ? 'Saving…' : text || p.summary || 'Not set'}</span></span>
              <Icon name={open === i ? 'chevronDown' : 'chevronRight'} size={16} />
            </button>
            {open === i && (
              <div className="pad-b">
                {p.dialogMessage && <p className="hint">{p.dialogMessage}</p>}
                <textarea className="form-input form-input--area" rows={3} value={draft} onChange={(e) => setDraft(e.target.value)} aria-label={p.title} />
                <div className="sheet__actions sheet__actions--flush pad-t-sm">
                  <button type="button" className="btn btn--ghost" onClick={() => setOpen(null)}>Cancel</button>
                  <button type="button" className="btn btn--accent" onClick={() => { setOpen(null); void save(i, { editTextState: draft }) }}>Save</button>
                </div>
              </div>
            )}
          </div>
        )
      }
    }
  }

  return (
    <Sheet open tall title={`${title} settings`} onClose={onClose}>
      {error && <Empty tone="error" icon="alert" title="Couldn't load settings" detail={error} />}
      {!prefs && !error && <Loading label="Loading settings" shape="rows" count={5} />}
      {prefs && !prefs.some((p) => p.visible) && <Empty icon="settings" title="No settings" detail="This source has nothing to set." />}
      {prefs && <div className="check-list">{prefs.map(row)}</div>}
      {prefs && <p className="hint">Saved on the server right away. Some changes apply after you refresh a title or the source list.</p>}
    </Sheet>
  )
}
