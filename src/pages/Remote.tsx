// Screens backed by the Suwayomi server: extensions, browsing a source, and searching every source.
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Cover, SourceIcon } from '../components/Art'
import { Chip, IconButton, PageHead, Sheet } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { Banner, Empty, Loading } from '../components/Status'
import { TLink as Link, useNav } from '../components/Nav'
import { useStore } from '../data/store'
import {
  artFor, assetUrl, browseSource, byLanguage, changeExtension, getExtensions, getExtensionSources, getRepos, getSources, refreshExtensions, setRepos,
  SExtension, SMangaCard, SSource, webviewUrl, type FilterChange, type SFilter,
} from '../data/suwayomi'
import { SourceFilters } from '../components/SourceFilters'
import { SourceSettings } from '../components/SourceSettings'

const PAGE_SIZE = 60

// Kept for the session so Sources and Search open straight away; they refresh quietly in the background.
let extCache: SExtension[] | null = null
let sourceCache: SearchSource[] | null = null
let lastSearch: { query: string; results: Record<string, SearchResult> } = { query: '', results: {} }
const ICON_BG = '#22222A'

/** Turns source errors into something readable; Cloudflare blocks get advice. */
export function sourceError(message: string): { title: string; detail: string } {
  if (/cloudflare|captcha|challenge|\b403\b|\b503\b/i.test(message)) {
    return { title: 'Verification needed', detail: 'This source is behind a Cloudflare check that FlareSolverr couldn\'t pass. Open it in WebView, solve the check there, close it and press Retry.' }
  }
  // Server errors can carry a whole stack trace; keep the readable start.
  const first = message.split(/\s+at\s+[\w$./]+\(|\n/)[0].replace(/^Exception while fetching data \([^)]*\)\s*:\s*/, '').trim()
  return { title: "Couldn't load this source", detail: first.length > 160 ? `${first.slice(0, 160)}…` : first }
}

function Notice({ title, detail, onRetry, webview }: { title: string; detail: string; onRetry?: () => void; webview?: string | null }) {
  return (
    <>
      <Empty icon="alert" tone="error" title={title} detail={detail} action={onRetry ? { label: 'Retry', onClick: onRetry } : undefined} />
      {webview && title === 'Verification needed' && (
        <div className="center pad-t-sm"><button type="button" className="btn btn--ghost" onClick={() => openWebview(webview)}><Icon name="globe" size={16} />Open in WebView</button></div>
      )}
    </>
  )
}

/** Opens the source in Suwayomi's WebView, in a new tab. */
const openWebview = (url: string) => window.open(webviewUrl(url), '_blank', 'noopener')

const langLabel = (lang: string) => (lang === 'all' ? 'Multi' : lang.toUpperCase())

