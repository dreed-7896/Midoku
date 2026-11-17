import { ReactNode } from 'react'
import { Icon, IconName } from './Icon'

/**
 * Shared states for screens and lists: loading placeholders, empty results, caught up, errors and
 * a slim banner for conditions like "offline". One look everywhere instead of loose grey lines.
 */

type Tone = 'neutral' | 'done' | 'error'

export function Empty({ icon = 'info', title, detail, action, tone = 'neutral', compact }: {
  icon?: IconName
  title: string
  detail?: ReactNode
  action?: { label: string; onClick: () => void }
  tone?: Tone
  compact?: boolean
}) {
  return (
    <div className={`state state--${tone}${compact ? ' state--compact' : ''}`} role="status">
      <span className="state__icon"><Icon name={icon} size={compact ? 18 : 22} /></span>
      <div className="state__text">
        <strong>{title}</strong>
        {detail && <span>{detail}</span>}
      </div>
      {action && <button type="button" className="btn btn--ghost btn--sm" onClick={action.onClick}>{action.label}</button>}
    </div>
  )
}

/** Placeholder shapes while content loads, with a short label for screen readers and context. */
export function Loading({ label, shape = 'grid', count }: { label: string; shape?: 'grid' | 'rail' | 'rows' | 'page'; count?: number }) {
  const n = count ?? (shape === 'grid' ? 6 : shape === 'rail' ? 3 : shape === 'rows' ? 4 : 1)
  return (
    <div className={`loading loading--${shape}`} role="status" aria-live="polite">
      <span className="loading__label"><span className="loading__bar" />{label}</span>
      {shape !== 'page' && (
        <div className="loading__shapes" aria-hidden="true">
          {Array.from({ length: n }, (_, i) => <span key={i} className="loading__shape skeleton" />)}
        </div>
      )}
    </div>
  )
}

export function Banner({ icon = 'info', children, tone = 'neutral' }: { icon?: IconName; children: ReactNode; tone?: Tone | 'busy' }) {
  return (
    <div className={`banner-line banner-line--${tone}`} role="status">
      {tone === 'busy' ? <span className="spinner" aria-hidden="true" /> : <Icon name={icon} size={15} />}
      <span>{children}</span>
    </div>
  )
}
