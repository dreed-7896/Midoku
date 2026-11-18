// "This device" as the server: the same calls as the Suwayomi client, answered by Aidoku extensions running in
// the iOS shell (plugins/midoku-sources, bridged in device.ts). Titles and chapters get stable numeric ids hashed
// from source key + key, so the store, the database (server_manga_id) and downloads work unchanged.
import { deviceImage, DChapter, DManga, DSource, hasDeviceSources, MidokuSources } from './device'
import type { SChapter, SExtension, SManga, SMangaCard, SRecentChapter, SSource } from './suwayomi'

/** settings.serverUrl value that selects the device. */
export const DEVICE = 'device'

// Ids

function fnv(text: string, seed: number) {
  let h = seed >>> 0
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 16777619) >>> 0
  }
  return h >>> 0
}
/** 31 bits: it is stored in entry_sources.server_manga_id (integer). */
const mangaIdFor = (source: string, key: string) => (fnv(`${source}\u0000${key}`, 2166136261) >>> 1) || 1
/** 52 bits: chapter ids stay on the device, so they can be wider. */
const chapterIdFor = (source: string, manga: string, key: string) => {
  const text = `${source}\u0000${manga}\u0000${key}`
  return fnv(text, 2166136261) * 2 ** 20 + (fnv(text, 84696351) >>> 12)
}

// What the device knows about titles and chapters (kept across launches; small)

interface KnownManga { s: string; k: string; m: Partial<Omit<DManga, 'chapters'>>; n?: number; l?: number }
type KnownChapter = [mangaId: number, key: string, url: string | null]

const M_KEY = 'midoku.dev.m'
const C_KEY = 'midoku.dev.c'
const R_KEY = 'midoku.dev.repos'
const read = <T,>(key: string, fallback: T): T => { try { return JSON.parse(localStorage.getItem(key) ?? '') as T } catch { return fallback } }
const known: Record<number, KnownManga> = read(M_KEY, {})
const knownChapters: Record<number, KnownChapter> = read(C_KEY, {})
let saveTimer: ReturnType<typeof setTimeout> | undefined
function save() {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    try {
      localStorage.setItem(M_KEY, JSON.stringify(known))
      localStorage.setItem(C_KEY, JSON.stringify(knownChapters))
    } catch { /* storage full: ids are worked out again from the source */ }
  }, 400)
}

const chapterLists = new Map<number, { at: number; list: DChapter[] }>()

function remember(m: DManga): number {
  const id = mangaIdFor(m.sourceKey, m.key)
  const { chapters: _drop, ...rest } = m
  const prev = known[id]
  // Search results carry less than a details fetch: keep what we had.
  known[id] = { ...prev, s: m.sourceKey, k: m.key, m: { ...prev?.m, ...stripEmpty(rest) } }
  save()
  return id
}
function stripEmpty<T extends object>(o: T): Partial<T> {
  return Object.fromEntries(Object.entries(o).filter(([, v]) => v != null && v !== '' && !(Array.isArray(v) && !v.length))) as Partial<T>
}

function mangaFor(id: number): DManga {
  const k = known[id]
  if (!k) throw new Error('This title is not known on this device yet. Open it from its source again.')
  return { status: 0, contentRating: 0, viewer: 0, updateStrategy: 0, url: undefined, ...k.m, sourceKey: k.s, key: k.k, title: k.m.title ?? '' }
}

/** The engine's decoder needs these keys present, even when empty. */
const bridgeManga = (m: DManga) => ({ ...m, url: m.url ?? null, chapters: undefined })
const bridgeChapter = (c: DChapter) => ({ ...c, url: c.url ?? null, dateUploaded: c.dateUploaded ?? null })

// Images: an https-looking address (so Cache Storage accepts it) that fetchImage hands to the plugin.