function MangaCard({ m, rail }: { m: SMangaCard; rail?: boolean }) {
  const saved = !!useStore().entry(`s${m.id}`)?.inLibrary
  return (
    <Link to={`/entry/s${m.id}`} className={rail ? 'rail__item' : 'card'}>
      <div className="thumb">
        <Cover art={artFor(m.id)} title={m.title} url={assetUrl(m.thumbnailUrl)} />
        {saved && <span className="badge badge--tl badge--glass"><Icon name="check" size={11} stroke={2.6} />Saved</span>}
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
  const [exts, setExtsState] = useState<SExtension[] | null>(extCache)
  const setExts = (list: SExtension[]) => { extCache = list; setExtsState(list) }
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState<string | null>(null)
  const [limit, setLimit] = useState(PAGE_SIZE)
  const [reposOpen, setReposOpen] = useState(false)

  const load = useCallback(async (refresh = false) => {
    setError(undefined)
    try {
      setExts(refresh ? await refreshExtensions() : await getExtensions())
    } catch (e) {
      if (!extCache) setError((e as Error).message)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
        <IconButton icon="database" label="Extension repositories" onClick={() => setReposOpen(true)} />
        <IconButton icon="refresh" label="Check repositories for new extensions" onClick={async () => { await load(true); store.toast('Extension list refreshed') }} />
      </PageHead>
      {reposOpen && <ReposSheet onClose={() => setReposOpen(false)} onChanged={() => void load(true)} />}

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
        {!exts && !error && <Loading label="Loading extensions" />}
        {exts && list.length === 0 && (tab === 'installed'
          ? <Empty icon="sources" title="No extensions yet" detail="Open Available to install sources." />
          : <Empty icon="search" title="Nothing matches" detail="Try another language or name, or add an extension repository in Suwayomi." />)}
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
  const [actions, setActions] = useState(false)
  const [busy, setBusy] = useState<'update' | 'uninstall' | null>(null)
  // The source's own filters: the edited set (to reopen the sheet as it was) and what changed from the defaults.
  const [filterSet, setFilterSet] = useState<SFilter[] | null>(null)
  const [changes, setChanges] = useState<FilterChange[]>([])
  const [filtering, setFiltering] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)

  const extAction = async (action: 'update' | 'uninstall') => {
    if (!ext) return
    if (action === 'uninstall' && !window.confirm(`Uninstall ${ext.name}? Titles from it stay in your library, but can't load until it's installed again.`)) return
    setBusy(action)
    try {
      await changeExtension(ext.pkgName, action)
      extCache = null
      setActions(false)
      store.toast(action === 'update' ? `${ext.name} updated` : `${ext.name} uninstalled`)
      if (action === 'uninstall') nav.back('/sources')
      else setExt({ ...ext, hasUpdate: false })
    } catch (e) {
      store.toast((e as Error).message)
    } finally {
      setBusy(null)
    }
  }

  useEffect(() => {
    setExt(undefined); setExtError(undefined); setSourceId(undefined); setItems([]); setPage(1); setFilterSet(null); setChanges([])
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
    browseSource(sourceId, query || changes.length ? 'SEARCH' : mode, page, query || (changes.length ? '' : undefined), changes)
      .then((r) => {
        if (!alive) return
        setItems((prev) => (page === 1 ? r.mangas : [...prev, ...r.mangas]))
        setHasNext(r.hasNextPage)
      })
      .catch((e: Error) => alive && setError(e.message))
      .finally(() => alive && setLoading(false))
    return () => { alive = false }
  }, [sourceId, mode, query, page, attempt, changes])

  const reset = (fn: () => void) => { setItems([]); setPage(1); fn() }
  const submit = (e: FormEvent) => { e.preventDefault(); reset(() => setQuery(input.trim())) }

  return (
    <div className="page entry">
      <div className="entry__backdrop entry__backdrop--short" style={{ background: '#1A1A22' }} aria-hidden="true"><span style={{ background: '#FF6B5E' }} /></div>
      <div className="entry__top">
        <IconButton icon="back" label="Back" glass onClick={() => nav.back('/sources')} />
        {ext && (
          <span className="row-gap">
            {source?.isConfigurable && <IconButton icon="settings" label="Source settings" glass onClick={() => setSettingsOpen(true)} />}
            {source?.baseUrl && <IconButton icon="globe" label="Open in WebView" glass onClick={() => openWebview(source.baseUrl!)} />}
            <IconButton icon="more" label="Extension actions" glass onClick={() => setActions(true)} />
          </span>
        )}
      </div>
      <Sheet open={actions} title={ext?.name ?? 'Extension'} onClose={() => setActions(false)}>
        <div className="menu">
          {source?.baseUrl && (
            <button type="button" className="menu__row" onClick={() => { setActions(false); openWebview(source.baseUrl!) }}>
              <span className="menu__icon"><Icon name="globe" size={20} /></span>
              <span className="menu__text"><strong>Open in WebView</strong><span>Solve Cloudflare checks or log in to the site</span></span>
            </button>
          )}
          {source?.isConfigurable && (
            <button type="button" className="menu__row" onClick={() => { setActions(false); setSettingsOpen(true) }}>
              <span className="menu__icon"><Icon name="settings" size={20} /></span>
              <span className="menu__text"><strong>Source settings</strong><span>{sources.length > 1 ? `For ${langLabel(source.lang)}` : "The extension's own options"}</span></span>
            </button>
          )}
          {ext?.hasUpdate && (
            <button type="button" className="menu__row" disabled={!!busy} onClick={() => void extAction('update')}>
              <span className="menu__icon"><Icon name="refresh" size={20} /></span>
              <span className="menu__text"><strong>{busy === 'update' ? 'Updating…' : 'Update'}</strong><span>A newer version is available</span></span>
            </button>
          )}
          <button type="button" className="menu__row" disabled={!!busy} onClick={() => void extAction('uninstall')}>
            <span className="menu__icon"><Icon name="trash" size={20} /></span>
            <span className="menu__text"><strong>{busy === 'uninstall' ? 'Uninstalling…' : 'Uninstall'}</strong><span>Titles in your library keep their progress</span></span>
          </button>
        </div>
      </Sheet>
      {settingsOpen && source && <SourceSettings sourceId={source.id} title={source.displayName} onClose={() => { setSettingsOpen(false); reset(() => setAttempt((n) => n + 1)) }} />}
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
          {sources.map((s: SSource) => <Chip key={s.id} on={s.id === sourceId} onClick={() => reset(() => { setSourceId(s.id); setFilterSet(null); setChanges([]) })}>{langLabel(s.lang)}</Chip>)}
        </div>
      )}

      <form className="pad-x pad-t-sm row-gap" onSubmit={submit}>
        <label className="field grow">
          <Icon name="search" size={18} />
          <input value={input} onChange={(e) => setInput(e.target.value)} placeholder={`Search ${ext?.name ?? 'this source'}`} aria-label="Search this source" enterKeyHint="search" />
        </label>
        {sourceId && <IconButton icon="sliders" label="Source filters" badge={changes.length || undefined} active={changes.length > 0} onClick={() => setFiltering(true)} />}
      </form>
      {filtering && sourceId && <SourceFilters sourceId={sourceId} value={filterSet} onClose={() => setFiltering(false)}
        onApply={(set, ch) => reset(() => { setFilterSet(set); setChanges(ch) })} />}

      <div className="underline-tabs pad-x" role="tablist">
        {query || changes.length ? (
          <>
            {query && <button type="button" role="tab" aria-selected className="is-on" onClick={() => { setInput(''); reset(() => setQuery('')) }}>“{query}” <Icon name="x" size={14} /></button>}
            {changes.length > 0 && <button type="button" role="tab" aria-selected className="is-on" onClick={() => reset(() => { setFilterSet(null); setChanges([]) })}>Filtered · {changes.length} <Icon name="x" size={14} /></button>}
          </>
        ) : (
          <>
            <button type="button" role="tab" aria-selected={mode === 'POPULAR'} className={mode === 'POPULAR' ? 'is-on' : ''} onClick={() => reset(() => setMode('POPULAR'))}>Popular</button>
            {source?.supportsLatest && <button type="button" role="tab" aria-selected={mode === 'LATEST'} className={mode === 'LATEST' ? 'is-on' : ''} onClick={() => reset(() => setMode('LATEST'))}>Latest</button>}
          </>
        )}
      </div>

      {error && <div className="pad-x pad-t"><Notice {...sourceError(error)} webview={source?.baseUrl} onRetry={() => setAttempt((n) => n + 1)} /></div>}
      <div className="grid3 pad-x pad-t">
        {items.map((m, i) => <MangaCard key={`${m.id}-${i}`} m={m} />)}
      </div>
      {loading && <div className="pad-x pad-t"><Loading label={query ? `Searching for “${query}”` : 'Loading titles'} count={items.length ? 3 : 6} /></div>}
      {!loading && !error && items.length === 0 && sourceId && (
        <div className="pad-x pad-t"><Empty icon="search" title="No results" detail={query ? `Nothing for “${query}” on this source. Try fewer words.` : 'This source returned no titles.'} /></div>
      )}
      {!loading && hasNext && <div className="center pad-t"><button type="button" className="btn btn--ghost" onClick={() => setPage((p) => p + 1)}>Load more</button></div>}
      {store.server.status === 'error' && store.server.where === 'server' && <div className="pad-x pad-t"><Banner icon="alert" tone="error">{store.server.error}</Banner></div>}
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
  const [query, setQuery] = useState(lastSearch.query)
  const [debounced, setDebounced] = useState(lastSearch.query)
  const [sources, setSources] = useState<SearchSource[] | null>(sourceCache)
  const [error, setError] = useState<string>()
  const [results, setResults] = useState<Record<string, SearchResult>>(lastSearch.results)
  const run = useRef(0)
  // The search shown when the screen opens again is the one left behind, not run again.
  const restored = useRef(lastSearch.query)
  useEffect(() => { lastSearch = { query: debounced, results } }, [debounced, results])

  useEffect(() => {
    getSources().then((list) => { sourceCache = list; setSources(list) }).catch((e: Error) => { if (!sourceCache) setError(e.message) })
  }, [])
  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 400)
    return () => clearTimeout(t)
  }, [query])

  // An extension's "All" source covers every language in one search; only extensions without one
  // fall back to searching each language, so every result comes up.
  const groups = useMemo(() => {
    const map = new Map<string, SearchGroup>()
    for (const s of sources ?? []) {
      const key = s.extension?.pkgName ?? s.id
      const g = map.get(key) ?? { key, pkg: s.extension?.pkgName ?? '', name: s.name, iconUrl: s.iconUrl, sources: [] }
      g.sources.push(s)
      map.set(key, g)
    }
    const pick = (list: SearchSource[]) => {
      const of = (lang: string) => list.filter((s) => s.lang === lang)
      return of('all').length ? of('all') : byLanguage(list)
    }
    return [...map.values()].map((g) => ({ ...g, sources: pick(g.sources) })).filter((g) => g.sources.length)
  }, [sources])
  const groupsKey = groups.map((g) => g.sources.map((s) => s.id).join()).join('|')

  // One request per extension first so each section fills in quickly; extra languages (for
  // extensions without an "All" source) follow and are merged in without duplicates. Four at a time.
  useEffect(() => {
    if (!debounced || !groups.length) return
    const finished = Object.values(results).length > 0 && Object.values(results).every((r) => r.done >= r.total)
    if (restored.current && restored.current === debounced && finished) { restored.current = ''; return }
    restored.current = ''
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

      {error && <div className="pad-x pad-t"><Notice title="Couldn't load sources" detail={error} /></div>}
      {!debounced ? (
        <div className="pad-x pad-t">
          {!sources && !error ? <Loading label="Loading sources" shape="rows" count={2} />
            : sources && !sources.length ? <Empty icon="sources" title="No sources yet" detail="Install an extension in Sources to search titles." />
            : <Empty icon="search" title="Search everywhere" detail={`Your library and ${groups.length} source${groups.length === 1 ? '' : 's'}, in every language.`} />}
        </div>
      ) : (
        <>
          <section className="section pad-x">
            <div className="section-head">
              <h2 className="h3"><Icon name="library" size={18} /> In your library</h2>
              <span className="card-meta">{local.length} match{local.length === 1 ? '' : 'es'}</span>
            </div>
            {local.length === 0 ? <Empty compact icon="library" title="Not in your library" detail="Results from your sources are below." /> : (
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

          {(() => {
            const pending = groups.filter((g) => resultFor(g).done < resultFor(g).total).length
            const found = groups.reduce((n, g) => n + resultFor(g).items.length, 0)
            if (pending) return <div className="pad-x pad-t"><Banner tone="busy">Searching {pending} of {groups.length} source{groups.length === 1 ? '' : 's'}… {found ? `${found} found so far` : ''}</Banner></div>
            if (!found) return <div className="pad-x pad-t"><Empty icon="search" title={`No results for “${debounced}”`} detail="No source has a title by that name. Try fewer or different words." /></div>
            return null
          })()}
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
                {!r.items.length && searching && <div className="pad-x"><Loading label={`Searching ${g.name}`} shape="rail" /></div>}
                {failed && <div className="pad-x"><Notice {...sourceError(r.errors[0] ?? '')} webview={g.sources[0]?.baseUrl} /></div>}
                {r.items.length > 0 && <div className="rail">{r.items.map((m) => <MangaCard key={m.id} m={m} rail />)}</div>}
              </section>
            )
          })}
        </>
      )}
    </div>
  )
}

