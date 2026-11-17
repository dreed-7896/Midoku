import type { CSSProperties } from 'react'
import type { CoverArt } from '../data/types'

/** Placeholder cover artwork: two flat colours, one shape and the title, like a printed book cover. */
export function Cover({ art, title, className = '', plain }: { art: CoverArt; title: string; className?: string; plain?: boolean }) {
  const style = { '--c1': art.c1, '--c2': art.c2, '--ink': art.ink } as CSSProperties
  return (
    <div className={`cover${plain ? ' cover--plain' : ''} ${className}`} style={style} role="img" aria-label={`${title} cover`}>
      <span className={`cover__shape cover__shape--${art.motif}`} />
      <span className="cover__rule" />
      <span className="cover__title">{title}</span>
    </div>
  )
}

const L = '#F4F2EC', M = '#CFCAC0', T = '#B9B4AA', D = '#3A3835'
type Panel = [number, number, number, number, string]
const LAYOUTS: Panel[][] = [
  [[6, 5, 88, 36, M], [6, 44, 43, 51, L], [51, 44, 43, 51, D]],
  [[6, 5, 88, 27, L], [6, 35, 55, 30, T], [64, 35, 30, 30, L], [6, 68, 88, 27, D]],
  [[6, 5, 50, 90, M], [59, 5, 35, 43, L], [59, 51, 35, 44, D]],
  [[6, 5, 43, 30, L], [51, 5, 43, 30, M], [6, 38, 88, 30, D], [6, 71, 43, 24, L], [51, 71, 43, 24, T]],
]

/** Placeholder chapter thumbnail: a manga page drawn as panels. */
export function PageThumb({ layout }: { layout: number }) {
  const panels = LAYOUTS[Math.abs(layout) % LAYOUTS.length]
  return (
    <div className="page-thumb" aria-hidden="true">
      {panels.map(([x, y, w, h, f], i) => (
        <span key={i} style={{ left: `${x}%`, top: `${y}%`, width: `${w}%`, height: `${h}%`, background: f }} />
      ))}
    </div>
  )
}

export function SourceIcon({ letter, color, size = 40 }: { letter: string; color: string; size?: number }) {
  return (
    <span className="source-icon" style={{ width: size, height: size, background: color, fontSize: Math.round(size * 0.44) }} aria-hidden="true">
      {letter}
    </span>
  )
}
