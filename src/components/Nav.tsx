import { MouseEvent, RefObject, useEffect, useLayoutEffect, useMemo } from 'react'
import { Link, LinkProps, useLocation, useNavigate } from 'react-router-dom'

/**
 * Native-style navigation: pushes slide in from the right, going back slides the page away to the right,
 * tab switches cross-fade. Uses the View Transitions API and falls back to an instant change.
 */
type Direction = 'forward' | 'back' | 'tab'

type ViewTransitionDoc = Document & { startViewTransition?: (cb: () => Promise<void>) => { finished: Promise<void> } }

let resolveRender: (() => void) | null = null
let afterRender: (() => void) | null = null
let currentKey = 'default'
/** Direction of the navigation in flight, used to decide whether to restore scroll. */
let pendingDirection: Direction | 'swipe' | null = null
const scrollPositions = new Map<string, number>()

function transition(direction: Direction, update: () => void) {
  const doc = document as ViewTransitionDoc
  scrollPositions.set(currentKey, window.scrollY)
  pendingDirection = direction
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  if (!doc.startViewTransition || reduce) {
    update()
    return
  }
  const root = document.documentElement
  root.dataset.nav = direction
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
  return useMemo(() => {
    const canGoBack = () => ((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0
    return {
      /** `direction: 'back'` makes a push look like going back (e.g. previous chapter). */
      go: (to: string, opts: { replace?: boolean; tab?: boolean; direction?: 'forward' | 'back' } = {}) =>
        transition(opts.tab ? 'tab' : opts.direction ?? 'forward', () => navigate(to, { replace: opts.replace })),
      back: (fallback = '/') =>
        transition('back', () => (canGoBack() ? navigate(-1) : navigate(fallback, { replace: true }))),
      /** Back without an animation; the edge swipe has already moved the page away. */
      backInstant: (fallback = '/', onRendered?: () => void) => {
        scrollPositions.set(currentKey, window.scrollY)
        pendingDirection = 'swipe'
        afterRender = onRendered ?? null
        if (canGoBack()) navigate(-1)
        else navigate(fallback, { replace: true })
      },
    }
  }, [navigate])
}

/** Restores scroll on back, resets it on push, then lets the pending view transition capture the new page. */
export function useNavEffects() {
  const location = useLocation()
  useLayoutEffect(() => {
    const dir = pendingDirection
    pendingDirection = null
    const saved = scrollPositions.get(location.key)
    // Browser back/forward (dir null) and in-app back restore; pushes start at the top.
    const restore = (dir === null || dir === 'back' || dir === 'swipe') && saved !== undefined
    window.scrollTo(0, restore ? saved : 0)
    currentKey = location.key
    resolveRender?.()
    resolveRender = null
    afterRender?.()
    afterRender = null
  }, [location.key])
}

const isStandalone = () =>
  window.matchMedia('(display-mode: standalone)').matches || (navigator as Navigator & { standalone?: boolean }).standalone === true

/**
 * iOS-style edge swipe: drag from the left edge to slide the page away and go back.
 * Only in the installed app; Safari's own swipe handles the browser case.
 */
export function useEdgeSwipeBack(screen: RefObject<HTMLElement>, enabled: boolean, fallback: string) {
  const nav = useNav()
  useEffect(() => {
    if (!enabled || !isStandalone()) return
    let tracking = false, decided = false, startX = 0, startY = 0, dx = 0, startT = 0
    const el = () => screen.current

    const onStart = (e: TouchEvent) => {
      const t = e.touches[0]
      if (e.touches.length !== 1 || t.clientX > 24) return
      tracking = true; decided = false; startX = t.clientX; startY = t.clientY; dx = 0; startT = Date.now()
    }
    const onMove = (e: TouchEvent) => {
      const node = el()
      if (!tracking || !node) return
      const t = e.touches[0]
      const mx = t.clientX - startX, my = t.clientY - startY
      if (!decided) {
        if (Math.abs(mx) < 8 && Math.abs(my) < 8) return
        decided = true
        if (Math.abs(my) > Math.abs(mx) || mx < 0) { tracking = false; return }
        node.classList.add('is-swiping')
      }
      e.preventDefault()
      dx = Math.max(0, mx)
      node.style.transform = `translate3d(${dx}px, 0, 0)`
    }
    const onEnd = () => {
      const node = el()
      if (!tracking || !decided || !node) { tracking = false; return }
      tracking = false
      const width = node.offsetWidth || window.innerWidth
      const velocity = dx / Math.max(1, Date.now() - startT)
      const commit = dx > width * 0.33 || velocity > 0.6
      node.style.transition = 'transform 220ms cubic-bezier(0.2, 0.8, 0.2, 1)'
      node.style.transform = commit ? `translate3d(${width}px, 0, 0)` : 'translate3d(0, 0, 0)'
      setTimeout(() => {
        const reset = () => {
          node.style.transition = ''
          node.style.transform = ''
          node.classList.remove('is-swiping')
          if (commit) node.animate([{ opacity: 0.4 }, { opacity: 1 }], { duration: 160, easing: 'ease-out' })
        }
        if (commit) nav.backInstant(fallback, reset)
        else reset()
      }, 220)
    }

    document.addEventListener('touchstart', onStart, { passive: true })
    document.addEventListener('touchmove', onMove, { passive: false })
    document.addEventListener('touchend', onEnd)
    document.addEventListener('touchcancel', onEnd)
    return () => {
      document.removeEventListener('touchstart', onStart)
      document.removeEventListener('touchmove', onMove)
      document.removeEventListener('touchend', onEnd)
      document.removeEventListener('touchcancel', onEnd)
    }
  }, [enabled, fallback, nav, screen])
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
