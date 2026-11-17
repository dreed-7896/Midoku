import { useEffect, useState } from 'react'
import { IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { useNav } from '../components/Nav'
import { createLock, lockSupported, unlock } from '../data/lock'
import { Settings, updateSettings, useSettings } from '../data/settings'
import { useStore } from '../data/store'
import { APP_VERSION, checkForUpdate, restartToUpdate, useUpdateReady } from '../data/update'

const DELAYS: { value: Settings['lockDelay']; label: string }[] = [
  { value: 0, label: 'Immediately' },
  { value: 60, label: 'After 1 min' },
  { value: 300, label: 'After 5 min' },
]

export default function SettingsPage() {
  const settings = useSettings()
  const store = useStore()
  const nav = useNav()
  const [supported, setSupported] = useState<boolean | null>(null)
  const [busy, setBusy] = useState(false)
  const [checking, setChecking] = useState(false)
  const updateReady = useUpdateReady()
  const lockOn = !!settings.lockCredential

  useEffect(() => { lockSupported().then(setSupported) }, [])

  const toggleLock = async () => {
    setBusy(true)
    try {
      if (lockOn) {
        await unlock(settings.lockCredential)
        updateSettings({ lockCredential: '' })
        store.toast('App lock turned off')
      } else {
        const id = await createLock()
        updateSettings({ lockCredential: id })
        store.toast('App lock is on')
      }
    } catch {
      store.toast(lockOn ? 'Verification failed — lock is still on' : 'The lock was not set up')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="page">
      <div className="entry__top">
        <IconButton icon="back" label="Back" onClick={() => nav.back('/')} />
      </div>
      <header className="pad-x pad-t">
        <h1 className="h1">Settings</h1>
      </header>

      <section className="section pad-x">
        <div className="label label--flush">Reader</div>
        <div className="setting">
          <div className="setting__text">
            <strong>Default mode</strong>
            <span className="card-meta card-meta--wrap">Webtoon scrolls down without breaks. Paged turns one page at a time.</span>
          </div>
        </div>
        <div className="segmented segmented--lg">
          <button type="button" className={settings.readerMode === 'webtoon' ? 'is-on' : ''} onClick={() => updateSettings({ readerMode: 'webtoon' })}>Webtoon</button>
          <button type="button" className={settings.readerMode === 'paged' ? 'is-on' : ''} onClick={() => updateSettings({ readerMode: 'paged' })}>Paged</button>
        </div>
      </section>

      <section className="section pad-x">
        <div className="label label--flush">Privacy</div>
        <div className="setting">
          <span className="setting__icon"><Icon name="faceId" size={22} /></span>
          <div className="setting__text">
            <strong>Face ID / fingerprint lock</strong>
            <span className="card-meta card-meta--wrap">
              {supported === false
                ? 'Not available here. On iPhone, add Midoku to your Home Screen (iOS 16 or later).'
                : 'Asks for Face ID, Touch ID or your fingerprint when Midoku opens.'}
            </span>
          </div>
          <input type="checkbox" role="switch" className="switch switch--lg" checked={lockOn} disabled={busy || supported === false}
            onChange={toggleLock} aria-label="Face ID or fingerprint lock" />
        </div>
        <div className={`segmented${lockOn ? '' : ' is-disabled'}`} aria-label="Lock after">
          {DELAYS.map((d) => (
            <button key={d.value} type="button" disabled={!lockOn} className={settings.lockDelay === d.value ? 'is-on' : ''}
              onClick={() => updateSettings({ lockDelay: d.value })}>{d.label}</button>
          ))}
        </div>
        <p className="hint pad-t-sm">The lock uses a passkey saved on this device. It hides the app from others; it does not encrypt your library.</p>
      </section>

      <section className="section pad-x">
        <div className="label label--flush">About</div>
        <div className="setting">
          <span className="setting__icon"><Icon name="info" size={22} /></span>
          <div className="setting__text">
            <strong>Midoku Web · {APP_VERSION}</strong>
            <span className="card-meta card-meta--wrap">
              {updateReady ? 'A new version is ready.' : 'Preview build · sample data, not connected to a server yet'}
            </span>
          </div>
        </div>
        {updateReady ? (
          <button type="button" className="btn btn--accent btn--block" onClick={restartToUpdate}><Icon name="refresh" size={16} />Restart to update</button>
        ) : (
          <button type="button" className="btn btn--ghost btn--block" disabled={checking} onClick={async () => {
            setChecking(true)
            const found = await checkForUpdate()
            setChecking(false)
            if (!found) store.toast("You're on the latest version")
          }}><Icon name="refresh" size={16} />{checking ? 'Checking…' : 'Check for updates'}</button>
        )}
      </section>
    </div>
  )
}
