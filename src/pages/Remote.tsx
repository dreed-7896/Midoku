// Screens backed by the Suwayomi server: extensions, browsing a source, and searching every source.
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Cover, SourceIcon } from '../components/Art'
import { Chip, IconButton, PageHead } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { TLink as Link, useNav } from '../components/Nav'
import { useStore } from '../data/store'
import {
  artFor, assetUrl, browseSource, changeExtension, getExtensions, getExtensionSources, getSources, refreshExtensions,
  SExtension, SMangaCard, SSource,
} from '../data/suwayomi'

const PAGE_SIZE = 60
const ICON_BG = '#22222A'

/** Turns source errors into something readable; Cloudflare blocks get advice. */
export function sourceError(message: string): { title: string; detail: string } {
  if (/cloudflare|captcha|challenge|\b403\b|\b503\b/i.test(message)) {
    return { title: 'Verification needed', detail: 'This source is behind Cloudflare. Turn on FlareSolverr in Suwayomi, or open the source once in its WebView.' }
  }
  return { title: "Couldn't load this source", detail: message }
}

function Notice({ title, detail, onRetry }: { title: string; detail: string; onRetry?: () => void }) {
  return (
    <div className="notice">
      <span className="notice__icon"><Icon name="shield" /></span>
      <span className="grow"><strong>{title}</strong><span className="card-meta card-meta--wrap">{detail}</span></span>
      {onRetry && <button type="button" className="btn btn--light btn--sm" onClick={onRetry}>Retry</button>}
    </div>
  )
}

const langLabel = (lang: string) => (lang === 'all' ? 'Multi' : lang.toUpperCase())

function MangaCard({ m, rail }: { m: SMangaCard; rail?: boolean }) {
  return (
    <Link to={`/entry/s${m.id}`} className={rail ? 'rail__item' : 'card'}>
      <div className="thumb">
        <Cover art={artFor(m.id)} title={m.title} url={assetUrl(m.thumbnailUrl)} />
        {m.inLibrary && <span className="badge badge--tl badge--glass"><Icon name="check" size={11} stroke={2.6} />Saved</span>}
      </div>
      <div className="card-title card-title--2">{m.title}</div>
    </Link>
  )
}

