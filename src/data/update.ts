import { useSyncExternalStore } from 'react'

/**
 * Service worker updates. A new deploy installs a new worker that waits; the app shows
 * "New version available" and restarting activates it and reloads.
 */
let registration: ServiceWorkerRegistration | null = null
let waiting: ServiceWorker | null = null
let restarting = false
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

function setWaiting(sw: ServiceWorker | null) {
  waiting = sw
  emit()
}

function watch(reg: ServiceWorkerRegistration) {
  if (reg.waiting && navigator.serviceWorker.controller) setWaiting(reg.waiting)
  reg.addEventListener('updatefound', () => {
    const sw = reg.installing
    sw?.addEventListener('statechange', () => {
      // Only an update when a worker already controls the page; the very first install is not.
      if (sw.state === 'installed' && navigator.serviceWorker.controller) setWaiting(sw)
    })
  })
}

export function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (restarting) window.location.reload()
  })
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').then((reg) => {
      registration = reg
      watch(reg)
      // Installed apps stay open for days; check again whenever the app comes back.
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') reg.update().catch(() => {}) })
      setInterval(() => reg.update().catch(() => {}), 30 * 60 * 1000)
    }).catch(() => {})
  })
}

/** Asks the server for a newer version; resolves true when one is ready to install. */
export async function checkForUpdate(): Promise<boolean> {
  if (!registration) return false
  await registration.update().catch(() => {})
  // Give a freshly found worker a moment to finish installing.
  await new Promise((r) => setTimeout(r, 1500))
  return !!waiting
}

export function restartToUpdate() {
  if (!waiting) { window.location.reload(); return }
  restarting = true
  waiting.postMessage('SKIP_WAITING')
}

export function useUpdateReady(): boolean {
  return useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l) }, () => !!waiting)
}

export const APP_VERSION = __APP_VERSION__
