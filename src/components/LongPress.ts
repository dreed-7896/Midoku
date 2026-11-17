import { useRef } from 'react'

/** Long press (or right click) runs `onLong`; the click that ends a long press is ignored. */
export function useLongPress<T>(onLong: (item: T) => void) {
  const timer = useRef<ReturnType<typeof setTimeout>>()
  const fired = useRef(false)
  const start = useRef<{ x: number; y: number } | null>(null)
  const cancel = () => { clearTimeout(timer.current); start.current = null }
  return (c: T) => ({
    onPointerDown: (e: React.PointerEvent) => {
      fired.current = false
      start.current = { x: e.clientX, y: e.clientY }
      timer.current = setTimeout(() => { fired.current = true; navigator.vibrate?.(10); onLong(c) }, 450)
    },
    onPointerMove: (e: React.PointerEvent) => {
      if (start.current && Math.hypot(e.clientX - start.current.x, e.clientY - start.current.y) > 10) cancel()
    },
    onPointerUp: cancel,
    onPointerLeave: cancel,
    onContextMenu: (e: React.MouseEvent) => { e.preventDefault(); cancel(); fired.current = true; onLong(c) },
    wasLongPress: () => { const f = fired.current; fired.current = false; return f },
  })
}
