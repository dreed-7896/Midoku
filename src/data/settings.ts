import { useSyncExternalStore } from 'react'

/** Per-device preferences, kept in localStorage. */
export interface Settings {
  readerMode: 'webtoon' | 'paged'
  /** Passkey credential id used for the app lock; empty when the lock is off. */
  lockCredential: string
  /** Seconds in the background before the app locks again. */
  lockDelay: 0 | 60 | 300
  /** Suwayomi server address, entered on this device. Empty shows sample data. */
  serverUrl: string
  /** Optional basic-auth login when the server has AUTH_MODE=basic_auth. */
  serverUser: string
  serverPass: string
}

const KEY = 'midoku.settings'
const DEFAULTS: Settings = { readerMode: 'webtoon', lockCredential: '', lockDelay: 0, serverUrl: '', serverUser: '', serverPass: '' }

function read(): Settings {
  try {
    return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) ?? '{}') }
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