export function RemoteSources() {
  const store = useStore()
  const [tab, setTab] = useState<'installed' | 'available'>('installed')
  const [query, setQuery] = useState('')
  const [lang, setLang] = useState('all-langs')
  const [exts, setExts] = useState<SExtension[] | null>(null)
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState<string | null>(null)
  const [limit, setLimit] = useState(PAGE_SIZE)

  const load = useCallback(async (refresh = false) => {
    setError(undefined)
    try {
      setExts(refresh ? await refreshExtensions() : await getExtensions())
    } catch (e) {
      setError((e as Error).message)
    }
  }, [])
  useEffect(() => { load() }, [load])

  const all = exts ?? []
  const installed = all.filter((e) => e.isInstalled)
  const updates = installed.filter((e) => e.hasUpdate)
  const langs = useMemo(() => [...new Set(all.map((e) => e.lang))].sort(), [all])
  const q = query.trim().toLowerCase()
  const match = (e: SExtension) => (!q || e.name.toLowerCase().includes(q)) && (lang === 'all-langs' || e.lang === lang)
  const list = (tab === 'installed' ? installed : all.filter((e) => !e.isInstalled)).filter(match).sort((a, b) => a.name.localeCompare(b.name))

  const act = async (ext: SExtension, action: 'install' | 'uninstall' | 'update') => {
    setBusy(ext.pkgName)
    try {
      await changeExtension(ext.pkgName, action)
      await load()
      store.toast(action === 'install' ? `${ext.name} installed` : action === 'update' ? `${ext.name} updated` : `${ext.name} removed`)
    } catch (e) {
      store.toast((e as Error).message)
    } finally {
      setBusy(null)
    }
  }
  const updateAll = async () => {
    setBusy('all')
    for (const ext of updates) await changeExtension(ext.pkgName, 'update').catch(() => {})
    await load()
    setBusy(null)
    store.toast('Extensions updated')
  }

  return (
    <div className="page">
      <PageHead kicker={`${installed.length} installed · Suwayomi`} title="Sources">
        <IconButton icon="refresh" label="Check repositories for new extensions" onClick={async () => { await load(true); store.toast('Extension list refreshed') }} />
      </PageHead>

      <div className="pad-x pad-t">
        <div className="segmented segmented--lg" role="tablist">
          <button type="button" role="tab" aria-selected={tab === 'installed'} className={tab === 'installed' ? 'is-on' : ''} onClick={() => { setTab('installed'); setLimit(PAGE_SIZE) }}>Installed · {installed.length}</button>
          <button type="button" role="tab" aria-selected={tab === 'available'} className={tab === 'available' ? 'is-on' : ''} onClick={() => { setTab('available'); setLimit(PAGE_SIZE) }}>Available · {all.length - installed.length}</button>
        </div>
      </div>

      {tab === 'installed' && updates.length > 0 && (
        <div className="pad-x pad-t-sm">
          <div className="banner">
            <Icon name="refresh" />
            <span className="grow">{updates.length} update{updates.length === 1 ? '' : 's'} available</span>
            <button type="button" className="btn btn--accent btn--sm" disabled={!!busy} onClick={updateAll}>{busy === 'all' ? 'Updating…' : 'Update all'}</button>
          </div>
        </div>
      )}

      <div className="pad-x pad-t-sm row-gap">
        <label className="field grow">
          <Icon name="search" size={18} />
          <input value={query} onChange={(e) => { setQuery(e.target.value); setLimit(PAGE_SIZE) }} placeholder="Search extensions" aria-label="Search extensions" />
        </label>
        <label className="select-box">
          <select value={lang} onChange={(e) => { setLang(e.target.value); setLimit(PAGE_SIZE) }} aria-label="Language">
            <option value="all-langs">All languages</option>
            {langs.map((l) => <option key={l} value={l}>{langLabel(l)}</option>)}
          </select>
          <Icon name="chevronDown" size={14} stroke={2} />
        </label>
      </div>

      <section className="section pad-x">
        {error && <Notice title="Couldn't load extensions" detail={error} onRetry={() => load()} />}
        {!exts && !error && <p className="hint">Loading extensions…</p>}
        {exts && list.length === 0 && (
          <p className="empty">{tab === 'installed' ? 'No extensions installed yet. Open Available to add some.' : 'Nothing matches. Add an extension repository in Suwayomi to see more.'}</p>
        )}
        <div className="grid3">
          {list.slice(0, limit).map((e) => {
            const icon = <SourceIcon letter={e.name[0] ?? '?'} color={ICON_BG} size={42} url={assetUrl(e.iconUrl)} />
            return e.isInstalled ? (
              <Link key={e.pkgName} to={`/sources/${encodeURIComponent(e.pkgName)}`} className="tile">
                <span className="split">
                  {icon}
                  {e.hasUpdate && <span className="update-dot" role="img" aria-label="Update available" />}
                </span>
                <span className="tile__name">{e.name}</span>
                <span className="card-meta">{langLabel(e.lang)} · v{e.versionName}</span>
              </Link>
            ) : (
              <div key={e.pkgName} className="tile">
                <span className="split">{icon}{e.isNsfw && <span className="tag">18+</span>}</span>
                <span className="tile__name">{e.name}</span>
                <span className="card-meta">{langLabel(e.lang)} · v{e.versionName}</span>
                <button type="button" className="btn btn--ghost btn--sm btn--block" disabled={!!busy} onClick={() => act(e, 'install')}>
                  <Icon name="download" size={14} stroke={2} /> {busy === e.pkgName ? 'Installing…' : 'Install'}
                </button>
              </div>
            )
          })}
        </div>
        {list.length > limit && (
          <div className="center pad-t"><button type="button" className="btn btn--ghost" onClick={() => setLimit((n) => n + PAGE_SIZE)}>Show more · {list.length - limit} left</button></div>
        )}
      </section>
    </div>
  )
}

