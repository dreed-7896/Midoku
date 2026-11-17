import { FormEvent, useEffect, useState } from 'react'
import { artFor, assetUrl, browseSource, getSources, SMangaCard, SSource } from '../data/suwayomi'
import { Cover, SourceIcon } from './Art'
import { Sheet } from './Chrome'
import { Icon } from './Icon'

export interface PickedTitle { mangaId: number; mangaUrl: string; sourceId: string; name?: string; iconUrl?: string }

/** Finds the same title on another installed source, to link it to an entry. */
export function SourcePicker({ query: initial, onPick, onClose }: { query: string; onPick: (m: PickedTitle) => void; onClose: () => void }) {
  const [sources, setSources] = useState<SSource[] | null>(null)
  const [source, setSource] = useState<SSource | null>(null)
  const [query, setQuery] = useState(initial)
  const [results, setResults] = useState<SMangaCard[] | null>(null)
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState(false)

  useEffect(() => { getSources().then(setSources).catch((e: Error) => setError(e.message)) }, [])

  const search = async (s: SSource, q: string) => {
    setBusy(true)
    setError(undefined)
    setResults(null)
    try {
      setResults((await browseSource(s.id, 'SEARCH', 1, q)).mangas)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  const pickSource = (s: SSource) => { setSource(s); void search(s, query) }
  const submit = (e: FormEvent) => { e.preventDefault(); if (source) void search(source, query) }

  return (
    <Sheet open title={source ? source.displayName : 'Link a source'} onClose={onClose}>
      {!source ? (
        <>
          <p className="hint">Pick the source to look for “{initial}” on.</p>
          {error && <p className="form__error">{error}</p>}
          {!sources && !error && <p className="hint">Loading sources…</p>}
          <div className="check-list">
            {sources?.map((s) => (
              <button key={s.id} type="button" className="check-row" onClick={() => pickSource(s)}>
                <SourceIcon letter={s.name[0] ?? '?'} color="#22222A" size={28} url={assetUrl(s.iconUrl)} />
                <span className="check-row__name">{s.displayName}</span>
                <Icon name="chevronRight" size={18} />
              </button>
            ))}
          </div>
        </>
      ) : (
        <>
          <form className="field" onSubmit={submit}>
            <Icon name="search" size={18} />
            <input value={query} onChange={(e) => setQuery(e.target.value)} aria-label="Search this source" enterKeyHint="search" />
          </form>
          <button type="button" className="link-btn" onClick={() => { setSource(null); setResults(null) }}>Other source</button>
          {busy && <p className="hint">Searching…</p>}
          {error && <p className="form__error">{error}</p>}
          {results && !results.length && <p className="hint">No results.</p>}
          <div className="grid3 pad-t-sm">
            {results?.map((m) => (
              <button key={m.id} type="button" className="card" onClick={() => onPick({
                mangaId: m.id, mangaUrl: m.url, sourceId: source.id, name: source.displayName, iconUrl: source.iconUrl ? assetUrl(source.iconUrl) : undefined,
              })}>
                <div className="thumb"><Cover art={artFor(m.id)} title={m.title} url={assetUrl(m.thumbnailUrl)} /></div>
                <div className="card-title card-title--2">{m.title}</div>
              </button>
            ))}
          </div>
        </>
      )}
    </Sheet>
  )
}
