import { useState } from 'react'
import { Empty } from '../components/Status'
import { useSettings } from '../data/settings'
import { RemoteSources } from './Remote'
import { TLink as Link } from '../components/Nav'
import { SourceIcon } from '../components/Art'
import { IconButton, PageHead } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { useStore } from '../data/store'
import type { Source } from '../data/types'

const LANGS = ['All', 'EN', 'Multi', 'JA', 'ES', 'ID']

function SampleSources() {
  const store = useStore()
  const [tab, setTab] = useState<'installed' | 'available'>('installed')
  const [query, setQuery] = useState('')
  const [lang, setLang] = useState('All')

  const installed = store.sources.filter((s) => s.installed)
  const available = store.sources.filter((s) => !s.installed)
  const updates = installed.filter((s) => s.update)
  const match = (s: Source) =>
    (!query || s.name.toLowerCase().includes(query.toLowerCase())) && (lang === 'All' || s.lang === lang || s.langs.includes(lang))
  const pinned = installed.filter((s) => s.pinned && match(s))
  const rest = installed.filter((s) => !s.pinned && match(s))

  return (
    <div className="page">
      <PageHead kicker={`${installed.length} installed · 1 repository`} title="Sources">
        <IconButton icon="database" label="Repositories" onClick={() => store.toast('Repository settings come later')} />
      </PageHead>

      <div className="pad-x pad-t">
        <div className="segmented segmented--lg" role="tablist">
          <button type="button" role="tab" aria-selected={tab === 'installed'} className={tab === 'installed' ? 'is-on' : ''} onClick={() => setTab('installed')}>Installed · {installed.length}</button>
          <button type="button" role="tab" aria-selected={tab === 'available'} className={tab === 'available' ? 'is-on' : ''} onClick={() => setTab('available')}>Available · {available.length}</button>
        </div>
      </div>

      {tab === 'installed' && updates.length > 0 && (
        <div className="pad-x pad-t-sm">
          <div className="banner">
            <Icon name="refresh" />
            <span className="grow">{updates.length} update{updates.length === 1 ? '' : 's'} available</span>
            <button type="button" className="btn btn--accent btn--sm" onClick={() => { store.updateAll(); store.toast('Extensions updated') }}>Update all</button>
          </div>
        </div>
      )}

      <div className="pad-x pad-t-sm row-gap">
        <label className="field grow">
          <Icon name="search" size={18} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search extensions" aria-label="Search extensions" />
        </label>
        <label className="select-box">
          <select value={lang} onChange={(e) => setLang(e.target.value)} aria-label="Language">
            {LANGS.map((l) => <option key={l} value={l}>{l === 'All' ? 'All languages' : l}</option>)}
          </select>
          <Icon name="chevronDown" size={14} stroke={2} />
        </label>
      </div>

      {tab === 'installed' ? (
        <>
          {pinned.length > 0 && (
            <section className="section pad-x">
              <div className="label label--flush">Pinned</div>
              <div className="grid2">
                {pinned.map((s) => (
                  <Link key={s.id} to={`/sources/${s.id}`} className="tile tile--big">
                    <span className="tile__glow" style={{ background: s.glow }} aria-hidden="true" />
                    <span className="split">
                      <SourceIcon letter={s.letter} color={s.color} size={50} />
                      {s.update && <span className="tag tag--accent">Update</span>}
                    </span>
                    <span className="tile__title">{s.name}</span>
                    <span className="card-meta">{s.lang} · {s.langs.length} languages</span>
                    <span className="tile__cta">Browse <Icon name="arrowRight" size={14} stroke={2.2} /></span>
                  </Link>
                ))}
              </div>
            </section>
          )}
          <section className="section pad-x">
            <div className="label label--flush">Installed</div>
            <div className="grid3">
              {rest.map((s) => (
                <Link key={s.id} to={`/sources/${s.id}`} className="tile">
                  <span className="split">
                    <SourceIcon letter={s.letter} color={s.color} size={42} />
                    <span className="row-gap row-gap--sm">
                      {s.warn && <span className="warn-icon"><Icon name={s.warn === 'cloudflare' ? 'shield' : 'alert'} size={16} label={s.warn === 'cloudflare' ? 'Needs verification' : 'Failing'} /></span>}
                      {s.update && <span className="update-dot" role="img" aria-label="Update available" />}
                    </span>
                  </span>
                  <span className="tile__name">{s.name}</span>
                  <span className="card-meta">{s.warn === 'error' ? 'Failing · tap for details' : `${s.lang} · v${s.version}`}</span>
                </Link>
              ))}
            </div>
            {rest.length === 0 && pinned.length === 0 && <Empty icon="search" title="No extensions match" detail="Try another name." />}
          </section>
        </>
      ) : (
        <section className="section pad-x">
          <div className="label label--flush">Keiyoushi</div>
          <div className="grid3">
            {available.filter(match).map((s) => (
              <div key={s.id} className="tile">
                <span className="split">
                  <SourceIcon letter={s.letter} color={s.color} size={42} />
                  {s.nsfw && <span className="tag">18+</span>}
                </span>
                <span className="tile__name">{s.name}</span>
                <span className="card-meta">{s.lang} · v{s.version}</span>
                <button type="button" className="btn btn--ghost btn--sm btn--block" onClick={() => { store.toggleInstall(s.id); store.toast(`${s.name} installed`) }}>
                  <Icon name="download" size={14} stroke={2} /> Install
                </button>
              </div>
            ))}
          </div>
          {available.filter(match).length === 0 && <Empty icon="check" tone="done" title="Everything is installed" />}
        </section>
      )}

      <section className="section pad-x">
        <div className="repo">
          <span className="repo__icon"><Icon name="database" /></span>
          <span className="grow">
            <strong>Keiyoushi</strong>
            <span className="card-meta">1,240 extensions · checked today</span>
          </span>
          <button type="button" className="btn btn--ghost btn--sm" onClick={() => store.toast('Adding repositories comes later')}>Add repo</button>
        </div>
      </section>
    </div>
  )
}

/** Sample data until a Suwayomi server is set in Settings. */
export default function Sources() {
  const { serverUrl } = useSettings()
  return serverUrl ? <RemoteSources /> : <SampleSources />
}