export function RemoteBrowse() {
  const { id = '' } = useParams()
  const pkg = decodeURIComponent(id)
  const nav = useNav()
  const store = useStore()
  const [ext, setExt] = useState<SExtension>()
  const [extError, setExtError] = useState<string>()
  const [sourceId, setSourceId] = useState<string>()
  const [mode, setMode] = useState<'POPULAR' | 'LATEST'>('POPULAR')
  const [input, setInput] = useState('')
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(1)
  const [items, setItems] = useState<SMangaCard[]>([])
  const [hasNext, setHasNext] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string>()
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    getExtensionSources(pkg).then((e) => {
      if (!e) { setExtError('This extension is not installed.'); return }
      setExt(e)
      const sources = e.source?.nodes ?? []
      setSourceId((sources.find((s) => s.lang === 'en') ?? sources.find((s) => s.lang === 'all') ?? sources[0])?.id)
    }).catch((e: Error) => setExtError(e.message))
  }, [pkg])

  const sources = ext?.source?.nodes ?? []
  const source = sources.find((s) => s.id === sourceId)

  useEffect(() => {
    if (!sourceId) return
    let alive = true
    setLoading(true)
    setError(undefined)
    browseSource(sourceId, query ? 'SEARCH' : mode, page, query || undefined)
      .then((r) => {
        if (!alive) return
        setItems((prev) => (page === 1 ? r.mangas : [...prev, ...r.mangas]))
        setHasNext(r.hasNextPage)
      })
      .catch((e: Error) => alive && setError(e.message))
      .finally(() => alive && setLoading(false))
    return () => { alive = false }
  }, [sourceId, mode, query, page, attempt])

  const reset = (fn: () => void) => { setItems([]); setPage(1); fn() }
  const submit = (e: FormEvent) => { e.preventDefault(); reset(() => setQuery(input.trim())) }

  return (
    <div className="page entry">
      <div className="entry__backdrop entry__backdrop--short" style={{ background: '#1A1A22' }} aria-hidden="true"><span style={{ background: '#FF6B5E' }} /></div>
      <div className="entry__top">
        <IconButton icon="back" label="Back" glass onClick={() => nav.back('/sources')} />
      </div>
      <div className="source-head pad-x">
        <SourceIcon letter={(ext?.name ?? pkg)[0] ?? '?'} color={ICON_BG} size={68} url={ext ? assetUrl(ext.iconUrl) : undefined} />
        <div>
          <h1 className="entry__title entry__title--left">{source?.displayName.replace(/\s*\(.*\)$/, '') ?? ext?.name ?? 'Source'}</h1>
          <div className="entry__author">{ext ? `${sources.length} language${sources.length === 1 ? '' : 's'} · v${ext.versionName}` : extError ? '' : 'Loading…'}</div>
        </div>
      </div>
      {extError && <div className="pad-x pad-t"><Notice title="Couldn't open this source" detail={extError} /></div>}

      {sources.length > 1 && (
        <div className="chips pad-x pad-t">
          {sources.map((s: SSource) => <Chip key={s.id} on={s.id === sourceId} onClick={() => reset(() => setSourceId(s.id))}>{langLabel(s.lang)}</Chip>)}
        </div>
      )}

      <form className="pad-x pad-t-sm row-gap" onSubmit={submit}>
        <label className="field grow">
          <Icon name="search" size={18} />
          <input value={input} onChange={(e) => setInput(e.target.value)} placeholder={`Search ${ext?.name ?? 'this source'}`} aria-label="Search this source" enterKeyHint="search" />
        </label>
      </form>

      <div className="underline-tabs pad-x" role="tablist">
        {query ? (
          <button type="button" role="tab" aria-selected className="is-on" onClick={() => { setInput(''); reset(() => setQuery('')) }}>“{query}” <Icon name="x" size={14} /></button>
        ) : (
          <>
            <button type="button" role="tab" aria-selected={mode === 'POPULAR'} className={mode === 'POPULAR' ? 'is-on' : ''} onClick={() => reset(() => setMode('POPULAR'))}>Popular</button>
            {source?.supportsLatest && <button type="button" role="tab" aria-selected={mode === 'LATEST'} className={mode === 'LATEST' ? 'is-on' : ''} onClick={() => reset(() => setMode('LATEST'))}>Latest</button>}
          </>
        )}
      </div>

      {error && <div className="pad-x pad-t"><Notice {...sourceError(error)} onRetry={() => setAttempt((n) => n + 1)} /></div>}
      <div className="grid3 pad-x pad-t">
        {items.map((m, i) => <MangaCard key={`${m.id}-${i}`} m={m} />)}
      </div>
      {loading && <p className="hint center pad-t">Loading…</p>}
      {!loading && !error && items.length === 0 && sourceId && <p className="empty pad-x">No results.</p>}
      {!loading && hasNext && <div className="center pad-t"><button type="button" className="btn btn--ghost" onClick={() => setPage((p) => p + 1)}>Load more</button></div>}
      {store.server.status === 'error' && <p className="hint pad-x">{store.server.error}</p>}
    </div>
  )
}

type SearchResult = { state: 'loading' | 'done' | 'error'; items: SMangaCard[]; error?: string }

