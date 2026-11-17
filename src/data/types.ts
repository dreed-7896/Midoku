/** Worked out from reading progress: completed once every chapter is read. */
export type Status = 'reading' | 'completed'

export const STATUS_LABEL: Record<Status, string> = {
  reading: 'Reading',
  completed: 'Completed',
}

export interface CoverArt {
  c1: string
  c2: string
  ink: string
  motif: 'sun' | 'moon' | 'dot' | 'ring'
}

export interface Source {
  id: string
  name: string
  letter: string
  color: string
  glow: string
  lang: string
  langs: string[]
  version: string
  installed: boolean
  pinned: boolean
  update: boolean
  warn?: 'cloudflare' | 'error'
  nsfw?: boolean
}

export interface Chapter {
  id: string
  number: number
  label: string
  title: string
  date: string
  pages: number
  /** Page the reader stopped on; 0 when not started. */
  page: number
  read: boolean
  bookmarked: boolean
  downloaded: boolean
  isNew: boolean
  /** Number of physical chapters (source variants) stacked in this slot. */
  versions: number
  sourceId: string
  insertedFrom?: string
  part?: string
  removed?: boolean
  layout: number
  /** Suwayomi chapter id, for chapters that come from the server. */
  remoteId?: number
  /** The source's chapter url; reading state in Midoku's database is keyed by it. */
  sourceUrl?: string
}

export interface EntrySource {
  sourceId: string
  chapters: number
  following: boolean
  main?: boolean
  /** Shown when the source is not in the local source list (server sources). */
  name?: string
  iconUrl?: string
}

export interface Entry {
  id: string
  title: string
  author: string
  art: CoverArt
  publishing: 'Ongoing' | 'Completed' | 'Hiatus'
  /** Ids of the library tabs (categories) this entry shows in. */
  tabs: string[]
  tags: string[]
  description: string
  sources: EntrySource[]
  parentId?: string
  chapters: Chapter[]
  inLibrary: boolean
  /** Hours since it was last read; undefined when never read. */
  lastReadAgo?: number
  /** Hours since new chapters arrived. */
  updatedAgo: number
  addedOrder: number
  /** Real cover image; the drawn placeholder is used until it loads. */
  coverUrl?: string
  /** Server path of the cover, kept in Midoku's database. */
  coverPath?: string
  /** Set for titles that come from the Suwayomi server. */
  remote?: { mangaId: number; sourceId: string; mangaUrl: string; url?: string; chaptersLoaded: boolean }
  /** Row id in Midoku's database once the title has been saved there. */
  dbId?: string
  /** Chapter totals from the library list, used before the chapters themselves are loaded. */
  counts?: { total: number; unread: number }
}

export interface CatalogItem {
  id: string
  title: string
  art: CoverArt
  entryId?: string
  publishing: string
}

export interface LibraryFilters {
  statuses: Status[]
  newOnly: boolean
  tag?: string
}

export type GroupBy = 'tab' | 'status' | 'source' | 'none'
export type SortBy = 'recent' | 'title' | 'added' | 'updated'

export type LibraryTab =
  | { id: string; kind: 'reading'; name: string }
  | { id: string; kind: 'all'; name: string }
  /** A category the person files titles into. */
  | { id: string; kind: 'tab'; name: string }
  /** Saved filters that update as the library changes. */
  | { id: string; kind: 'smart'; name: string; filters: LibraryFilters }