const IMG = 'https://device.midoku.invalid/img'
export const isDeviceImage = (url: string) => url.startsWith(IMG)
export function deviceImageUrl(source: string, url: string | undefined | null, context?: Record<string, string>, cover = false): string | null {
  if (!url) return null
  if (url.startsWith('data:')) return url
  const q = new URLSearchParams({ s: source, u: url })
  if (context && Object.keys(context).length) q.set('c', JSON.stringify(context))
  if (cover) q.set('cover', '1')
  return `${IMG}?${q}`
}
export async function fetchDeviceImage(url: string): Promise<Blob> {
  if (url.startsWith('data:')) return (await fetch(url)).blob()
  const q = new URL(url).searchParams
  const context = q.get('c') ? JSON.parse(q.get('c')!) as Record<string, string> : undefined
  return deviceImage(q.get('s')!, q.get('u')!, context, q.get('cover') === '1')
}

// Mapping

const STATUS = ['UNKNOWN', 'ONGOING', 'COMPLETED', 'CANCELLED', 'ON_HIATUS']
const iconCache = new Map<string, string>()

function toCard(m: DManga): SMangaCard {
  const id = remember(m)
  return { id, url: m.key, title: m.title, thumbnailUrl: deviceImageUrl(m.sourceKey, m.cover, undefined, true) }
}

async function toManga(id: number): Promise<SManga> {
  const k = known[id]
  const m = mangaFor(id)
  const source = (await installedSources()).find((s) => s.key === m.sourceKey)
  return {
    id,
    url: m.key,
    title: m.title,
    thumbnailUrl: deviceImageUrl(m.sourceKey, m.cover, undefined, true),
    author: m.authors?.join(', ') || null,
    artist: m.artists?.join(', ') || null,
    description: m.description ?? null,
    genre: m.tags ?? [],
    status: STATUS[m.status] ?? 'UNKNOWN',
    realUrl: m.url ?? null,
    sourceId: m.sourceKey,
    initialized: true,
    source: source ? { id: source.key, displayName: source.name, iconUrl: source.icon ?? '', lang: langOf(source) } : null,
    chapters: { totalCount: k?.n ?? 0 },
    latestUploadedChapter: k?.l ? { uploadDate: String(k.l) } : null,
  }
}

function toChapter(mangaId: number, m: DManga, c: DChapter, index: number): SChapter {
  const id = chapterIdFor(m.sourceKey, m.key, c.key)
  knownChapters[id] = [mangaId, c.key, c.url ?? null]
  const number = c.chapterNumber ?? -1
  const name = c.title?.trim() || (c.chapterNumber != null ? `Chapter ${Number(c.chapterNumber.toFixed(2))}` : 'Chapter')
  return {
    id,
    url: c.key,
    name: c.volumeNumber != null && c.title == null ? `Vol. ${c.volumeNumber} ${name}` : name,
    chapterNumber: number,
    uploadDate: c.dateUploaded ? String(c.dateUploaded * 1000) : '0',
    scanlator: c.scanlators?.join(', ') || null,
    pageCount: 0,
    sourceOrder: index,
  }
}

const langOf = (s: DSource) => (s.languages.length === 1 ? s.languages[0] : 'all')

// Sources

let installedPromise: Promise<DSource[]> | undefined
function installedSources(force = false): Promise<DSource[]> {
  if (!installedPromise || force) {
    installedPromise = MidokuSources.installed().then((r) => r.sources)
    installedPromise.catch(() => { installedPromise = undefined })
  }
  return installedPromise
}

function toSource(s: DSource): SSource & { extension: { pkgName: string } } {
  if (s.icon) iconCache.set(s.key, s.icon)
  return {
    id: s.key, name: s.name, displayName: s.name, lang: langOf(s), iconUrl: s.icon ?? '',
    supportsLatest: s.listings.length > 1, isNsfw: s.contentRating === 2, baseUrl: s.urls[0] ?? null, isConfigurable: true,
    extension: { pkgName: s.key },
  }
}

export const devGetSources = async () => (await installedSources()).map(toSource)

// Repos and extensions

interface RepoSource {
  id: string; name: string; version: number; iconURL?: string; downloadURL?: string; languages?: string[]; contentRating?: number
  lang?: string; nsfw?: number; file?: string; icon?: string; repo: string
}

export const devGetRepos = async () => read<string[]>(R_KEY, [])
export async function devSetRepos(repos: string[]) {
  localStorage.setItem(R_KEY, JSON.stringify(repos))
  repoCache = undefined
  return repos
}

