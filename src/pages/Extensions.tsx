import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Extension, img, listExtensions, refreshExtensions, setInstalled } from '../api'

type Tab = 'installed' | 'available'

export default function Extensions() {
  const [exts, setExts] = useState<Extension[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [tab, setTab] = useState<Tab>('installed')
  const [q, setQ] = useState('')
  const [busy, setBusy] = useState<string | null>(null)
  const [refreshing, setRefreshing] = useState(false)

  const load = () => listExtensions().then(setExts).catch((e) => setError(e.message))
  useEffect(() => {
    load()
  }, [])

  const refresh = async () => {
    setRefreshing(true)
    setError(null)
    try {
      setExts(await refreshExtensions())
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setRefreshing(false)
    }
  }

  const toggle = async (ext: Extension) => {
    setBusy(ext.pkgName)
    try {
      await setInstalled(ext.pkgName, !ext.isInstalled)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(null)
    }
  }

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase()
    return (exts ?? [])
      .filter((e) => (tab === 'installed' ? e.isInstalled : !e.isInstalled))
      .filter((e) => !needle || e.name.toLowerCase().includes(needle))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [exts, tab, q])

  return (
    <div className="page">
      <header className="bar">
        <h1>Extensions</h1>
        <button className="ghost" onClick={refresh} disabled={refreshing}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </header>

      <div className="tabs">
        {(['installed', 'available'] as Tab[]).map((t) => (
          <button key={t} className={tab === t ? 'tab on' : 'tab'} onClick={() => setTab(t)}>
            {t === 'installed' ? 'Installed' : 'Available'}
          </button>
        ))}
      </div>
      <input className="search" placeholder="Search extensions" value={q} onChange={(e) => setQ(e.target.value)} />

      {error && <p className="error">{error}</p>}
      {!exts && !error && <p className="muted">Loading…</p>}
      {exts && shown.length === 0 && (
        <p className="muted">
          {tab === 'installed' ? 'No extensions installed. Check the Available tab.' : 'Nothing here. Tap Refresh.'}
        </p>
      )}

      <ul className="list">
        {shown.map((ext) => {
          const body = (
            <>
              <img className="icon" src={img(ext.iconUrl)} alt="" loading="lazy" />
              <div className="meta">
                <div className="name">
                  {ext.name}
                  {ext.isNsfw && <span className="badge">18+</span>}
                  {ext.hasUpdate && <span className="badge accent">Update</span>}
                </div>
                <div className="sub">
                  {ext.lang.toUpperCase()} · v{ext.versionName}
                </div>
              </div>
            </>
          )
          return (
            <li key={ext.pkgName} className="row">
              {ext.isInstalled ? (
                <Link to={`/extension/${encodeURIComponent(ext.pkgName)}`} className="rowlink">
                  {body}
                </Link>
              ) : (
                <div className="rowlink">{body}</div>
              )}
              <button className="ghost small" onClick={() => toggle(ext)} disabled={busy === ext.pkgName}>
                {busy === ext.pkgName ? '…' : ext.isInstalled ? 'Remove' : 'Install'}
              </button>
            </li>
          )
        })}
      </ul>
    </div>
  )
}
