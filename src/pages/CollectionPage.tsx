import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { IconButton } from '../components/Chrome'
import { Icon } from '../components/Icon'
import { EntryGrid } from '../components/LibraryCards'
import { useNav } from '../components/Nav'
import { newCount, useStore } from '../data/store'
import type { SortBy } from '../data/types'
import { nextSort, sorter, SORT_LABEL } from './Library'

/** One collection (root folder) opened. */
export default function CollectionPage() {
  const { id = '' } = useParams()
  const store = useStore()
  const nav = useNav()
  const [sort, setSort] = useState<SortBy>('recent')
  const collection = store.collection(id)

  if (!collection) {
    return (
      <div className="page pad-x">
        <div className="entry__top"><IconButton icon="back" label="Back" onClick={() => nav.back('/library')} /></div>
        <p className="empty">This collection no longer exists.</p>
      </div>
    )
  }

  const entries = store.entries.filter((e) => e.inLibrary && !e.parentId && e.collections.includes(id)).sort(sorter(sort))
  const fresh = entries.reduce((n, e) => n + newCount(e), 0)

  const rename = () => {
    const name = window.prompt('Rename collection', collection.name)
    if (name?.trim()) store.renameCollection(id, name.trim())
  }
  const remove = () => {
    if (window.confirm(`Delete “${collection.name}”? Its titles stay in your library.`)) {
      store.deleteCollection(id)
      store.toast(`Deleted “${collection.name}”`)
      nav.back('/library')
    }
  }

  return (
    <div className="page">
      <div className="entry__top">
        <IconButton icon="back" label="Back to library" onClick={() => nav.back('/library')} />
        <div className="row-gap">
          <IconButton icon="settings" label="Rename collection" onClick={rename} />
          <IconButton icon="trash" label="Delete collection" onClick={remove} />
        </div>
      </div>
      <header className="pad-x pad-t">
        <div className="kicker"><Icon name="folder" size={13} stroke={2} /> Collection · {entries.length} titles{fresh ? ` · ${fresh} new` : ''}</div>
        <h1 className="h1">{collection.name}</h1>
      </header>
      <div className="chips pad-x pad-t">
        <button type="button" className="chip" onClick={() => setSort(nextSort(sort))}><Icon name="sort" size={14} stroke={2} />{SORT_LABEL[sort]}</button>
      </div>
      <section className="section pad-x">
        {entries.length === 0
          ? <p className="empty">No titles yet. Add titles from their details page.</p>
          : <EntryGrid entries={entries} />}
      </section>
    </div>
  )
}
