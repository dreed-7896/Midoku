export type Status = 'planned' | 'reading' | 'completed' | 'onHold' | 'dropped'

export const STATUS_LABEL: Record<Status, string> = {
  planned: 'Planned',
  reading: 'Reading',
  completed: 'Completed',
  onHold: 'On hold',
  dropped: 'Dropped',
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
}

export interface EntrySource {
  sourceId: string
  chapters: number
  following: boolean
  main?: boolean
}

export interface Entry {
  id: string
  title: string
  author: string
  art: CoverArt
  publishing: 'Ongoing' | 'Completed' | 'Hiatus'
  status: Status
  categories: string[]
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
  progress: 'any' | 'notStarted' | 'inProgress' | 'completed'
  tag?: string
}

export type GroupBy = 'category' | 'status' | 'source' | 'none'
export type SortBy = 'recent' | 'title' | 'added' | 'updated'

export type LibraryTab =
  | { id: string; kind: 'reading'; name: string }
  | { id: string; kind: 'all'; name: string }
  | { id: string; kind: 'smart'; name: string; filters: LibraryFilters }
  | { id: string; kind: 'group'; name: string; entryIds: string[] }
