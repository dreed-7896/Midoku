/** Reading and Completed are worked out from reading progress; the others are set by hand. */
export type Status = 'reading' | 'planned' | 'onhold' | 'completed' | 'dropped'
export type ManualStatus = Exclude<Status, 'reading' | 'completed'>

export const STATUS_LABEL: Record<Status, string> = {
  reading: 'Reading',
  planned: 'Planned',
  onhold: 'On hold',
  completed: 'Completed',
  dropped: 'Dropped',
}

/** Details edited in Midoku; they win over what the server says. */
export interface CustomDetails {
  title?: string
  author?: string
  description?: string
  /** An image address or a picture saved as a data URL. */
  cover?: string
  status?: ManualStatus
  /** Reading mode for this title; the device default is used without one. */
  reader?: ReaderMode
}

export type ReaderMode = 'webtoon' | 'paged' | 'rtl'
export const READER_LABEL: Record<ReaderMode, string> = { webtoon: 'Webtoon', paged: 'Paged', rtl: 'Right to left' }

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
  /** Every physical chapter (one per linked source) stacked in this slot. */
  alts?: ChapterVersion[]
  /** This version was picked by hand instead of the main source's. */
  preferred?: boolean
  /** Pages shown, within the physical chapter (1-based, inclusive): a part of a split chapter, or a chapter with excluded pages. */
  range?: [number, number]
  /** Pages left out (physical page numbers). */
  skip?: number[]
  /** For parts: the id of the whole chapter they come from. */
  physicalId?: string
  /** A chapter inserted from another title or source (row id in Midoku's database). */
  insertId?: string
  /** Place in the reading order set by hand (replaces the number for ordering). */
  order?: number
  /** Number before any move, from the source. */
  sourceNumber?: number
}

export interface ChapterVersion { sourceId: string; url: string; remoteId: number; name: string; title: string }

export interface InsertedChapter {
  id: string
  sourceId: string
  mangaUrl: string
  chapterUrl: string
  remoteId?: number
  number: number
  label: string
  fromTitle: string
}

export interface EntrySource {
  sourceId: string
  /** The title on that source: its id on the current server and its address on the source. */
  mangaId?: number
  mangaUrl?: string
  chapters: number
  following: boolean
  main?: boolean
  /** Merged titles: sources in the same segment are versions; segments follow each other. */
  segment?: number
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
  /** Page layouts: chapter key (source + url) → where parts start and which pages are left out. */
  splits?: Record<string, PageLayout>
  /** Chapters placed in from other titles or sources. */
  inserted?: InsertedChapter[]
  /** Chapter totals from the library list, used before the chapters themselves are loaded. */
  counts?: { total: number; unread: number }
  /** Edited details, kept over the server's. */
  custom?: CustomDetails
  /** Order inside a series. */
  position?: number
  /** Merged titles: chapters numbered 1, 2, 3… */
  renumber?: boolean
  /** The details as the server gives them, before edits. */
  original?: { title: string; author: string; description: string; coverUrl?: string }
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

/** How a chapter's pages are shown: `breaks` = first page of every part after the first, `skip` = pages left out. */
export interface PageLayout { breaks: number[]; skip: number[] }
