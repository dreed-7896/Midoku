import { MouseEvent, ReactNode, useLayoutEffect, useMemo, useReducer, useRef } from 'react'
import { Link, LinkProps, Location, Routes, useLocation, useNavigate, useNavigationType } from 'react-router-dom'

/**
 * A native-style page stack. Every screen is its own scrolling layer. Pushing slides the new screen in from
 * the right while the one underneath shifts left and darkens; going back reverses it. The previous screen
 * stays mounted underneath, so going back shows it with its scroll position and state intact.
 *
 * The edge swipe is left to iOS: it animates its own back gesture, so a history step the app did not start
 * (iOS swipe, browser back) changes screens without a second animation.
 */
type Direction = 'forward' | 'back' | 'tab' | 'none'
type Role = 'current' | 'hidden' | 'top-in' | 'under-out' | 'top-out' | 'under-in' | 'fade-in'

const DURATION = 360
let pendingDirection: Direction | null = null
const scrollPositions = new Map<string, number>()

const historyIndex = () => (window.history.state as { idx?: number } | null)?.idx ?? 0
const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches

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

export function StackRoutes({ children }: { children: ReactNode }) {
  const location = useLocation()
  const navType = useNavigationType()
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
    // A history step the app did not start (iOS edge swipe, browser back) is already animated by the system.
    const dir = pendingDirection ?? (navType === 'POP' ? 'none' : 'forward')
    pendingDirection = null
    anim.current = dir === 'none' || reduceMotion() ? null : { from: last.current, dir, key: location.key }
    last.current = location
  }

  const els = useRef(new Map<string, HTMLDivElement>())
  const register = useMemo(() => (key: string, el: HTMLDivElement | null) => {
    if (el) els.current.set(key, el)
    else els.current.delete(key)
  }, [])

  useLayoutEffect(() => {
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
