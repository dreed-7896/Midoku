import { MouseEvent, useLayoutEffect, useMemo } from 'react'
import { Link, LinkProps, useLocation, useNavigate } from 'react-router-dom'

/**
 * Native-style navigation: pushes slide in from the right, going back slides the page away to the right,
 * tab switches cross-fade. Uses the View Transitions API and falls back to an instant change.
 */
type Direction = 'forward' | 'back' | 'tab'

type ViewTransitionDoc = Document & { startViewTransition?: (cb: () => Promise<void>) => { finished: Promise<void> } }

let resolveRender: (() => void) | null = null
let currentKey = 'default'
const scrollPositions = new Map<string, number>()

function transition(direction: Direction, update: () => void) {
  const doc = document as ViewTransitionDoc
  scrollPositions.set(currentKey, window.scrollY)
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const root = document.documentElement
  root.dataset.nav = direction
  if (!doc.startViewTransition || reduce) {
    update()
    return
  }
  const t = doc.startViewTransition(() => new Promise<void>((resolve) => {
    resolveRender = resolve
    update()
    // Never leave the transition hanging if the location does not change.
    setTimeout(resolve, 800)
  }))
  t.finished.finally(() => { if (root.dataset.nav === direction) delete root.dataset.nav })
}

export function useNav() {
  const navigate = useNavigate()
  return useMemo(() => ({
    go: (to: string, opts: { replace?: boolean; tab?: boolean } = {}) =>
      transition(opts.tab ? 'tab' : 'forward', () => navigate(to, { replace: opts.replace })),
    back: (fallback = '/') => {
      const idx = (window.history.state as { idx?: number } | null)?.idx ?? 0
      transition('back', () => (idx > 0 ? navigate(-1) : navigate(fallback, { replace: true })))
    },
  }), [navigate])
}

/** Restores scroll on back, resets it on push, then lets the pending view transition capture the new page. */
export function useNavEffects() {
  const location = useLocation()
  useLayoutEffect(() => {
    const dir = document.documentElement.dataset.nav
    const saved = scrollPositions.get(location.key)
    window.scrollTo(0, dir !== 'forward' && dir !== 'tab' && saved !== undefined ? saved : 0)
    currentKey = location.key
    resolveRender?.()
    resolveRender = null
  }, [location.key])
}

/** Drop-in Link that animates like a native push. */
export function TLink({ to, replace, onClick, ...rest }: Omit<LinkProps, 'to'> & { to: string }) {
  const nav = useNav()
  const handle = (e: MouseEvent<HTMLAnchorElement>) => {
    onClick?.(e)
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    e.preventDefault()
    nav.go(to, { replace })
  }
  return <Link to={to} replace={replace} onClick={handle} {...rest} />
}
