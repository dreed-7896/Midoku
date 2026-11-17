import { useEffect, useMemo, useState } from 'react'
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
  // What was new when the screen opened stays marked while it's open; leaving clears the badge.
  const [newSince] = useState(seenAt)
  useEffect(() => { markUpdatesSeen(); return () => markUpdatesSeen() }, [])

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
        {server && <IconButton icon="refresh" label="Check for new chapters" active={!!store.updating} onClick={() => void check()} />}
      </div>
      <header className="pad-x pad-t">
        <h1 className="h1">Updates</h1>
      </header>
      {store.updating && <div className="pad-x pad-t-sm"><Banner tone="busy">Checking for new chapters and pages… {store.updating.done} of {store.updating.total}</Banner></div>}

      {error && <div className="pad-x pad-t"><Empty icon="alert" tone="error" title="Couldn't load updates" detail={error} action={{ label: 'Try again', onClick: () => void reloadUpdates(store) }} /></div>}
      {!items && !error && <div className="pad-x pad-t"><Loading label="Loading updates" shape="rows" /></div>}
      {items && !items.length && !loading && <div className="pad-x pad-t"><Empty icon="bell" title="No updates" detail="New chapters, and new pages in recent chapters, from your library show up here." /></div>}
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
