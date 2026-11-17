// Talks to a Suwayomi server straight from the browser. Suwayomi allows any origin (without cookies),
// so no proxy sits in between; the address and optional basic-auth login are kept on this device.
import { getSettings } from './settings'
import type { Chapter, CoverArt, Entry } from './types'

export interface SExtension {
  pkgName: string
  name: string
  lang: string
  iconUrl: string
  versionName: string
  isInstalled: boolean
  hasUpdate: boolean
  isNsfw: boolean
  source?: { nodes: SSource[] }
}

export interface SSource {
  id: string
  name: string
  displayName: string
  lang: string
  iconUrl: string
  supportsLatest: boolean
  isNsfw: boolean
}

export interface SMangaCard {
  id: number
  url: string
  title: string
  thumbnailUrl: string | null
}

export interface SManga extends SMangaCard {
  author: string | null
  artist: string | null
  description: string | null
  genre: string[]
  status: string
  realUrl: string | null
  sourceId: string
  initialized: boolean
  source?: { id: string; displayName: string; iconUrl: string; lang: string } | null
  chapters?: { totalCount: number }
  latestUploadedChapter?: { uploadDate: string } | null
}

export interface SChapter {
  id: number
  url: string
  name: string
  chapterNumber: number
  uploadDate: string
  scanlator: string | null
  pageCount: number
  sourceOrder: number
}

const EXT = 'pkgName name lang iconUrl versionName isInstalled hasUpdate isNsfw'
const SRC = 'id name displayName lang iconUrl supportsLatest isNsfw'
const CARD = 'id url title thumbnailUrl'
const MANGA = `${CARD} author artist description genre status realUrl sourceId initialized source { id displayName iconUrl lang }`
// Only what the source says. Reading state on the server is ignored; Midoku keeps its own.
const SUMMARY = `${MANGA} chapters { totalCount } latestUploadedChapter { uploadDate }`
const CHAPTER = 'id url name chapterNumber uploadDate scanlator pageCount sourceOrder'

export const isConnected = () => !!getSettings().serverUrl

const normalise = (url: string) => url.trim().replace(/\/+$/, '')
const serverBase = () => normalise(getSettings().serverUrl)

export function authHeaders(user = getSettings().serverUser, pass = getSettings().serverPass): Record<string, string> {
  return user ? { Authorization: `Basic ${btoa(`${user}:${pass}`)}` } : {}
}

export const needsAuthForImages = () => !!getSettings().serverUser

/** Server paths (covers, pages, icons) become absolute URLs on the server. */
export function assetUrl(path?: string | null): string {
  if (!path) return ''
  return /^https?:\/\//.test(path) ? path : `${serverBase()}${path.startsWith('/') ? '' : '/'}${path}`
}

/** Fetches an image with the login attached (for servers with basic auth). */
export async function fetchImage(url: string, signal?: AbortSignal): Promise<Blob> {
  const res = await fetch(url, { headers: authHeaders(), signal })
  if (!res.ok) throw new Error(`Image failed (${res.status})`)
  return res.blob()
}

async function request<T>(base: string, headers: Record<string, string>, query: string, variables?: Record<string, unknown>): Promise<T> {
  let res: Response
  try {
    res = await fetch(`${base}/api/graphql`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json', ...headers },
      body: JSON.stringify({ query, variables }),
    })
  } catch {
    throw new Error("Can't reach the server. Check the address, and that it uses https.")
  }
  if (res.status === 401) throw new Error('The server needs a username and password.')
  if (!res.ok) throw new Error(`The server answered ${res.status}.`)
  const json = await res.json().catch(() => null)
  if (!json) throw new Error("That address didn't answer like a Suwayomi server.")
  if (json.errors?.length) throw new Error(json.errors[0].message)
  return json.data as T
}

export const gql = <T>(query: string, variables?: Record<string, unknown>) => request<T>(serverBase(), authHeaders(), query, variables)

/** Checks an address before it is saved. */
export async function testServer(url: string, user: string, pass: string) {
  const data = await request<{ aboutServer: { name: string; version: string } }>(
    normalise(url), authHeaders(user, pass), '{ aboutServer { name version } }',
  )
  return data.aboutServer
}

// Extensions and sources

export const getExtensions = () =>
  gql<{ extensions: { nodes: SExtension[] } }>(`{ extensions { nodes { ${EXT} } } }`).then((d) => d.extensions.nodes)