let repoCache: Promise<RepoSource[]> | undefined
async function loadRepo(url: string): Promise<RepoSource[]> {
  const get = async (u: string) => {
    const r = await MidokuSources.fetchText({ url: u })
    if (r.status >= 400) throw new Error(`${u} answered ${r.status}`)
    return JSON.parse(r.text) as unknown
  }
  let data: unknown
  try { data = await get(url) } catch { data = undefined }
  // Legacy lists: a folder with index.min.json in it.
  if (!data || (typeof data === 'object' && !Array.isArray(data) && !('sources' in data))) {
    data = await get(`${url.replace(/\/+$/, '')}/index.min.json`)
    url = `${url.replace(/\/+$/, '')}/`
  }
  const list = (Array.isArray(data) ? data : (data as { sources: unknown[] }).sources) as Omit<RepoSource, 'repo'>[]
  return list.map((s) => ({ ...s, repo: url }))
}
function repoSources(force = false) {
  if (!repoCache || force) {
    repoCache = devGetRepos().then(async (repos) => {
      const lists = await Promise.allSettled(repos.map(loadRepo))
      const all = lists.flatMap((l) => (l.status === 'fulfilled' ? l.value : []))
      // The newest version of each extension wins.
      const best = new Map<string, RepoSource>()
      for (const s of all) if (!best.has(s.id) || best.get(s.id)!.version < s.version) best.set(s.id, s)
      return [...best.values()]
    })
    repoCache.catch(() => { repoCache = undefined })
  }
  return repoCache
}
const resolve = (rel: string | undefined, base: string) => { try { return rel ? new URL(rel, base).toString() : '' } catch { return '' } }
const fileUrl = (s: RepoSource) => (s.downloadURL ? resolve(s.downloadURL, s.repo) : s.file ? resolve(`sources/${s.file}`, s.repo) : '')
const iconUrl = (s: RepoSource) => (s.iconURL ? resolve(s.iconURL, s.repo) : s.icon ? resolve(`icons/${s.icon}`, s.repo) : '')

async function extensions(force = false): Promise<SExtension[]> {
  const [repo, installed] = await Promise.all([repoSources(force), installedSources(force)])
  const byKey = new Map(installed.map((s) => [s.key, s]))
  const list: SExtension[] = repo.map((s) => {
    const have = byKey.get(s.id)
    const langs = s.languages ?? (s.lang ? [s.lang] : [])
    return {
      pkgName: s.id, name: s.name, lang: langs.length === 1 ? langs[0] : langs.length ? 'all' : 'all',
      iconUrl: have?.icon ?? iconUrl(s), versionName: String(s.version), isInstalled: !!have,
      hasUpdate: !!have && have.version < s.version, isNsfw: (s.contentRating ?? s.nsfw ?? 0) === 2,
    }
  })
  // Installed ones no repo lists any more.
  for (const s of installed) {
    if (!repo.some((r) => r.id === s.key)) {
      list.push({ pkgName: s.key, name: s.name, lang: langOf(s), iconUrl: s.icon ?? '', versionName: String(s.version), isInstalled: true, hasUpdate: false, isNsfw: s.contentRating === 2 })
    }
  }
  return list
}

export const devGetExtensions = () => extensions()
export const devRefreshExtensions = () => extensions(true)

export async function devChangeExtension(pkgName: string, action: 'install' | 'uninstall' | 'update') {
  if (action === 'uninstall') {
    await MidokuSources.uninstall({ key: pkgName })
  } else {
    const s = (await repoSources()).find((x) => x.id === pkgName)
    const url = s && fileUrl(s)
    if (!url) throw new Error('No repository offers this extension.')
    await MidokuSources.install({ url })
  }
  await installedSources(true)
  return { updateExtension: { extension: { pkgName } } }
}

export async function devGetExtensionSources(pkgName: string) {
  const ext = (await extensions()).find((e) => e.pkgName === pkgName)
  if (!ext) return null
  const installed = (await installedSources()).filter((s) => s.key === pkgName)
  return { ...ext, source: { nodes: installed.map(toSource) } }
}

// Browsing

