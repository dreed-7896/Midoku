import { CSSProperties, useEffect, useRef, useState } from 'react'
import { savedPageUrl } from '../data/downloads'
import { fetchImage, needsAuthForImages } from '../data/suwayomi'
import { cachedThumb, chapterThumb } from '../data/thumbs'
import type { Chapter, CoverArt } from '../data/types'

/**
 * Blob URLs of images fetched with a login, kept after the image leaves the screen so going back to a
 * screen (or a page coming back into the reader's window) shows it at once instead of fetching again.
 * Unused ones are released oldest first once they pass the size budget.
 */
const blobs = new Map<string, { url: string; size: number; refs: number }>()
const BUDGET = 60 * 1024 * 1024
function trim() {
  let total = 0
  for (const b of blobs.values()) total += b.size
  for (const [k, b] of blobs) {
    if (total <= BUDGET) break
    if (b.refs > 0) continue
    URL.revokeObjectURL(b.url)
    blobs.delete(k)
    total -= b.size
  }
}
function take(src: string) {
  const b = blobs.get(src)
  if (!b) return undefined
  // Move to the end: most recently used.
  blobs.delete(src); blobs.set(src, b)
  b.refs++
  return b.url
}
function release(src: string) {
  const b = blobs.get(src)
  if (b) b.refs = Math.max(0, b.refs - 1)
  trim()
}

/**
 * An image from the server. Plain <img> when the server is open; with a login it is fetched with the
 * Authorization header and shown from a blob URL (kept in memory a while, see above).
 * fromDevice reads a downloaded page from the device first (works offline, without the service worker).
 * Covers and icons are cached by the service worker (sw.js), so they also show offline.
 */
export function RemoteImage({ src, alt = '', className, onLoad, fromDevice }: { src: string; alt?: string; className?: string; onLoad?: () => void; fromDevice?: boolean }) {
  const auth = needsAuthForImages()
  const direct = !auth && !fromDevice
  const [url, setUrl] = useState(() => (direct ? src : blobs.get(src)?.url ?? ''))
  const [failed, setFailed] = useState(false)
  useEffect(() => {
    setFailed(false)
    if (direct) { setUrl(src); return }
    const cached = take(src)
    if (cached) { setUrl(cached); return () => release(src) }
    const ctrl = new AbortController()
    let held = false
    let saved: string | undefined
    const load = async () => {
      saved = fromDevice ? await savedPageUrl(src) : undefined
      if (saved) return saved
      const blob = await fetchImage(src, ctrl.signal)
      // Another copy of this image may have finished first.
      const again = take(src)
      if (again) return again
      const u = URL.createObjectURL(blob)
      blobs.set(src, { url: u, size: blob.size, refs: 1 })
      return u
    }
    load()
      .then((u) => { held = blobs.get(src)?.url === u; if (ctrl.signal.aborted) { if (held) release(src) } else setUrl(u) })
      .catch(() => { if (!ctrl.signal.aborted) setFailed(true) })
    return () => { ctrl.abort(); if (held) release(src); if (saved) URL.revokeObjectURL(saved) }
  }, [src, direct, fromDevice])
  if (failed || !url) return null
  // CORS mode (Suwayomi allows any origin) so the service worker can cache real, readable responses.
  return <img src={url} alt={alt} className={className} loading={direct ? 'lazy' : undefined} crossOrigin={direct ? 'anonymous' : undefined} onLoad={onLoad} onError={() => setFailed(true)} />
}

/** Placeholder cover artwork: two flat colours, one shape and the title, like a printed book cover. */
export function Cover({ art, title, className = '', plain, url }: { art: CoverArt; title: string; className?: string; plain?: boolean; url?: string }) {
  const style = { '--c1': art.c1, '--c2': art.c2, '--ink': art.ink } as CSSProperties
  return (
    <div className={`cover${plain ? ' cover--plain' : ''} ${className}`} style={style} role="img" aria-label={`${title} cover`}>
      <span className={`cover__shape cover__shape--${art.motif}`} />
      <span className="cover__rule" />
      <span className="cover__title">{title}</span>
      {url && <RemoteImage src={url} className="cover__img" />}
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

/** True once the element comes near the screen (stays true). Grids of page images load as they scroll in. */
function useNear<T extends HTMLElement>(margin = '300px') {
  const ref = useRef<T>(null)
  const [near, setNear] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el || near) return
    const io = new IntersectionObserver((items) => { if (items.some((i) => i.isIntersecting)) { setNear(true); io.disconnect() } }, { rootMargin: margin })
    io.observe(el)
    return () => io.disconnect()
  }, [near, margin])
  return [ref, near] as const
}

/** A server image that is only fetched once it scrolls near the screen; a page placeholder until then. */
export function LazyImage({ src, fromDevice, placeholder = 0 }: { src: string; fromDevice?: boolean; placeholder?: number }) {
  const [ref, near] = useNear<HTMLDivElement>()
  return <div ref={ref} className="lazy-img">{near && src ? <RemoteImage src={src} fromDevice={fromDevice} /> : <PageThumb layout={placeholder} />}</div>
}

/**
 * A chapter's thumbnail: a picture the person picked, or a page of the chapter made into a small image on
 * this device (see thumbs.ts) once the chapter is on screen. Sample chapters keep the drawn placeholder.
 */
export function ChapterThumb({ chapter }: { chapter: Chapter }) {
  const [ref, near] = useNear<HTMLDivElement>('100px')
  const picked = chapter.thumb?.startsWith('data:') ? chapter.thumb : undefined
  const [url, setUrl] = useState<string>()
  const key = `${chapter.sourceId}|${chapter.sourceUrl}|${chapter.thumb ?? ''}|${chapter.range?.[0] ?? ''}`
  useEffect(() => {
    setUrl(undefined)
    if (picked || !chapter.remoteId) return
    let alive = true
    cachedThumb(chapter).then((u) => { if (alive && u) setUrl(u) })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])
  useEffect(() => {
    if (!near || url || picked || !chapter.remoteId) return
    let alive = true
    // A short wait so flinging through a long list doesn't start work for every chapter passed.
    const t = setTimeout(() => chapterThumb(chapter).then((u) => { if (alive && u) setUrl(u) }).catch(() => {}), 300)
    return () => { alive = false; clearTimeout(t) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [near, key, url])
  const shown = picked ?? url
  return <div ref={ref} className="chapter-art">{shown ? <img src={shown} alt="" /> : <PageThumb layout={chapter.layout} />}</div>
}

export function SourceIcon({ letter, color, size = 40, url }: { letter: string; color: string; size?: number; url?: string }) {
  return (
    <span className="source-icon" style={{ width: size, height: size, background: color, fontSize: Math.round(size * 0.44) }} aria-hidden="true">
      {letter}
      {url && <RemoteImage src={url} className="source-icon__img" />}
    </span>
  )
}