export const refreshExtensions = () =>
  gql<{ fetchExtensions: { extensions: SExtension[] } }>(`mutation { fetchExtensions(input: {}) { extensions { ${EXT} } } }`)
    .then((d) => d.fetchExtensions.extensions)

export const changeExtension = (pkgName: string, action: 'install' | 'uninstall' | 'update') =>
  gql(`mutation($id: String!) { updateExtension(input: { id: $id, patch: { ${action}: true } }) { extension { pkgName } } }`, { id: pkgName })

// Suwayomi's extensions(condition:) ignores pkgName, so one extension is read with extension(pkgName:).
export const getExtensionSources = (pkgName: string) =>
  gql<{ extension: SExtension | null }>(
    `query($pkg: String!) { extension(pkgName: $pkg) { ${EXT} source { nodes { ${SRC} } } } }`, { pkg: pkgName },
  ).then((d) => d.extension)

/** Multi-language ("all") first, then English, then the rest A–Z. */
export function byLanguage<T extends { lang: string }>(list: T[]): T[] {
  const rank = (l: string) => (l === 'all' ? 0 : l === 'en' ? 1 : 2)
  return [...list].sort((a, b) => rank(a.lang) - rank(b.lang) || a.lang.localeCompare(b.lang))
}

/** Installed sources, without Suwayomi's built-in "Local source". */
export const getSources = () =>
  gql<{ sources: { nodes: (SSource & { extension: { pkgName: string } | null })[] } }>(`{ sources { nodes { ${SRC} extension { pkgName } } } }`)
    .then((d) => d.sources.nodes.filter((s) => s.id !== '0'))

export const browseSource = (source: string, type: 'POPULAR' | 'LATEST' | 'SEARCH', page: number, query?: string) =>
  gql<{ fetchSourceManga: { hasNextPage: boolean; mangas: SMangaCard[] } }>(
    `mutation($source: LongString!, $type: FetchSourceMangaType!, $page: Int!, $query: String) {
      fetchSourceManga(input: { source: $source, type: $type, page: $page, query: $query }) { hasNextPage mangas { ${CARD} } }
    }`,
    { source, type, page, query },
  ).then((d) => d.fetchSourceManga)

// Titles and chapters

/** Stored details, refreshed from the source when the server has not fetched them yet. */
export async function getManga(id: number, refresh = false): Promise<SManga> {
  if (!refresh) {
    const { manga } = await gql<{ manga: SManga }>(`query($id: Int!) { manga(id: $id) { ${SUMMARY} } }`, { id })
    if (manga.initialized) return manga
  }
  await gql(`mutation($id: Int!) { fetchManga(input: { id: $id }) { manga { id } } }`, { id })
  return (await gql<{ manga: SManga }>(`query($id: Int!) { manga(id: $id) { ${SUMMARY} } }`, { id })).manga
}

export async function getChapters(mangaId: number, refresh = false): Promise<SChapter[]> {
  if (!refresh) {
    const { manga } = await gql<{ manga: { chapters: { nodes: SChapter[] } } }>(
      `query($id: Int!) { manga(id: $id) { chapters { nodes { ${CHAPTER} } } } }`, { id: mangaId },
    )
    if (manga.chapters.nodes.length) return manga.chapters.nodes
  }
  const d = await gql<{ fetchChapters: { chapters: SChapter[] } }>(
    `mutation($id: Int!) { fetchChapters(input: { mangaId: $id }) { chapters { ${CHAPTER} } } }`, { id: mangaId },
  )
  return d.fetchChapters.chapters
}

/** Chapter totals and newest upload for titles in the library, by server id. */
export const getMangaSummaries = (ids: number[]) =>
  ids.length
    ? gql<{ mangas: { nodes: SManga[] } }>(`query($ids: [Int!]) { mangas(filter: { id: { in: $ids } }) { nodes { ${SUMMARY} } } }`, { ids })
      .then((d) => d.mangas.nodes)
    : Promise.resolve([])

/** The server's copy of a source title, found by the source and the title's address on it. */
export const findManga = (sourceId: string, url: string) =>
  gql<{ mangas: { nodes: SManga[] } }>(
    `query($s: LongString!, $u: String!) { mangas(filter: { sourceId: { equalTo: $s }, url: { equalTo: $u } }) { nodes { ${SUMMARY} } } }`,
    { s: sourceId, u: url },
  ).then((d) => d.mangas.nodes[0])