/** Extension repositories on the server: add one by its index address, or remove one. */
function ReposSheet({ onClose, onChanged }: { onClose: () => void; onChanged: () => void }) {
  const store = useStore()
  const [list, setList] = useState<string[] | null>(null)
  const [error, setError] = useState<string>()
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => { getRepos().then(setList).catch((e: Error) => setError(e.message)) }, [])

  const save = async (next: string[], message: string) => {
    setBusy(true)
    try {
      setList(await setRepos(next))
      store.toast(message)
      onChanged()
    } catch (e) {
      store.toast(`Couldn't save: ${(e as Error).message}`)
    } finally {
      setBusy(false)
    }
  }
  const add = (e: FormEvent) => {
    e.preventDefault()
    let url = input.trim()
    if (!url || !list) return
    // A GitHub repo page ("github.com/owner/repo") becomes its index the way Mihon-style repos publish it.
    const gh = url.match(/^(?:https?:\/\/)?github\.com\/([^/]+)\/([^/]+?)\/?$/)
    if (gh) url = `https://github.com/${gh[1]}/${gh[2]}/raw/repo/index.min.json`
    if (!/^https?:\/\//.test(url)) url = `https://${url}`
    if (list.includes(url)) { store.toast('Already added'); return }
    setInput('')
    void save([...list, url], 'Repository added · extension list refreshed')
  }
  const name = (u: string) => u.replace(/^https?:\/\//, '').replace(/\/raw\/repo\/index(\.min)?\.(json|pb)$/, '').replace(/^github\.com\//, '')

  return (
    <Sheet open title="Extension repositories" onClose={onClose}>
      <p className="hint">The server installs extensions from these. Add a repository's index address (or its GitHub page).</p>
      {error && <Empty compact tone="error" icon="alert" title="Couldn't load repositories" detail={error} />}
      {!list && !error && <Loading label="Loading repositories" shape="rows" count={2} />}
      {list && !list.length && <Empty compact icon="database" title="No repositories" detail="Add one to see extensions to install." />}
      <div className="check-list">
        {list?.map((u) => (
          <div key={u} className="check-row">
            <span className="check-row__name check-row__name--stack grow"><strong className="ellipsis">{name(u)}</strong><span className="card-meta ellipsis">{u}</span></span>
            <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove ${name(u)}`} disabled={busy}
              onClick={() => { if (window.confirm(`Remove ${name(u)}? Installed extensions stay installed.`)) void save(list.filter((x) => x !== u), 'Repository removed') }}>
              <Icon name="trash" size={16} />
            </button>
          </div>
        ))}
      </div>
      <form className="row-gap pad-t" onSubmit={add}>
        <label className="field grow"><Icon name="plus" size={18} /><input value={input} onChange={(e) => setInput(e.target.value)} placeholder="https://…/index.min.json" aria-label="Repository address" inputMode="url" autoCapitalize="off" /></label>
        <button type="submit" className="btn btn--accent" disabled={!input.trim() || busy || !list}>Add</button>
      </form>
    </Sheet>
  )
}
