import { useEffect, useMemo, useState } from 'react'
import { Cover } from '../components/Art'
import { IconButton, Sheet } from '../components/Chrome'
import { Icon, type IconName } from '../components/Icon'
import { useLongPress } from '../components/LongPress'
import { useNav } from '../components/Nav'
import { UpdateRow } from '../components/UpdateRow'
import { Banner, Empty, Loading } from '../components/Status'
import { byDay } from '../data/dates'
import { findChapter, openChapter } from '../data/openChapter'
import { useStore } from '../data/store'
import { markUpdatesSeen, reloadUpdates, useUpdates, type Update } from '../data/updates'

export default function Updates() {
  const store = useStore()
  const nav = useNav()
  const server = store.server.status !== 'off'
  const { items, error, loading, seenAt } = useUpdates(store)
  const [opening, setOpening] = useState<string>()
  const [sheet, setSheet] = useState<Update | null>(null)
  const [following, setFollowing] = useState(false)
  // What was new when the screen opened stays marked while it's open; leaving clears the badge.
  const [newSince] = useState(seenAt)
  useEffect(() => { markUpdatesSeen(); return () => markUpdatesSeen() }, [])

  const followedCount = store.entries.filter((e) => e.inLibrary && e.remote && e.sources.some((s) => s.following)).length
  const groups = useMemo(() => byDay(items ?? [], (u) => u.at), [items])
  const check = async () => { await store.checkUpdates(); await reloadUpdates(store) }
  const press = useLongPress<Update>((u) => setSheet(u))

  const open = async (u: Update) => {
    setOpening(u.key)
    try {
      await openChapter(store, (to) => nav.go(to), u.entryId, { chapterId: u.chapterId, sourceId: u.sourceId, url: u.url })
    } catch (err) {
      store.toast(`Couldn't open it: ${(err as Error).message}`)
    } finally {
      setOpening(undefined)
    }
  }
  /** Runs a chapter action on updates; their titles' chapters are loaded first when needed. */
  const each = async (list: Update[], run: (entryId: string, ids: Set<string>) => void) => {
    const byEntry = new Map<string, Set<string>>()
    for (const u of list) {
      const c = await findChapter(store, u.entryId, { chapterId: u.chapterId, sourceId: u.sourceId, url: u.url }).catch(() => undefined)
      if (c) byEntry.set(u.entryId, new Set([...(byEntry.get(u.entryId) ?? []), c.id]))
    }
    byEntry.forEach((ids, entryId) => run(entryId, ids))
    return byEntry.size
  }
  const setRead = async (list: Update[], read: boolean) => {
    const n = await each(list, (id, ids) => store.editChapters(id, ids, { read, page: 0, ...(read ? { newPages: undefined } : {}) }))
    if (!n) store.toast("Couldn't find those chapters")
  }

  return (
    <div className="page">
      <div className="entry__top">
        <IconButton icon="back" label="Back" onClick={() => nav.back('/')} />
        {server && <span className="row-gap">
          <IconButton icon="bell" label="Titles that get new chapters" badge={followedCount || undefined} onClick={() => setFollowing(true)} />
          <IconButton icon="refresh" label="Check for new chapters" active={!!store.updating} onClick={() => void check()} />
        </span>}
      </div>
      <header className="pad-x pad-t">
        <h1 className="h1">Updates</h1>
      </header>
      {store.updating && <div className="pad-x pad-t-sm"><Banner tone="busy">Checking for new chapters and pages… {store.updating.done} of {store.updating.total}</Banner></div>}

      {error && <div className="pad-x pad-t"><Empty icon="alert" tone="error" title="Couldn't load updates" detail={error} action={{ label: 'Try again', onClick: () => void reloadUpdates(store) }} /></div>}
      {!items && !error && <div className="pad-x pad-t"><Loading label="Loading updates" shape="rows" /></div>}
      {server && !followedCount && <div className="pad-x pad-t-sm"><Empty compact icon="bell" title="No titles get new chapters" detail="Pick the titles to check for new chapters and pages." action={{ label: 'Pick titles', onClick: () => setFollowing(true) }} /></div>}
      {items && !items.length && !loading && followedCount > 0 && <div className="pad-x pad-t"><Empty icon="bell" title="No updates" detail="New chapters, and new pages in recent chapters, of the titles you picked show up here." /></div>}
      {items && items.length > 0 && <p className="hint pad-x">Long-press a chapter for more.</p>}

      {groups.map(([day, list]) => {
        const unread = list.filter((u) => !u.read)
        return (
          <section key={day} className="section section--tight pad-x">
            <div className="section-head section-head--flush">
              <div className="label label--flush">{day}</div>
              {unread.length > 0 && <button type="button" className="link-btn" onClick={() => void setRead(unread, true)}>Mark all read</button>}
            </div>
            <div className="check-list">
              {list.map((u) => <UpdateRow key={u.key} u={u} fresh={u.at > newSince && !u.read} busy={opening === u.key} press={press(u)} onOpen={() => void open(u)} />)}
            </div>
          </section>
        )
      })}

      {following && <FollowSheet onClose={() => { setFollowing(false); void reloadUpdates(store) }} />}
      <Sheet open={!!sheet} title={sheet ? `${store.entry(sheet.entryId)?.title ?? ''} · ${sheet.label}` : ''} onClose={() => setSheet(null)}>
        {sheet && (
          <div className="menu">
            <MenuRow icon="play" title="Read" onClick={() => { setSheet(null); void open(sheet) }} />
            <MenuRow icon={sheet.read ? 'undo' : 'check'} title={sheet.read ? 'Mark unread' : 'Mark read'} onClick={() => { setSheet(null); void setRead([sheet], !sheet.read) }} />
            {server && <MenuRow icon="download" title="Download" detail="Save it on this device for offline reading" onClick={() => { setSheet(null); void each([sheet], (id, ids) => store.downloadChapters(id, ids)) }} />}
            <MenuRow icon="book" title="Open title" onClick={() => { setSheet(null); nav.go(`/entry/${sheet.entryId}`) }} />
          </div>
        )}
      </Sheet>
    </div>
  )
}

