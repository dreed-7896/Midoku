import { MouseEvent, ReactNode, useEffect, useLayoutEffect, useMemo, useReducer, useRef } from 'react'
import { Link, LinkProps, Location, Routes, useLocation, useNavigate, useNavigationType } from 'react-router-dom'

/**
 * A native-style page stack. Every screen is its own scrolling layer. Pushing slides the new screen in from
 * the right while the one underneath shifts left and darkens; going back reverses it. The previous screen
 * stays mounted underneath, so the edge swipe drags the real page away and reveals the real previous page,
 * with scroll positions and state intact.
 */
type Direction = 'forward' | 'back' | 'tab' | 'swipe'
type Role = 'current' | 'hidden' | 'top-in' | 'under-out' | 'top-out' | 'under-in' | 'fade-in'

const DURATION = 360
let pendingDirection: Direction | null = null
const scrollPositions = new Map<string, number>()

const historyIndex = () => (window.history.state as { idx?: number } | null)?.idx ?? 0
const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches
const isStandalone = () =>
  window.matchMedia('(display-mode: standalone)').matches || (navigator as Navigator & { standalone?: boolean }).standalone === true

export function useNav() {
  const navigate = useNavigate()
  return useMemo(() => ({
    /** `direction: 'back'` makes a push look like going back (e.g. previous chapter). */
    go: (to: string, opts: { replace?: boolean; tab?: boolean; direction?: 'forward' | 'back' } = {}) => {
      pendingDirection = opts.tab ? 'tab' : opts.direction ?? 'forward'
      navigate(to, { replace: opts.replace })
    },
    back: (fallback = '/') => {
      pendingDirection = 'back'
      if (historyIndex() > 0) navigate(-1)
      else navigate(fallback, { replace: true })
    },
  }), [navigate])
}

/** The scroll container of the screen on top (Library uses its active tab panel). */
export function currentScroller(): HTMLElement | null {
  const layer = document.querySelector<HTMLElement>('.layer--current, .layer--top-in, .layer--fade-in')
  return layer?.querySelector<HTMLElement>('[data-scroll-active="true"]') ?? layer
}

