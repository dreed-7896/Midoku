import { FormEvent, useCallback, useEffect, useRef, useState } from 'react'
import { enterPassword, useAuth } from '../data/db'
import { unlock } from '../data/lock'
import { getSettings, useSettings } from '../data/settings'
import { Icon } from './Icon'

/** Covers the app until Face ID / Touch ID passes. Locks again after the chosen time in the background. */
export function LockGate() {
  const settings = useSettings()
  const enabled = !!settings.lockCredential
  const [locked, setLocked] = useState(() => !!getSettings().lockCredential)
  const [failed, setFailed] = useState(false)
  const [busy, setBusy] = useState(false)
  const hiddenAt = useRef<number | null>(null)

  useEffect(() => {
    const onVisibility = () => {
      const s = getSettings()
      if (!s.lockCredential) return
      if (document.visibilityState === 'hidden') {
        hiddenAt.current = Date.now()
        // Cover the screen right away so the app switcher snapshot stays private.
        if (s.lockDelay === 0) setLocked(true)
      } else if (hiddenAt.current && Date.now() - hiddenAt.current >= s.lockDelay * 1000) {
        setLocked(true)
      }
    }
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [])

  const tryUnlock = useCallback(async () => {
    const id = getSettings().lockCredential
    if (!id) { setLocked(false); return }
    setBusy(true)
    try {
      await unlock(id)
      setLocked(false)
      setFailed(false)
    } catch {
      setFailed(true)
    } finally {
      setBusy(false)
    }
  }, [])

  if (!enabled || !locked) return null

  return (
    <div className="lock" role="dialog" aria-modal="true" aria-label="Midoku is locked">
      <img src="/icon.svg" alt="" className="lock__logo" />
      <h1 className="lock__title">Midoku is locked</h1>
      <p className="lock__sub">Use Face ID or your fingerprint to continue.</p>
      <button type="button" className="btn btn--accent btn--xl lock__btn" onClick={tryUnlock} disabled={busy}>
        <Icon name="faceId" size={22} /> {busy ? 'Waiting…' : 'Unlock'}
      </button>
      {failed && (
        <p className="lock__error">
          That didn't work. Try again.
          <br />
          <span>If the Midoku passkey was deleted, remove Midoku from your Home Screen and add it again.</span>
        </p>
      )}
    </div>
  )
}

/** Covers the app until the app password is entered on this device. */
export function PasswordGate() {
  const auth = useAuth()
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState(false)
  if (auth.userId) return null
  // Plain cover while the saved session is checked, so nothing shows through.
  if (!auth.ready) return <div className="lock" aria-hidden="true" />

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError(undefined)
    try {
      await enterPassword(password)
      setPassword('')
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="lock" role="dialog" aria-modal="true" aria-label="Enter password" onSubmit={submit}>
      <img src="/icon.svg" alt="" className="lock__logo" />
      <h1 className="lock__title">Midoku</h1>
      <p className="lock__sub">Enter the app password.</p>
      <input className="field-input lock__input" type="password" value={password} onChange={(e) => setPassword(e.target.value)}
        autoComplete="current-password" aria-label="Password" autoFocus />
      <button type="submit" className="btn btn--accent btn--xl lock__btn" disabled={busy || !password}>{busy ? 'Checking…' : 'Open'}</button>
      {error && <p className="lock__error">{error}</p>}
    </form>
  )
}