export async function devBrowse(source: string, type: 'POPULAR' | 'LATEST' | 'SEARCH', page: number, query?: string) {
  const s = (await installedSources()).find((x) => x.key === source)
  if (!s) throw new Error('This extension is not installed on this device.')
  let result
  if (type === 'SEARCH' || !s.providesListings || !s.listings.length) {
    result = await MidokuSources.search({ key: source, query: type === 'SEARCH' ? query : undefined, page })
  } else {
    const pick = type === 'LATEST'
      ? s.listings.find((l) => /latest|update|new|recent/i.test(`${l.id} ${l.name}`)) ?? s.listings[1] ?? s.listings[0]
      : s.listings.find((l) => /popular|trend|hot|top/i.test(`${l.id} ${l.name}`)) ?? s.listings[0]
    result = await MidokuSources.listing({ key: source, id: pick.id, page })
  }
  return { hasNextPage: result.hasNextPage, mangas: result.entries.map(toCard) }
}

/** Details and chapters come in one call; the chapters wait for getChapters. */
async function refreshManga(id: number) {
  const m = mangaFor(id)
  const full = await MidokuSources.manga({ key: m.sourceKey, manga: bridgeManga(m) as DManga, details: true, chapters: true })
  remember({ ...full, sourceKey: m.sourceKey, key: m.key })
  if (full.chapters) storeChapters(id, full.chapters)
}

function storeChapters(id: number, list: DChapter[]) {
  chapterLists.set(id, { at: Date.now(), list })
  const k = known[id]
  if (k) {
    k.n = list.length
    k.l = Math.max(0, ...list.map((c) => (c.dateUploaded ?? 0) * 1000)) || undefined
  }
  save()
}

export async function devGetManga(id: number, refresh = false): Promise<SManga> {
  if (refresh || !chapterLists.has(id)) await refreshManga(id)
  return toManga(id)
}

const FRESH = 10 * 60_000
export async function devGetChapters(mangaId: number, refresh = false): Promise<SChapter[]> {
  const cached = chapterLists.get(mangaId)
  if (refresh || !cached || Date.now() - cached.at > FRESH) await refreshManga(mangaId)
  const m = mangaFor(mangaId)
  const list = chapterLists.get(mangaId)?.list ?? []
  const out = list.map((c, i) => toChapter(mangaId, m, c, i))
  save()
  return out
}

export async function devGetMangaSummaries(ids: number[]): Promise<SManga[]> {
  const out: SManga[] = []
  for (const id of ids) if (known[id]) out.push(await toManga(id))
  return out
}

export async function devFindManga(sourceId: string, url: string): Promise<SManga | undefined> {
  if (!(await installedSources()).some((s) => s.key === sourceId)) return undefined
  const id = mangaIdFor(sourceId, url)
  if (!known[id]) {
    known[id] = { s: sourceId, k: url, m: { sourceKey: sourceId, key: url, title: '', status: 0, contentRating: 0, viewer: 0, updateStrategy: 0 } }
    try { await refreshManga(id) } catch (e) { delete known[id]; throw e }
  }
  return toManga(id)
}

export async function devRecentChapters(mangaIds: number[], first = 150): Promise<SRecentChapter[]> {
  const all: SRecentChapter[] = []
  for (const id of mangaIds) {
    const list = chapterLists.get(id)?.list
    if (!list || !known[id]) continue
    const m = mangaFor(id)
    list.forEach((c, i) => all.push({ ...toChapter(id, m, c, i), mangaId: id }))
  }
  return all.sort((a, b) => Number(b.uploadDate) - Number(a.uploadDate)).slice(0, first)
}

export async function devGetPages(chapterId: number): Promise<string[]> {
  const kc = knownChapters[chapterId]
  if (!kc) throw new Error('Open the title again to load this chapter.')
  const [mangaId, key, url] = kc
  const m = mangaFor(mangaId)
  const chapter = chapterLists.get(mangaId)?.list.find((c) => c.key === key) ?? { key, url: url ?? undefined, locked: false }
  const { pages } = await MidokuSources.pages({ key: m.sourceKey, manga: bridgeManga(m) as DManga, chapter: bridgeChapter(chapter) as DChapter })
  return pages.flatMap((p) => {
    if (p.type === 'url') return [deviceImageUrl(m.sourceKey, p.url, p.context)!]
    if (p.type === 'image') return [`data:${p.mime};base64,${p.data}`]
    return []
  })
}

export const deviceAvailable = hasDeviceSources
