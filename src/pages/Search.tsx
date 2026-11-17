import { useEffect, useMemo, useState } from 'react'
import { TLink as Link } from '../components/Nav'
import { Cover, SourceIcon } from '../components/Art'
import { Chip, PageHead } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { catalogFor, RECENT_SEARCHES } from '../data/mock'
import { useStore, visibleChapters } from '../data/store'

type SourceState = 'loading' | 'done' | 'cloudflare'

export default function Search() {
  const store = useStore()
  const [query, setQuery] = useState('crown')
  const [debounced, setDebounced] = useState('crown')
  const [scope, setScope] = useState<'all' | 'pinned'>('all')
  const [english, setEnglish] = useState(false)
  const [hideNsfw, setHideNsfw] = useState(true)
  const [states, setStates] = useState<Record<string, SourceState>>({})

  const sources = store.sources.filter((s) => s.installed && (scope === 'all' || s.pinned) && (!english || s.langs.includes('EN')) && (!hideNsfw || !s.nsfw))

  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 300)
    return () => clearTimeout(t)
  }, [query])

  // Simulates each source answering at its own pace; Asura sits behind a Cloudflare check.
  useEffect(() => {
    if (!debounced) return
    const timers: ReturnType<typeof setTimeout>[] = []
    setStates(Object.fromEntries(sources.map((s) => [s.id, 'loading' as SourceState])))
    sources.forEach((s, i) => {
      const delay = s.id === 'weebcentral' ? 2600 : 350 + i * 260
      timers.push(setTimeout(() => setStates((st) => ({ ...st, [s.id]: s.warn === 'cloudflare' ? 'cloudflare' : 'done' })), delay))
    })
    return () => timers.forEach(clearTimeout)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debounced, sources.map((s) => s.id + s.warn).join()])

  const q = debounced.toLowerCase()
  const local = useMemo(() => store.entries.filter((e) => e.inLibrary && q && e.title.toLowerCase().includes(q)), [store.entries, q])
  const results = (id: string) => catalogFor(id).filter((c) => c.title.toLowerCase().includes(q))
  const inLibrary = (entryId?: string) => !!entryId && !!store.entry(entryId)?.inLibrary

  const solve = (id: string) => {
    setStates((st) => ({ ...st, [id]: 'loading' }))
    setTimeout(() => { store.clearWarning(id); setStates((st) => ({ ...st, [id]: 'done' })); store.toast('Verified — results loaded') }, 1400)
  }

  return (
    <div className="page">
      <PageHead kicker={`${sources.length} sources · your library`} title="Search" />
      <div className="pad-x pad-t">
        <label className="field field--lg field--focus">
          <Icon name="search" size={20} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search titles everywhere" aria-label="Search all sources and your library" enterKeyHint="search" />
          {query && <button type="button" className="icon-btn icon-btn--sm" aria-label="Clear search" onClick={() => setQuery('')}><Icon name="x" size={16} /></button>}
        </label>
      </div>
      <div className="chips pad-x pad-t-sm">
        <Chip on={scope === 'all'} onClick={() => setScope('all')}>All sources · {store.sources.filter((s) => s.installed).length}</Chip>
        <Chip on={scope === 'pinned'} onClick={() => setScope('pinned')}>Pinned</Chip>
        <Chip on={english} onClick={() => setEnglish((x) => !x)}>English</Chip>
        <Chip on={hideNsfw} onClick={() => setHideNsfw((x) => !x)}>Hide 18+</Chip>
      </div>

      {!debounced ? (
        <section className="section pad-x">
          <div className="label label--flush">Recent</div>
          <div className="chips wrap">
            {RECENT_SEARCHES.map((r) => <Chip key={r} onClick={() => setQuery(r)}>{r}</Chip>)}
          </div>
        </section>
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
                    <Cover art={e.art} title={e.title} className="tile__cover" />
                    <span className="grow">
                      <span className="card-title card-title--2">{e.title}</span>
                      <span className="card-meta">
                        {store.children(e.id).length ? `Collection · ${e.sources.length} sources` : e.parentId ? `In ${store.entry(e.parentId)?.title}` : `${visibleChapters(e).length} chapters`}
                      </span>
                    </span>
                  </Link>
                ))}
              </div>
            )}
          </section>

          {sources.map((s) => {
            const state = states[s.id] ?? 'loading'
            const list = state === 'done' ? results(s.id) : []
            return (
              <section key={s.id} className="section">
                <Link to={`/sources/${s.id}`} className="section-head pad-x link-row">
                  <h2 className="h3"><SourceIcon letter={s.letter} color={s.color} size={28} />{s.name}</h2>
                  <span className="card-meta">{state === 'loading' ? 'Searching…' : state === 'done' ? `${list.length} results` : ''}</span>
                  <Icon name="chevronRight" size={18} />
                </Link>
                {state === 'loading' && (
                  <div className="rail" aria-hidden="true">{[0, 1, 2].map((i) => <div key={i} className="rail__item skeleton" />)}</div>
                )}
                {state === 'cloudflare' && (
                  <div className="pad-x">
                    <div className="notice">
                      <span className="notice__icon"><Icon name="shield" /></span>
                      <span className="grow">
                        <strong>Verification needed</strong>
                        <span className="card-meta">{s.name} is behind a Cloudflare check</span>
                      </span>
                      <button type="button" className="btn btn--light btn--sm" onClick={() => solve(s.id)}>Solve</button>
                    </div>
                  </div>
                )}
                {state === 'done' && (list.length === 0 ? <p className="hint pad-x">No results.</p> : (
                  <div className="rail">
                    {list.map((r) => (
                      <Link key={r.id} to={r.entryId ? `/entry/${r.entryId}` : `/sources/${s.id}`} className="rail__item">
                        <div className="thumb">
                          <Cover art={r.art} title={r.title} />
                          {inLibrary(r.entryId) && <span className="badge badge--tl badge--glass"><Icon name="check" size={11} stroke={2.6} />Saved</span>}
                        </div>
                        <div className="card-title card-title--2">{r.title}</div>
                      </Link>
                    ))}
                  </div>
                ))}
              </section>
            )
          })}
        </>
      )}
    </div>
  )
}