function Layer({ loc, role, children, register }: {
  loc: Location; role: Role; children: ReactNode; register: (key: string, el: HTMLDivElement | null) => void
}) {
  const ref = useRef<HTMLDivElement>(null)
  useLayoutEffect(() => {
    const el = ref.current!
    register(loc.key, el)
    el.scrollTop = scrollPositions.get(loc.key) ?? 0
    return () => register(loc.key, null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const passive = role === 'hidden' || role === 'under-out' || role === 'top-out'
  return (
    <div ref={ref} className={`layer layer--${role}`} aria-hidden={passive || undefined}
      onScroll={(e) => scrollPositions.set(loc.key, e.currentTarget.scrollTop)}>
      <Routes location={loc}>{children}</Routes>
    </div>
  )
}

export function StackRoutes({ children, canSwipeBack }: { children: ReactNode; canSwipeBack: (pathname: string) => boolean }) {
  const location = useLocation()
  const navType = useNavigationType()
  const navigate = useNavigate()
  const [, rerender] = useReducer((n: number) => n + 1, 0)
  const idx = historyIndex()

  // Mirror the browser history so the screen underneath is known.
  const stack = useRef<Location[]>([])
  if (stack.current[idx]?.key !== location.key) {
    if (navType === 'PUSH') stack.current = stack.current.slice(0, idx)
    stack.current[idx] = location
  }
  const below = idx > 0 ? stack.current[idx - 1] : undefined

  // Work out the transition while rendering, so the screen being left never unmounts mid-animation.
  const last = useRef(location)
  const anim = useRef<{ from: Location; dir: 'forward' | 'back' | 'tab'; key: string } | null>(null)
  if (last.current.key !== location.key) {
    const dir = pendingDirection ?? (navType === 'POP' ? 'back' : 'forward')
    pendingDirection = null
    anim.current = dir === 'swipe' || reduceMotion() ? null : { from: last.current, dir, key: location.key }
    last.current = location
  }

  const els = useRef(new Map<string, HTMLDivElement>())
  const register = useMemo(() => (key: string, el: HTMLDivElement | null) => {
    if (el) els.current.set(key, el)
    else els.current.delete(key)
  }, [])

  useLayoutEffect(() => {
    // Drop any inline styles left by an edge swipe.
    els.current.forEach((el) => { el.style.transform = ''; el.style.filter = ''; el.style.transition = ''; el.style.visibility = '' })
    if (!anim.current) return
    const key = anim.current.key
    const t = setTimeout(() => {
      if (anim.current?.key === key) { anim.current = null; rerender() }
    }, DURATION + 30)
    return () => clearTimeout(t)
  }, [location.key])

  // Which screens are on stage, and how each one moves.
  const roles = new Map<string, { loc: Location; role: Role }>()
  const put = (loc: Location | undefined, role: Role) => { if (loc) roles.set(loc.key, { loc, role }) }
  const a = anim.current
  if (a?.dir === 'forward') { put(below, 'hidden'); put(a.from, 'under-out'); put(location, 'top-in') }
  else if (a?.dir === 'back') { put(below, 'hidden'); put(location, 'under-in'); put(a.from, 'top-out') }
  else if (a?.dir === 'tab') { put(below, 'hidden'); put(location, 'fade-in') }
  else { put(below, 'hidden'); put(location, 'current') }

  // Keep DOM order stable (by first appearance) so scroll containers are never moved; z-index does the stacking.
  const order = useRef(new Map<string, number>())
  for (const k of roles.keys()) if (!order.current.has(k)) order.current.set(k, order.current.size)
  const layers = [...roles.values()].sort((x, y) => order.current.get(x.loc.key)! - order.current.get(y.loc.key)!)

  // Edge swipe: drag the top screen right to reveal the one below; release past a third to go back.
  useEffect(() => {
    if (!below || !isStandalone() || !canSwipeBack(location.pathname)) return
    let tracking = false, decided = false, startX = 0, startY = 0, dx = 0, startT = 0
    const top = () => els.current.get(location.key)
    const under = () => els.current.get(below.key)

    const paint = (x: number, width: number) => {
      const p = Math.min(1, x / width)
      top()!.style.transform = `translate3d(${x}px, 0, 0)`
      const u = under()!
      u.style.transform = `translate3d(${-30 * (1 - p)}%, 0, 0)`
      u.style.filter = `brightness(${0.4 + 0.6 * p})`
    }
    const onStart = (e: TouchEvent) => {
      const t = e.touches[0]
      if (e.touches.length !== 1 || t.clientX > 24 || anim.current) return
      tracking = true; decided = false; startX = t.clientX; startY = t.clientY; dx = 0; startT = Date.now()
    }
    const onMove = (e: TouchEvent) => {
      if (!tracking || !top() || !under()) return
      const t = e.touches[0]
      const mx = t.clientX - startX, my = t.clientY - startY
      if (!decided) {
        if (Math.abs(mx) < 8 && Math.abs(my) < 8) return
        decided = true
        if (Math.abs(my) > Math.abs(mx) || mx < 0) { tracking = false; return }
        top()!.classList.add('layer--dragging')
        under()!.classList.add('layer--peek')
      }
      e.preventDefault()
      dx = Math.max(0, mx)
      paint(dx, top()!.offsetWidth)
    }
    const onEnd = () => {
      const t = top(), u = under()
      if (!tracking || !decided || !t || !u) { tracking = false; return }
      tracking = false
      const width = t.offsetWidth
      const commit = dx > width * 0.33 || dx / Math.max(1, Date.now() - startT) > 0.6
      const ease = 'cubic-bezier(0.2, 0.8, 0.2, 1)'
      t.style.transition = `transform 240ms ${ease}`
      u.style.transition = `transform 240ms ${ease}, filter 240ms ${ease}`
      paint(commit ? width : 0, width)
      setTimeout(() => {
        t.classList.remove('layer--dragging')
        u.classList.remove('layer--peek')
        if (commit) {
          pendingDirection = 'swipe'
          navigate(-1)
        } else {
          for (const el of [t, u]) { el.style.transform = ''; el.style.filter = ''; el.style.transition = '' }
        }
      }, 240)
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
  }, [below, location.key, location.pathname, canSwipeBack, navigate])

  return (
    <>
      {layers.map(({ loc, role }) => (
        <Layer key={loc.key} loc={loc} role={role} register={register}>{children}</Layer>
      ))}
    </>
  )
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
