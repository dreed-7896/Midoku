import { FormEvent, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { BrowseType, Extension, Manga, browseSource, getExtension, img } from '../api'

export default function ExtensionBrowse() {
  const { pkg = '' } = useParams()
  const [ext, setExt] = useState<Extension | null>(null)
  const [sourceId, setSourceId] = useState<string | null>(null)
  const [type, setType] = useState<BrowseType>('POPULAR')
  const [query, setQuery] = useState('')
  const [submitted, setSubmitted] = useState('')
  const [items, setItems] = useState<Manga[]>([])
  const [page, setPage] = useState(1)
  const [hasNext, setHasNext] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    getExtension(pkg)
      .then((e) => {
        setExt(e)
        setSourceId(e?.source?.nodes[0]?.id ?? null)
      })
      .catch((e) => setError(e.message))
  }, [pkg])

  const sources = ext?.source?.nodes ?? []
  const source = sources.find((s) => s.id === sourceId)

  // Load a page whenever the source, mode, query or page changes.
  useEffect(() => {
    if (!sourceId) return
    let cancelled = false
    setLoading(true)
    setError(null)
    browseSource(sourceId, type, page, type === 'SEARCH' ? submitted : undefined)
      .then((r) => {
        if (cancelled) return
        setItems((prev) => (page === 1 ? r.mangas : [...prev, ...r.mangas]))
        setHasNext(r.hasNextPage)
      })
      .catch((e) => !cancelled && setError(e.message))
      .finally(() => !cancelled && setLoading(false))
    return () => {
      cancelled = true
    }
  }, [sourceId, type, page, submitted])

  const reset = (fn: () => void) => {
    setItems([])
    setPage(1)
    fn()
  }

  const onSearch = (e: FormEvent) => {
    e.preventDefault()
    const q = query.trim()
    reset(() => {
      setType(q ? 'SEARCH' : 'POPULAR')
      setSubmitted(q)
    })
  }

  return (
    <div className="page">
      <header className="bar">
        <Link to="/" className="back">
          ‹ Extensions
        </Link>
      </header>

      {ext && (
        <div className="hero">
          <img className="icon lg" src={img(ext.iconUrl)} alt="" />
          <div>
            <h1>{ext.name}</h1>
            <div className="sub">
              {sources.length} source{sources.length === 1 ? '' : 's'} · v{ext.versionName}
            </div>
          </div>
        </div>
      )}

      {sources.length > 1 && (
        <div className="chips">
          {sources.map((s) => (
            <button
              key={s.id}
              className={s.id === sourceId ? 'chip on' : 'chip'}
              onClick={() => reset(() => setSourceId(s.id))}
            >
              {s.lang.toUpperCase()}
            </button>
          ))}
        </div>
      )}

      <form onSubmit={onSearch}>
        <input
          className="search"
          placeholder={`Search ${source?.displayName ?? ''}`}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </form>

      <div className="tabs">
        <button className={type === 'POPULAR' ? 'tab on' : 'tab'} onClick={() => reset(() => setType('POPULAR'))}>
          Popular
        </button>
        {source?.supportsLatest && (
          <button className={type === 'LATEST' ? 'tab on' : 'tab'} onClick={() => reset(() => setType('LATEST'))}>
            Latest
          </button>
        )}
        {type === 'SEARCH' && <button className="tab on">“{submitted}”</button>}
      </div>

      {error && <p className="error">{error}</p>}

      <div className="grid">
        {items.map((m) => (
          <div key={m.id} className="card">
            <div className="cover">
              {m.thumbnailUrl && <img src={img(m.thumbnailUrl)} alt="" loading="lazy" />}
              {m.inLibrary && <span className="badge accent corner">In library</span>}
            </div>
            <div className="title">{m.title}</div>
          </div>
        ))}
      </div>

      {loading && <p className="muted center">Loading…</p>}
      {!loading && !error && items.length === 0 && sourceId && <p className="muted center">No entries.</p>}
      {!loading && hasNext && (
        <button className="more" onClick={() => setPage((p) => p + 1)}>
          Load more
        </button>
      )}
    </div>
  )
}
