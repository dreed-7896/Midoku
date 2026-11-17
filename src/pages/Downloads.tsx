import { useEffect, useMemo, useState } from 'react'
import { Cover } from '../components/Art'
import { IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { useNav } from '../components/Nav'
import { Empty } from '../components/Status'
import { cancel, dismissFailed, jobFor, removeAllDownloads, removeDownload, retry, savedBytes, useDownloads, type SavedChapter } from '../data/downloads'
import { useStore } from '../data/store'

export const mb = (bytes: number) => (bytes < 1e6 ? `${Math.round(bytes / 1e3)} KB` : `${(bytes / 1e6).toFixed(bytes < 1e8 ? 1 : 0)} MB`)

/** Chapters saved on this device, by title, with what's downloading now. */
export default function Downloads() {
  const store = useStore()
  const nav = useNav()
  const d = useDownloads()
  const [open, setOpen] = useState<Record<string, boolean>>({})
  const [usage, setUsage] = useState<{ used: number; quota: number }>()
  const count = Object.keys(d.saved).length
  useEffect(() => {
    navigator.storage?.estimate?.().then((e) => setUsage({ used: e.usage ?? 0, quota: e.quota ?? 0 })).catch(() => {})
  }, [count])

  const titles = useMemo(() => {
    const map = new Map<string, { entryId: string; title: string; bytes: number; chapters: [string, SavedChapter][] }>()
    for (const [key, s] of Object.entries(d.saved)) {
      const t = map.get(s.entryId) ?? { entryId: s.entryId, title: s.title, bytes: 0, chapters: [] }
      t.bytes += s.bytes
      t.chapters.push([key, s])
      map.set(s.entryId, t)
    }
    for (const t of map.values()) t.chapters.sort((a, b) => a[1].label.localeCompare(b[1].label, undefined, { numeric: true }))
    return [...map.values()].sort((a, b) => b.bytes - a.bytes)
  }, [d.saved])
  const failed = Object.entries(d.failed)

  const removeTitle = async (t: (typeof titles)[number]) => {
    if (!window.confirm(`Remove ${t.chapters.length} downloaded chapter${t.chapters.length === 1 ? '' : 's'} of ${t.title}?`)) return
    for (const [key] of t.chapters) await removeDownload(key)
    store.toast(`Removed downloads of ${t.title}`)
  }
  const removeAll = async () => {
    if (!window.confirm(`Remove all ${count} downloaded chapters from this device?`)) return
    await removeAllDownloads()
    store.toast('Downloads removed')
  }

  return (
    <div className="page">
      <div className="entry__top">
        <IconButton icon="back" label="Back" onClick={() => nav.back('/settings')} />
        {count > 0 && <IconButton icon="trash" label="Remove all downloads" onClick={() => void removeAll()} />}
      </div>
      <header className="pad-x pad-t">
        <h1 className="h1">Downloads</h1>
        <div className="card-meta pad-t-sm">
          {count} chapter{count === 1 ? '' : 's'} · {mb(savedBytes())}{usage ? ` · ${mb(usage.used)} used on this device of ${mb(usage.quota)}` : ''}
        </div>
      </header>

      {d.pending.length > 0 && (
        <section className="section section--tight pad-x">
          <div className="label label--flush">Downloading · {d.pending.length}</div>
          <div className="check-list">
            {d.pending.map((j) => {
              const now = d.active?.key === j.key
              return (
                <div key={j.key} className="order-row history-row">
                  <span className="check-row__name check-row__name--stack grow">
                    <strong className="ellipsis">{j.title}</strong>
                    <span className="card-meta">{j.label} · {now ? `${Math.round((d.active?.progress ?? 0) * 100)}%` : 'Waiting'}</span>
                    {now && <span className="bar"><span style={{ width: `${(d.active?.progress ?? 0) * 100}%` }} /></span>}
                  </span>
                  {!now && <button type="button" className="icon-btn icon-btn--sm" aria-label={`Cancel ${j.label}`} onClick={() => cancel(j.key)}><Icon name="x" size={16} /></button>}
                </div>
              )
            })}
          </div>
        </section>
      )}

      {failed.length > 0 && (
        <section className="section section--tight pad-x">
          <div className="label label--flush">Failed · {failed.length}</div>
          <div className="check-list">
            {failed.map(([key, message]) => {
              const j = jobFor(key)
              return (
                <div key={key} className="order-row history-row">
                  <span className="check-row__name check-row__name--stack grow">
                    <strong className="ellipsis">{j?.title ?? 'Chapter'}</strong>
                    <span className="card-meta ellipsis">{j?.label ? `${j.label} · ` : ''}{message}</span>
                  </span>
                  {j && <button type="button" className="icon-btn icon-btn--sm" aria-label="Try again" onClick={() => retry(key)}><Icon name="refresh" size={16} /></button>}
                  <button type="button" className="icon-btn icon-btn--sm" aria-label="Dismiss" onClick={() => dismissFailed(key)}><Icon name="x" size={16} /></button>
                </div>
              )
            })}
          </div>
        </section>
      )}

      {!count && !d.pending.length && !failed.length && (
        <div className="pad-x pad-t"><Empty icon="download" title="Nothing downloaded" detail="Long-press chapters on a title page (or use Select) to save them for offline reading." /></div>
      )}

      {titles.length > 0 && (
        <section className="section section--tight pad-x">
          <div className="label label--flush">On this device</div>
          <div className="check-list">
            {titles.map((t) => {
              const e = store.entry(t.entryId)
              const expanded = !!open[t.entryId]
              return (
                <div key={t.entryId} className="dl-title">
                  <div className="order-row history-row">
                    <button type="button" className="plain-btn order-row__cover" aria-label={`Open ${t.title}`} onClick={() => nav.go(`/entry/${t.entryId}`)}>
                      {e ? <Cover art={e.art} title={e.title} url={e.coverUrl} /> : <span className="cover" />}
                    </button>
                    <button type="button" className="check-row__name check-row__name--stack grow plain-btn" aria-expanded={expanded} onClick={() => setOpen((o) => ({ ...o, [t.entryId]: !expanded }))}>
                      <strong className="ellipsis">{e?.title ?? t.title}</strong>
                      <span className="card-meta">{t.chapters.length} chapter{t.chapters.length === 1 ? '' : 's'} · {mb(t.bytes)}</span>
                    </button>
                    <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove downloads of ${t.title}`} onClick={() => void removeTitle(t)}><Icon name="trash" size={16} /></button>
                    <button type="button" className="icon-btn icon-btn--sm" aria-label={expanded ? 'Hide chapters' : 'Show chapters'} onClick={() => setOpen((o) => ({ ...o, [t.entryId]: !expanded }))}>
                      <Icon name={expanded ? 'chevronDown' : 'chevronRight'} size={16} />
                    </button>
                  </div>
                  {expanded && t.chapters.map(([key, s]) => (
                    <div key={key} className="order-row dl-chapter">
                      <span className="check-row__name check-row__name--stack grow">
                        <strong className="ellipsis">{s.label}</strong>
                        <span className="card-meta">{s.pages.length} pages · {mb(s.bytes)}</span>
                      </span>
                      <button type="button" className="icon-btn icon-btn--sm" aria-label={`Remove ${s.label}`} onClick={() => void removeDownload(key)}><Icon name="trash" size={16} /></button>
                    </div>
                  ))}
                </div>
              )
            })}
          </div>
        </section>
      )}
    </div>
  )
}
