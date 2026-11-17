import { FormEvent, useMemo, useState } from 'react'
import { Empty } from '../components/Status'
import { useSettings } from '../data/settings'
import { RemoteBrowse } from './Remote'
import { useParams } from 'react-router-dom'
import { TLink as Link, useNav } from '../components/Nav'
import { Cover, SourceIcon } from '../components/Art'
import { Chip, IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { catalogFor } from '../data/mock'
import { useStore } from '../data/store'

function SampleSourceBrowse() {
  const { id = '' } = useParams()
  const store = useStore()
  const nav = useNav()
  const source = store.source(id)
  const [lang, setLang] = useState(source?.langs[0] ?? 'EN')
  const [mode, setMode] = useState<'popular' | 'latest'>('popular')
  const [input, setInput] = useState('')
  const [query, setQuery] = useState('')
  const [pages, setPages] = useState(1)

  const items = useMemo(() => {
    const base = catalogFor(id)
    const ordered = mode === 'latest' ? [...base].reverse() : base
    const q = query.toLowerCase()
    const filtered = q ? ordered.filter((c) => c.title.toLowerCase().includes(q)) : ordered
    // Repeat the catalogue to fake further pages.
    return Array.from({ length: pages }, (_, p) => filtered.map((c) => ({ ...c, key: `${c.id}-${p}` }))).flat()
  }, [id, mode, query, pages])

  if (!source) {
    return <div className="page pad-x"><Empty icon="sources" title="Source not found" detail="It may have been uninstalled." /><Link to="/sources" className="btn btn--ghost">Back to sources</Link></div>
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    setQuery(input.trim())
    setPages(1)
  }

  return (
    <div className="page entry">
      <div className="entry__backdrop entry__backdrop--short" style={{ background: source.color }} aria-hidden="true">
        <span style={{ background: source.glow }} />
      </div>
      <div className="entry__top">
        <IconButton icon="back" label="Back" glass onClick={() => nav.back('/sources')} />
        <div className="row-gap">
          <IconButton icon="pin" label={source.pinned ? 'Unpin' : 'Pin'} glass active={source.pinned} onClick={() => store.togglePin(source.id)} />
          <IconButton icon="sliders" label="Source settings" glass onClick={() => store.toast('Source settings come later')} />
        </div>
      </div>

      <div className="source-head pad-x">
        <SourceIcon letter={source.letter} color={source.color} size={68} />
        <div>
          <h1 className="entry__title entry__title--left">{source.name}</h1>
          <div className="entry__author">{source.lang} · {source.langs.length} languages · v{source.version}</div>
        </div>
      </div>

      {source.langs.length > 1 && (
        <div className="chips pad-x pad-t">
          {source.langs.map((l) => <Chip key={l} on={l === lang} onClick={() => { setLang(l); setPages(1) }}>{l}</Chip>)}
        </div>
      )}

      <form className="pad-x pad-t-sm row-gap" onSubmit={submit}>
        <label className="field grow">
          <Icon name="search" size={18} />
          <input value={input} onChange={(e) => setInput(e.target.value)} placeholder={`Search ${source.name}`} aria-label="Search this source" enterKeyHint="search" />
        </label>
        <IconButton icon="filter" label="Filters" onClick={() => store.toast('Source filters come later')} />
      </form>

      <div className="underline-tabs pad-x" role="tablist">
        {query ? (
          <button type="button" role="tab" aria-selected className="is-on" onClick={() => { setQuery(''); setInput('') }}>“{query}” <Icon name="x" size={14} /></button>
        ) : (
          <>
            <button type="button" role="tab" aria-selected={mode === 'popular'} className={mode === 'popular' ? 'is-on' : ''} onClick={() => { setMode('popular'); setPages(1) }}>Popular</button>
            <button type="button" role="tab" aria-selected={mode === 'latest'} className={mode === 'latest' ? 'is-on' : ''} onClick={() => { setMode('latest'); setPages(1) }}>Latest</button>
          </>
        )}
      </div>

      <div className="grid3 pad-x pad-t">
        {items.map((c) => {
          const saved = !!c.entryId && !!store.entry(c.entryId)?.inLibrary
          return (
            <Link key={c.key} to={c.entryId ? `/entry/${c.entryId}` : '#'} className="card" onClick={(e) => { if (!c.entryId) { e.preventDefault(); store.toast('Details for titles outside your library come later') } }}>
              <div className="thumb">
                <Cover art={c.art} title={c.title} />
                {saved && <span className="badge badge--tl badge--glass"><Icon name="check" size={11} stroke={2.6} />Saved</span>}
              </div>
              <div className="card-title card-title--2">{c.title}</div>
            </Link>
          )
        })}
      </div>
      {items.length === 0 && <div className="pad-x pad-t"><Empty icon="search" title="No results" detail="Try another search on this source." /></div>}
      {items.length > 0 && pages < 4 && (
        <div className="center pad-t"><button type="button" className="btn btn--ghost" onClick={() => setPages((p) => p + 1)}>Load more</button></div>
      )}
    </div>
  )
}

/** Sample data until a Suwayomi server is set in Settings. */
export default function SourceBrowse() {
  const { serverUrl } = useSettings()
  return serverUrl ? <RemoteBrowse /> : <SampleSourceBrowse />
}
