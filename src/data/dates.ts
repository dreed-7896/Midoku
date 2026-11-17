/** "Today", "Yesterday", a weekday this week, then a date. */
export const dayLabel = (t: number) => {
  const d = new Date(t)
  const start = new Date(); start.setHours(0, 0, 0, 0)
  const diff = Math.round((start.getTime() - new Date(d).setHours(0, 0, 0, 0)) / 86_400_000)
  if (diff <= 0) return 'Today'
  if (diff === 1) return 'Yesterday'
  if (diff < 7) return d.toLocaleDateString('en', { weekday: 'long' })
  return d.toLocaleDateString('en', { day: 'numeric', month: 'short', year: d.getFullYear() === new Date().getFullYear() ? undefined : 'numeric' })
}
export const timeLabel = (t: number) => new Date(t).toLocaleTimeString('en', { hour: 'numeric', minute: '2-digit' })

/** Items grouped under day headings, in the order given. */
export function byDay<T>(items: T[], at: (t: T) => number): [string, T[]][] {
  const map = new Map<string, T[]>()
  for (const it of items) { const k = dayLabel(at(it)); map.set(k, [...(map.get(k) ?? []), it]) }
  return [...map.entries()]
}
