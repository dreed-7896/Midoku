// Screens backed by the Suwayomi server: extensions, browsing a source, and searching every source.
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Cover, SourceIcon } from '../components/Art'
import { Chip, IconButton, PageHead } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { TLink as Link, useNav } from '../components/Nav'
import { useStore } from '../data/store'
import {
  artFor, assetUrl, browseSource, byLanguage, changeExtension, getExtensions, getExtensionSources, getSources, refreshExtensions,
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
    setExt(undefined); setExtError(undefined); setSourceId(undefined); setItems([]); setPage(1)
    getExtensionSources(pkg).then((e) => {
      const sources = byLanguage(e?.source?.nodes ?? [])
      if (!e || !e.isInstalled || !sources.length) { setExtError('This extension is not installed on the server.'); return }
      setExt(e)
      setSourceId(sources[0].id)
    }).catch((e: Error) => setExtError(e.message))
  }, [pkg])

  const sources = useMemo(() => byLanguage(ext?.source?.nodes ?? []), [ext])
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
          <div className="entry__author">{ext ? `${sources.length === 1 ? langLabel(sources[0].lang) : `${sources.length} languages`} · v${ext.versionName}` : extError ? '' : 'Loading…'}</div>
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

type SearchSource = SSource & { extension: { pkgName: string } | null }
/** One section per extension: its sources in every language, searched and merged. */
type SearchGroup = { key: string; pkg: string; name: string; iconUrl: string; sources: SearchSource[] }
type SearchResult = { done: number; total: number; items: SMangaCard[]; errors: string[] }

const titleKey = (t: string) => t.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '')

export function RemoteSearch() {
  const store = useStore()
  const [query, setQuery] = useState('')
  const [debounced, setDebounced] = useState('')
  const [english, setEnglish] = useState(false)
  const [hideNsfw, setHideNsfw] = useState(true)
  const [sources, setSources] = useState<SearchSource[] | null>(null)
  const [error, setError] = useState<string>()
  const [results, setResults] = useState<Record<string, SearchResult>>({})
  const run = useRef(0)

  useEffect(() => { getSources().then(setSources).catch((e: Error) => setError(e.message)) }, [])
  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 400)
    return () => clearTimeout(t)
  }, [query])

  // An extension's "All" source covers every language in one search; only extensions without one
  // fall back to searching each language. "English only" uses the English source instead.
  const groups = useMemo(() => {
    const map = new Map<string, SearchGroup>()
    for (const s of sources ?? []) {
      if (hideNsfw && s.isNsfw) continue
      const key = s.extension?.pkgName ?? s.id
      const g = map.get(key) ?? { key, pkg: s.extension?.pkgName ?? '', name: s.name, iconUrl: s.iconUrl, sources: [] }
      g.sources.push(s)
      map.set(key, g)
    }
    const pick = (list: SearchSource[]) => {
      const of = (lang: string) => list.filter((s) => s.lang === lang)
      if (english) return of('en').length ? of('en') : of('all')
      return of('all').length ? of('all') : byLanguage(list)
    }
    return [...map.values()].map((g) => ({ ...g, sources: pick(g.sources) })).filter((g) => g.sources.length)
  }, [sources, english, hideNsfw])
  const groupsKey = groups.map((g) => g.sources.map((s) => s.id).join()).join('|')

  // One request per extension first so each section fills in quickly; extra languages (for
  // extensions without an "All" source) follow and are merged in without duplicates. Four at a time.
  useEffect(() => {
    if (!debounced || !groups.length) return
    const id = ++run.current
    setResults(Object.fromEntries(groups.map((g) => [g.key, { done: 0, total: g.sources.length, items: [], errors: [] } as SearchResult])))
    const depth = Math.max(...groups.map((g) => g.sources.length))
    const queue: { key: string; source: string }[] = []
    for (let i = 0; i < depth; i++) for (const g of groups) if (g.sources[i]) queue.push({ key: g.key, source: g.sources[i].id })
    const worker = async () => {
      while (queue.length && run.current === id) {
        const job = queue.shift()!
        let found: SMangaCard[] = []
        let failure: string | undefined
        try {
          found = (await browseSource(job.source, 'SEARCH', 1, debounced)).mangas
        } catch (e) {
          failure = (e as Error).message
        }
        if (run.current !== id) return
        setResults((prev) => {
          const r = prev[job.key]
          if (!r) return prev
          const seen = new Set(r.items.map((m) => titleKey(m.title)))
          const fresh = found.filter((m) => {
            const k = titleKey(m.title)
            if (seen.has(k)) return false
            seen.add(k)
            return true
          })
          return { ...prev, [job.key]: { ...r, done: r.done + 1, items: fresh.length ? [...r.items, ...fresh] : r.items, errors: failure ? [...r.errors, failure] : r.errors } }
        })
      }
    }
    Promise.all([worker(), worker(), worker(), worker()])
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debounced, groupsKey])

  const q = debounced.toLowerCase()
  const local = store.entries.filter((e) => e.inLibrary && q && e.title.toLowerCase().includes(q))
  const resultFor = (g: SearchGroup): SearchResult => results[g.key] ?? { done: 0, total: g.sources.length, items: [], errors: [] }
  const order = (g: SearchGroup) => {
    const r = resultFor(g)
    return r.items.length ? 0 : r.done < r.total ? 1 : 2
  }

  return (
    <div className="page">
      <PageHead kicker={`${groups.length} sources · your library`} title="Search" />
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
        <p className="hint pad-x pad-t">{sources && !sources.length ? 'Install an extension in Sources first.' : `Searches your library and ${groups.length} sources, in every language${english ? ' you picked' : ''}.`}</p>
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

          {[...groups].sort((a, b) => order(a) - order(b)).map((g) => {
            const r = resultFor(g)
            const searching = r.done < r.total
            const failed = !searching && !r.items.length && r.errors.length === r.total
            if (!searching && !r.items.length && !failed) return null
            return (
              <section key={g.key} className="section">
                <Link to={`/sources/${encodeURIComponent(g.pkg)}`} className="section-head pad-x link-row">
                  <h2 className="h3"><SourceIcon letter={g.name[0] ?? '?'} color={ICON_BG} size={28} url={assetUrl(g.iconUrl)} />{g.name}</h2>
                  <span className="card-meta">
                    {searching ? (r.total > 1 ? `Searching ${r.done}/${r.total}…` : 'Searching…') : failed ? '' : `${r.items.length} result${r.items.length === 1 ? '' : 's'}`}
                  </span>
                  <Icon name="chevronRight" size={18} />
                </Link>
                {!r.items.length && searching && <div className="rail" aria-hidden="true">{[0, 1, 2].map((i) => <div key={i} className="rail__item skeleton" />)}</div>}
                {failed && <div className="pad-x"><Notice {...sourceError(r.errors[0] ?? '')} /></div>}
                {r.items.length > 0 && <div className="rail">{r.items.map((m) => <MangaCard key={m.id} m={m} rail />)}</div>}
              </section>
            )
          })}
        </>
      )}
    </div>
  )
}
