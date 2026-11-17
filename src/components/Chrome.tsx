import { ReactNode, useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { NavLink, useLocation } from 'react-router-dom'
import { resumeChapter, useStore } from '../data/store'
import { Cover } from './Art'
import { Icon, IconName } from './Icon'
import { currentScroller, TLink, useNav } from './Nav'
import { restartToUpdate, useUpdateReady } from '../data/update'

const TABS: { to: string; label: string; icon: IconName }[] = [
  { to: '/', label: 'Home', icon: 'home' },
  { to: '/library', label: 'Library', icon: 'library' },
  { to: '/search', label: 'Search', icon: 'search' },
  { to: '/sources', label: 'Sources', icon: 'sources' },
]

export function TabBar() {
  const nav = useNav()
  const { pathname } = useLocation()
  return (
    <nav className="tabbar" aria-label="Main">
      {TABS.map((t) => (
        <NavLink key={t.to} to={t.to} end={t.to === '/'} className={({ isActive }) => `tabbar__item${isActive ? ' is-active' : ''}`}
          onClick={(e) => {
            e.preventDefault()
            if (pathname === t.to) currentScroller()?.scrollTo({ top: 0, behavior: 'smooth' })
            else nav.go(t.to, { tab: true })
          }}>
          <Icon name={t.icon} size={22} />
          <span>{t.label}</span>
        </NavLink>
      ))}
    </nav>
  )
}

/** Floating "continue reading" card above the tab bar. Dismissable; it comes back after the next reading session. */
export function MiniPlayer() {
  const { entries, miniHidden, dismissMini } = useStore()
  const nav = useNav()
  const { pathname } = useLocation()
  const current = [...entries].filter((e) => e.inLibrary && e.lastReadAgo !== undefined && resumeChapter(e))
    .sort((a, b) => (a.lastReadAgo ?? 0) - (b.lastReadAgo ?? 0))[0]
  if (!current || miniHidden || pathname === '/' || pathname.startsWith('/entry/') || pathname === '/settings') return null
  const ch = resumeChapter(current)!
  const pct = ch.pages ? Math.round((ch.page / ch.pages) * 100) : 0
  return (
    <div className="mini" style={{ background: current.art.c1 }}>
      <TLink to={`/entry/${current.id}`} className="mini__main">
        <Cover art={current.art} title={current.title} url={current.coverUrl} className="mini__cover" />
        <span className="mini__text">
          <span className="mini__title">{current.title}</span>
          <span className="mini__sub">{ch.label} · page {Math.max(ch.page, 1)} of {ch.pages}</span>
        </span>
      </TLink>
      <button type="button" className="mini__play" aria-label={`Resume ${current.title}`} onClick={() => nav.go(`/read/${current.id}/${ch.id}`)}>
        <Icon name="play" size={16} />
      </button>
      <button type="button" className="mini__close" aria-label="Dismiss" onClick={dismissMini}>
        <Icon name="x" size={16} />
      </button>
      <span className="mini__progress" style={{ width: `${pct}%` }} />
    </div>
  )
}

/** Shown when a new deploy has been downloaded; restarting switches to it. */
export function UpdateCard() {
  const ready = useUpdateReady()
  const [hidden, setHidden] = useState(false)
  if (!ready || hidden) return null
  return (
    <div className="update" role="status">
      <span className="update__icon"><Icon name="refresh" size={18} /></span>
      <span className="update__text"><strong>New version available</strong><span>Restart to update</span></span>
      <button type="button" className="btn btn--accent btn--sm" onClick={restartToUpdate}>Restart</button>
      <button type="button" className="mini__close" aria-label="Later" onClick={() => setHidden(true)}><Icon name="x" size={16} /></button>
    </div>
  )
}

/** Loading and error state of the server library; nothing when showing sample data or when ready. */
export function ServerStatus() {
  const { server } = useStore()
  const nav = useNav()
  if (server.status === 'loading') return <p className="hint pad-x pad-t">Loading your library from Suwayomi…</p>
  if (server.status !== 'error') return null
  return (
    <div className="pad-x pad-t">
      <div className="notice">
        <span className="notice__icon"><Icon name="alert" /></span>
        <span className="grow"><strong>Can't reach your server</strong><span className="card-meta card-meta--wrap">{server.error}</span></span>
        <button type="button" className="btn btn--light btn--sm" onClick={() => nav.go('/settings')}>Settings</button>
      </div>
    </div>
  )
}

export function Toast() {
  const { toastMessage } = useStore()
  return <div className={`toast${toastMessage ? ' is-on' : ''}`} role="status" aria-live="polite">{toastMessage}</div>
}

export function PageHead({ kicker, title, children }: { kicker?: string; title: string; children?: ReactNode }) {
  return (
    <header className="page-head">
      <div>
        {kicker && <div className="kicker">{kicker}</div>}
        <h1 className="h1">{title}</h1>
      </div>
      {children && <div className="page-head__actions">{children}</div>}
    </header>
  )
}

export function IconButton({ icon, label, onClick, badge, glass, active }: {
  icon: IconName; label: string; onClick?: () => void; badge?: string | number; glass?: boolean; active?: boolean
}) {
  return (
    <button type="button" className={`icon-btn${glass ? ' icon-btn--glass' : ''}${active ? ' is-active' : ''}`} aria-label={label} onClick={onClick}>
      <Icon name={icon} />
      {badge !== undefined && <span className="icon-btn__badge">{badge}</span>}
    </button>
  )
}

export function Sheet({ open, title, onClose, children }: { open: boolean; title: string; onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : ''
    return () => { document.body.style.overflow = '' }
  }, [open])
  if (!open) return null
  // Rendered at the top level so it sits above the tab bar, not inside the screen's layer.
  return createPortal(
    <div className="sheet-wrap">
      <button type="button" className="sheet-scrim" aria-label="Close" onClick={onClose} />
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title}>
        <div className="sheet__head">
          <h2 className="h2">{title}</h2>
          <button type="button" className="icon-btn" aria-label="Close" onClick={onClose}><Icon name="x" /></button>
        </div>
        <div className="sheet__body">{children}</div>
      </div>
    </div>,
    document.body,
  )
}

export function Chip({ on, onClick, children, removable }: { on?: boolean; onClick?: () => void; children: ReactNode; removable?: boolean }) {
  return (
    <button type="button" className={`chip${on ? ' is-on' : ''}${removable ? ' chip--accent' : ''}`} aria-pressed={on} onClick={onClick}>
      {children}
      {removable && <Icon name="x" size={13} stroke={2.4} />}
    </button>
  )
}

export function SectionHead({ title, count, action, onAction }: { title: string; count?: number | string; action?: string; onAction?: () => void }) {
  return (
    <div className="section-head">
      <h2 className="h2">{title}{count !== undefined && <span className="h2__count">{count}</span>}</h2>
      {action && <button type="button" className="link-btn" onClick={onAction}>{action}</button>}
    </div>
  )
}
