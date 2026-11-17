import { timeLabel } from '../data/dates'
import { useStore } from '../data/store'
import type { Update } from '../data/updates'
import { Cover } from './Art'
import { Icon } from './Icon'
import type { useLongPress } from './LongPress'

/** One row of the Updates feed (Updates screen and Home's preview). */
export function UpdateRow({ u, fresh, busy, press, onOpen }: {
  u: Update; fresh?: boolean; busy?: boolean; press?: ReturnType<ReturnType<typeof useLongPress<Update>>>; onOpen: () => void
}) {
  const store = useStore()
  const entry = store.entry(u.entryId)
  if (!entry) return null
  return (
    <button type="button" className={`order-row history-row plain-btn${u.read ? ' is-read' : ''}`} disabled={busy}
      onPointerDown={press?.onPointerDown} onPointerMove={press?.onPointerMove} onPointerUp={press?.onPointerUp} onPointerLeave={press?.onPointerLeave} onContextMenu={press?.onContextMenu}
      onClick={() => { if (!press?.wasLongPress()) onOpen() }}>
      <span className="order-row__cover"><Cover art={entry.art} title={entry.title} url={entry.coverUrl} /></span>
      <span className="check-row__name check-row__name--stack grow">
        <strong className="ellipsis">{fresh && <span className="dot-new" aria-label="New" />}{entry.title}</strong>
        <span className="card-meta ellipsis">{u.label} · {u.detail}</span>
      </span>
      {u.pages ? <span className="tag tag--accent">+{u.pages.now - u.pages.before} pages</span>
        : u.read ? <Icon name="check" size={16} /> : <span className="card-meta">{timeLabel(u.at)}</span>}
    </button>
  )
}

