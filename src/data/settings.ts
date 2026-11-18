import { useSyncExternalStore } from 'react'
import type { ReaderMode } from './types'

/** Per-device preferences, kept in localStorage. */
export interface Settings {
  readerMode: ReaderMode
  /** Passkey credential id used for the app lock; empty when the lock is off. */
  lockCredential: string
  /** Seconds in the background before the app locks again. */
  lockDelay: 0 | 60 | 300
  /** Suwayomi server address, entered on this device, or 'device' for extensions on this device (iOS app). Empty shows sample data. */
  serverUrl: string
  /** Optional basic-auth login when the server has AUTH_MODE=basic_auth. */
  serverUser: string
  serverPass: string
  /** Page images kept on this device after reading (MB); 0 keeps none. */
  pageCacheMB: number
}

const KEY = 'midoku.settings'
const DEFAULTS: Settings = { readerMode: 'webtoon', lockCredential: '', lockDelay: 0, serverUrl: '', serverUser: '', serverPass: '', pageCacheMB: 300 }

/** In the iOS app, extensions run on the device unless a Suwayomi server is set up instead. */
const inApp = () => !!(window as { Capacitor?: { isNativePlatform?: () => boolean } }).Capacitor?.isNativePlatform?.()

function read(): Settings {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) ?? '{}') as Partial<Settings>
    return { ...DEFAULTS, ...(inApp() && saved.serverUrl === undefined ? { serverUrl: 'device' } : {}), ...saved }
  } catch {
    return DEFAULTS
  }
}

let current = read()
const listeners = new Set<() => void>()

export function getSettings(): Settings {
  return current
}

export function updateSettings(patch: Partial<Settings>) {
  current = { ...current, ...patch }
  try {
    localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    // Storage can be unavailable (private mode); the change still applies for this session.
  }
  listeners.forEach((l) => l())
}

export function useSettings(): Settings {
  return useSyncExternalStore(
    (l) => { listeners.add(l); return () => listeners.delete(l) },
    () => current,
  )
}
