import { useEffect, useState } from 'react'
import { IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { useNav } from '../components/Nav'
import { createLock, lockSupported, unlock } from '../data/lock'
import { Settings, updateSettings, useSettings } from '../data/settings'
import { useStore } from '../data/store'
import { clearData } from '../data/cache'
import { changePassword, lockApp, usePendingWrites } from '../data/db'
import { removeAllDownloads, savedBytes, useDownloads } from '../data/downloads'
import { testServer } from '../data/suwayomi'
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

  const newPassword = async () => {
    const next = window.prompt('New app password (at least 6 characters)')
    if (!next) return
    if (next.length < 6) { store.toast('Use at least 6 characters'); return }
    if (window.prompt('Type it again') !== next) { store.toast("The passwords didn't match"); return }
    try {
      await changePassword(next)
      store.toast('Password changed')
    } catch (e) {
      store.toast((e as Error).message)
    }
  }

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

      <ServerSection />

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
          <span className="setting__icon"><Icon name="shield" size={22} /></span>
          <div className="setting__text">
            <strong>App password</strong>
            <span className="card-meta card-meta--wrap">Asked every 10 days on each device. It also protects your library in the database.</span>
          </div>
        </div>
        <div className="row-btns">
          <button type="button" className="btn btn--ghost" onClick={newPassword}>Change password</button>
          <button type="button" className="btn btn--ghost" onClick={() => lockApp().catch((e: Error) => store.toast(e.message))}>Lock now</button>
        </div>
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

      <StorageSection />

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

/** The Suwayomi address lives on this device; the app talks to it directly, nothing in between. */
function ServerSection() {
  const settings = useSettings()
  const store = useStore()
  const [url, setUrl] = useState(settings.serverUrl)
  const [user, setUser] = useState(settings.serverUser)
  const [pass, setPass] = useState(settings.serverPass)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string>()
  const connected = !!settings.serverUrl

  const connect = async () => {
    let address = url.trim()
    if (address && !/^https?:\/\//.test(address)) address = `https://${address}`
    if (!address) return
    setBusy(true)
    setError(undefined)
    try {
      const about = await testServer(address, user.trim(), pass)
      updateSettings({ serverUrl: address.replace(/\/+$/, ''), serverUser: user.trim(), serverPass: pass })
      store.toast(`Connected to ${about.name} ${about.version}`)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  const disconnect = () => {
    if (!window.confirm('Disconnect from this server? The app goes back to sample data. Your library stays in your account.')) return
    updateSettings({ serverUrl: '', serverUser: '', serverPass: '' })
    setUrl(''); setUser(''); setPass('')
  }

  return (
    <section className="section pad-x">
      <div className="label label--flush">Server</div>
      {connected ? (
        <>
          <div className="setting">
            <span className="setting__icon"><Icon name="database" size={22} /></span>
            <div className="setting__text">
              <strong>Suwayomi</strong>
              <span className="card-meta card-meta--wrap">{settings.serverUrl}</span>
              <span className="card-meta card-meta--wrap">
                {store.server.status === 'error' && store.server.where === 'server' ? `Not reachable: ${store.server.error}` : 'Titles, chapters and extensions'}
              </span>
            </div>
          </div>
          <button type="button" className="btn btn--ghost btn--block" onClick={disconnect}>Disconnect</button>
        </>
      ) : (
        <>
          <p className="hint">Connect your Suwayomi server to use your real library, sources and chapters. Until then the app shows sample data.</p>
          <div className="form">
            <label className="form__row"><span>Address</span>
              <input className="field-input" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://your-server:4567" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} />
            </label>
            <label className="form__row"><span>Username <em>optional</em></span>
              <input className="field-input" value={user} onChange={(e) => setUser(e.target.value)} autoCapitalize="none" autoCorrect="off" autoComplete="username" />
            </label>
            <label className="form__row"><span>Password <em>optional</em></span>
              <input className="field-input" type="password" value={pass} onChange={(e) => setPass(e.target.value)} autoComplete="current-password" />
            </label>
          </div>
          {error && <p className="form__error">{error}</p>}
          <button type="button" className="btn btn--accent btn--block" disabled={busy || !url.trim()} onClick={connect}>{busy ? 'Connecting…' : 'Connect'}</button>
          <p className="hint pad-t-sm">The address stays on this device and the app talks to the server directly. Use an https address: the installed app can't load plain http.</p>
        </>
      )}
    </section>
  )
}


const mb = (bytes: number) => (bytes < 1e6 ? `${Math.round(bytes / 1e3)} KB` : `${(bytes / 1e6).toFixed(bytes < 1e8 ? 1 : 0)} MB`)

/** What is kept on this device for offline use, and changes still waiting to be saved. */
function StorageSection() {
  const store = useStore()
  const downloads = useDownloads()
  const pending = usePendingWrites()
  const [usage, setUsage] = useState<{ used: number; quota: number }>()
  const count = Object.keys(downloads.saved).length
  useEffect(() => {
    navigator.storage?.estimate?.().then((e) => setUsage({ used: e.usage ?? 0, quota: e.quota ?? 0 })).catch(() => {})
  }, [count])

  const clearDownloads = async () => {
    if (!window.confirm(`Remove all ${count} downloaded chapters from this device?`)) return
    await removeAllDownloads()
    store.toast('Downloads removed')
  }
  const clearCache = async () => {
    await Promise.all([clearData(), caches.delete('midoku-images').catch(() => false)])
    store.toast('Cache cleared')
  }

  return (
    <section className="section pad-x">
      <div className="label label--flush">Storage & offline</div>
      <div className="setting">
        <span className="setting__icon"><Icon name="download" size={22} /></span>
        <div className="setting__text">
          <strong>{count} downloaded chapter{count === 1 ? '' : 's'}</strong>
          <span className="card-meta card-meta--wrap">
            {mb(savedBytes())}{downloads.queued.size || downloads.active ? ` · ${downloads.queued.size + (downloads.active ? 1 : 0)} downloading` : ''}
            {usage ? ` · ${mb(usage.used)} used on this device` : ''}
          </span>
        </div>
      </div>
      <div className="setting">
        <span className="setting__icon"><Icon name="refresh" size={22} /></span>
        <div className="setting__text">
          <strong>{pending ? `${pending} change${pending === 1 ? '' : 's'} waiting to sync` : 'Everything is saved'}</strong>
          <span className="card-meta card-meta--wrap">Changes made offline are sent when the device is back online. Opened titles stay readable offline for 3 days.</span>
        </div>
      </div>
      <div className="row-btns">
        <button type="button" className="btn btn--ghost" disabled={!count} onClick={clearDownloads}>Remove downloads</button>
        <button type="button" className="btn btn--ghost" onClick={clearCache}>Clear cache</button>
      </div>
    </section>
  )
}