export function RemoteSearch() {
  const store = useStore()
  const [query, setQuery] = useState('')
  const [debounced, setDebounced] = useState('')
  const [english, setEnglish] = useState(false)
  const [hideNsfw, setHideNsfw] = useState(true)
  const [sources, setSources] = useState<(SSource & { extension: { pkgName: string } | null })[] | null>(null)
  const [error, setError] = useState<string>()
  const [results, setResults] = useState<Record<string, SearchResult>>({})
  const run = useRef(0)

  useEffect(() => { getSources().then(setSources).catch((e: Error) => setError(e.message)) }, [])
  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 400)
    return () => clearTimeout(t)
  }, [query])

  const active = (sources ?? []).filter((s) => (!english || s.lang === 'en') && (!hideNsfw || !s.isNsfw))
  const activeKey = active.map((s) => s.id).join()

  // Searches every source, three at a time, showing each one as it answers.
  useEffect(() => {
    if (!debounced || !active.length) return
    const id = ++run.current
    setResults(Object.fromEntries(active.map((s) => [s.id, { state: 'loading', items: [] } as SearchResult])))
    const queue = [...active]
    const worker = async () => {
      while (queue.length && run.current === id) {
        const s = queue.shift()!
        try {
          const r = await browseSource(s.id, 'SEARCH', 1, debounced)
          if (run.current === id) setResults((prev) => ({ ...prev, [s.id]: { state: 'done', items: r.mangas } }))
        } catch (e) {
          if (run.current === id) setResults((prev) => ({ ...prev, [s.id]: { state: 'error', items: [], error: (e as Error).message } }))
        }
      }
    }
    Promise.all([worker(), worker(), worker()])
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debounced, activeKey])

  const q = debounced.toLowerCase()
  const local = store.entries.filter((e) => e.inLibrary && q && e.title.toLowerCase().includes(q))
  const order = (s: SSource) => ({ done: results[s.id]?.items.length ? 0 : 2, loading: 1, error: 3 }[results[s.id]?.state ?? 'loading'])

  return (
    <div className="page">
      <PageHead kicker={`${active.length} sources · your library`} title="Search" />
      <div className="pad-x pad-t">
        <label className="field field--lg field--focus">
          <Icon name="search" size={20} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search titles everywhere" aria-label="Search all sources and your library" enterKeyHint="search" />
          {query && <button type="button" className="icon-btn icon-btn--sm" aria-label="Clear search" onClick={() => setQuery('')}><Icon name="x" size={16} /></button>}
        </label>
      </div>
      <div className="chips pad-x pad-t-sm">
        <Chip on={english} onClick={() => setEnglish((x) => !x)}>English only</Chip>
        <Chip on={hideNsfw} onClick={() => setHideNsfw((x) => !x)}>Hide 18+</Chip>
      </div>

      {error && <div className="pad-x pad-t"><Notice title="Couldn't load sources" detail={error} /></div>}
      {!debounced ? (
        <p className="hint pad-x pad-t">{sources && !sources.length ? 'Install an extension in Sources first.' : `Searches your library and ${active.length} sources at once.`}</p>
      ) : (
        <>
          <section className="section pad-x">
            <div className="section-head">
              <h2 className="h3"><Icon name="library" size={18} /> In your library</h2>
              <span className="card-meta">{local.length} match{local.length === 1 ? '' : 'es'}</span>
            </div>
            {local.length === 0 ? <p className="hint">No matches in your library.</p> : (
              <div className="grid2">
                {local.map((e) => (
                  <Link key={e.id} to={`/entry/${e.id}`} className="tile tile--row">
                    <Cover art={e.art} title={e.title} url={e.coverUrl} className="tile__cover" />
                    <span className="grow"><span className="card-title card-title--2">{e.title}</span><span className="card-meta">{e.sources[0]?.name ?? ''}</span></span>
                  </Link>
                ))}
              </div>
            )}
          </section>

          {[...active].sort((a, b) => order(a) - order(b)).map((s) => {
            const r = results[s.id] ?? { state: 'loading', items: [] }
            if (r.state === 'done' && !r.items.length) return null
            return (
              <section key={s.id} className="section">
                <Link to={`/sources/${encodeURIComponent(s.extension?.pkgName ?? '')}`} className="section-head pad-x link-row">
                  <h2 className="h3"><SourceIcon letter={s.name[0] ?? '?'} color={ICON_BG} size={28} url={assetUrl(s.iconUrl)} />{s.displayName}</h2>
                  <span className="card-meta">{r.state === 'loading' ? 'Searching…' : r.state === 'done' ? `${r.items.length} results` : ''}</span>
                  <Icon name="chevronRight" size={18} />
                </Link>
                {r.state === 'loading' && <div className="rail" aria-hidden="true">{[0, 1, 2].map((i) => <div key={i} className="rail__item skeleton" />)}</div>}
                {r.state === 'error' && <div className="pad-x"><Notice {...sourceError(r.error ?? '')} /></div>}
                {r.state === 'done' && <div className="rail">{r.items.map((m) => <MangaCard key={m.id} m={m} rail />)}</div>}
              </section>
            )
          })}
        </>
      )}
    </div>
  )
}