function MenuRow({ icon, title, detail, onClick }: { icon: IconName; title: string; detail?: string; onClick: () => void }) {
  return (
    <button type="button" className="menu__row" onClick={onClick}>
      <span className="menu__icon"><Icon name={icon} size={20} /></span>
      <span className="menu__text"><strong>{title}</strong>{detail && <span>{detail}</span>}</span>
    </button>
  )
}

/**
 * "Get new chapters" (like native Midoku): only the titles picked here are checked for new chapters and
 * pages. New titles start unpicked. Tap Add titles to pick more from the library.
 */
function FollowSheet({ onClose }: { onClose: () => void }) {
  const store = useStore()
  const [adding, setAdding] = useState(false)
  const [q, setQ] = useState('')
  const [picked, setPicked] = useState<string[]>([])
  const lib = store.entries.filter((e) => e.inLibrary && e.remote)
  const isOn = (id: string) => !!store.entry(id)?.sources.some((s) => s.following)
  const needle = q.trim().toLowerCase()
  const match = (t: string) => !needle || t.toLowerCase().includes(needle)
  const on = lib.filter((e) => isOn(e.id) && match(e.title)).sort((a, b) => a.title.localeCompare(b.title))
  const off = lib.filter((e) => !isOn(e.id) && match(e.title)).sort((a, b) => a.title.localeCompare(b.title))
  const total = lib.filter((e) => isOn(e.id)).length
  const row = (e: (typeof lib)[number], end: React.ReactNode) => (
    <div key={e.id} className="order-row">
      <Cover art={e.art} title={e.title} url={e.coverUrl} className="order-row__cover" />
      <span className="check-row__name check-row__name--stack grow"><strong className="ellipsis">{e.title}</strong>
        <span className="card-meta ellipsis">{e.parentId ? `in ${store.entry(e.parentId)?.title ?? 'a series'} · ` : ''}{e.sources.find((s) => s.main)?.name ?? ''}</span></span>
      {end}
    </div>
  )

  if (adding) return (
    <Sheet open tall title="Add titles" onClose={() => setAdding(false)}>
      <label className="field"><Icon name="search" size={18} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search your library" aria-label="Search your library" /></label>
      {off.length > 1 && <button type="button" className="link-btn" onClick={() => setPicked(picked.length === off.length ? [] : off.map((e) => e.id))}>{picked.length === off.length ? 'Pick none' : 'Pick all'}</button>}
      {!off.length && <Empty compact icon="check" title={needle ? 'No matches' : 'Every title gets new chapters'} />}
      <div className="check-list pad-t-sm">
        {off.map((e) => row(e, <input type="checkbox" className="check-input" checked={picked.includes(e.id)} aria-label={`Pick ${e.title}`}
          onChange={() => setPicked((p) => (p.includes(e.id) ? p.filter((x) => x !== e.id) : [...p, e.id]))} />))}
      </div>
      <div className="sheet__actions sheet__actions--sticky">
        <button type="button" className="btn btn--ghost" onClick={() => setAdding(false)}>Back</button>
        <button type="button" className="btn btn--accent" disabled={!picked.length} onClick={() => {
          store.setFollow(picked, true)
          store.toast(`${picked.length} title${picked.length === 1 ? '' : 's'} will get new chapters`)
          setPicked([]); setQ(''); setAdding(false)
        }}>Add{picked.length ? ` ${picked.length}` : ''}</button>
      </div>
    </Sheet>
  )

  return (
    <Sheet open tall title="Get new chapters" onClose={onClose}>
      <p className="hint">Only these titles are checked for new chapters and pages. Titles you add to the library start off.</p>
      <div className="sheet__actions sheet__actions--flush">
        <button type="button" className="btn btn--ghost" disabled={!total} onClick={() => {
          if (!window.confirm(`Stop new chapters for all ${total} titles?`)) return
          store.setFollow(lib.map((e) => e.id), false)
        }}><Icon name="x" size={15} />Stop all</button>
        <button type="button" className="btn btn--accent" onClick={() => { setQ(''); setAdding(true) }}><Icon name="plus" size={15} />Add titles</button>
      </div>
      {total > 8 && <label className="field pad-t-sm"><Icon name="search" size={18} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search followed titles" aria-label="Search followed titles" /></label>}
      {!on.length && <div className="pad-t"><Empty compact icon="bell" title={needle ? 'No matches' : 'No titles yet'} detail={needle ? undefined : 'Add the titles you want new chapters for.'} /></div>}
      <div className="check-list pad-t-sm">
        {on.map((e) => row(e, <button type="button" className="icon-btn icon-btn--sm" aria-label={`Stop new chapters for ${e.title}`} onClick={() => store.setFollow([e.id], false)}><Icon name="x" size={16} /></button>))}
      </div>
    </Sheet>
  )
}