/**
 * Finds a title on this server again (after a reinstall or a move to another server, its id changes).
 * When the server has never seen it, a search on the source by title adds it, then it is looked up again.
 */
export async function resolveManga(sourceId: string, url: string, title: string): Promise<SManga | undefined> {
  const found = await findManga(sourceId, url)
  if (found) return found
  await browseSource(sourceId, 'SEARCH', 1, title)
  return findManga(sourceId, url)
}

/** Page image URLs for a chapter. */
export const getPages = (chapterId: number) =>
  gql<{ fetchChapterPages: { pages: string[] } }>(
    `mutation($id: Int!) { fetchChapterPages(input: { chapterId: $id }) { pages } }`, { id: chapterId },
  ).then((d) => d.fetchChapterPages.pages.map(assetUrl))

// Mapping server data onto the app's model

const PALETTE: CoverArt[] = [
  { c1: '#1E2A44', c2: '#E9B872', ink: '#F4EBDD', motif: 'sun' },
  { c1: '#4A1F2E', c2: '#F27A6B', ink: '#FBE3DC', motif: 'moon' },
  { c1: '#17423A', c2: '#F2C14E', ink: '#EAF4EE', motif: 'dot' },
  { c1: '#2A2148', c2: '#7FA7FF', ink: '#E6E8FF', motif: 'ring' },
  { c1: '#12343F', c2: '#8FD3C7', ink: '#E2F5F1', motif: 'sun' },
  { c1: '#3A2340', c2: '#E58FD0', ink: '#F8E5F3', motif: 'dot' },
]
export const artFor = (id: number): CoverArt => PALETTE[id % PALETTE.length]

const HOUR = 3_600_000
export const hoursSince = (ms?: string | number | null) => {
  const n = Number(ms)
  return n > 0 ? Math.max(0, (Date.now() - n) / HOUR) : undefined
}

function publishing(status: string): Entry['publishing'] {
  if (status === 'COMPLETED' || status === 'PUBLISHING_FINISHED') return 'Completed'
  if (status === 'ON_HIATUS') return 'Hiatus'
  return 'Ongoing'
}

export function toChapter(c: SChapter, sourceId: string): Chapter {
  const known = c.chapterNumber >= 0
  const label = known ? `Ch. ${Number(c.chapterNumber.toFixed(2))}` : c.name
  const uploaded = Number(c.uploadDate)
  return {
    id: `c${c.id}`,
    remoteId: c.id,
    // Unknown numbers fall back to the source order (sources list newest first).
    number: known ? c.chapterNumber : -c.sourceOrder,
    label,
    title: c.scanlator ? `${c.name} · ${c.scanlator}` : c.name,
    date: uploaded > 0 ? new Date(uploaded).toLocaleDateString('en', { month: 'short', day: 'numeric' }) : '',
    pages: c.pageCount > 0 ? c.pageCount : 0,
    // Progress and marks come from Midoku's database, not from the server.
    page: 0,
    read: false,
    bookmarked: false,
    // Downloads are Midoku's own, on this device (see downloads.ts).
    downloaded: false,
    isNew: uploaded > Date.now() - 7 * 24 * HOUR,
    sourceUrl: c.url,
    versions: 1,
    sourceId,
    layout: c.id % 4,
  }
}

export function toEntry(m: SManga, chapters?: SChapter[]): Entry {
  const total = chapters?.length ?? m.chapters?.totalCount ?? 0
  return {
    id: `s${m.id}`,
    title: m.title,
    author: m.author || m.artist || '',
    art: artFor(m.id),
    coverUrl: assetUrl(m.thumbnailUrl),
    publishing: publishing(m.status),
    tabs: [],
    tags: m.genre ?? [],
    description: m.description ?? '',
    sources: [{
      sourceId: m.sourceId, mangaId: m.id, mangaUrl: m.url, chapters: total, following: true, main: true,
      name: m.source?.displayName, iconUrl: m.source?.iconUrl ? assetUrl(m.source.iconUrl) : undefined,
    }],
    chapters: (chapters ?? []).map((c) => toChapter(c, m.sourceId)),
    inLibrary: false,
    updatedAgo: hoursSince(m.latestUploadedChapter?.uploadDate) ?? 1e6,
    addedOrder: m.id,
    coverPath: m.thumbnailUrl ?? undefined,
    remote: { mangaId: m.id, sourceId: m.sourceId, mangaUrl: m.url, url: m.realUrl ?? undefined, chaptersLoaded: !!chapters },
    counts: { total, unread: total },
  }
}
