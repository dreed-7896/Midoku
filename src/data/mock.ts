// Dummy data until the app is wired to a Suwayomi server.
import type { CatalogItem, Chapter, CoverArt, Entry, LibraryTab, Source } from './types'

const art = (c1: string, c2: string, ink: string, motif: CoverArt['motif']): CoverArt => ({ c1, c2, ink, motif })

export const ART = {
  hollow: art('#1E2A44', '#E9B872', '#F4EBDD', 'sun'),
  hollowSide: art('#24304D', '#C9D6F2', '#F1F4FB', 'dot'),
  hollowColor: art('#3A2B18', '#E9B872', '#FBEFD9', 'ring'),
  salt: art('#4A1F2E', '#F27A6B', '#FBE3DC', 'moon'),
  tigers: art('#17423A', '#F2C14E', '#EAF4EE', 'dot'),
  bus: art('#2A2148', '#7FA7FF', '#E6E8FF', 'ring'),
  busExtra: art('#1B2350', '#A9C1FF', '#E8EDFF', 'sun'),
  orbit: art('#12343F', '#8FD3C7', '#E2F5F1', 'sun'),
  glass: art('#3A2340', '#E58FD0', '#F8E5F3', 'dot'),
  ember: art('#5A3415', '#FF9F5A', '#FFE9D6', 'moon'),
  tide: art('#183447', '#9CC8E8', '#E6F1FA', 'moon'),
  neon: art('#1D1A3A', '#B48CFF', '#ECE4FF', 'sun'),
  rust: art('#3D2A1E', '#D9733F', '#F5E2D3', 'ring'),
  ash: art('#2B2B2B', '#E25B45', '#F3E9E6', 'dot'),
  paper: art('#17423A', '#F2C14E', '#EAF4EE', 'moon'),
  less: art('#2A2148', '#7FA7FF', '#E6E8FF', 'ring'),
  anchor: art('#5A3415', '#FF9F5A', '#FFE9D6', 'sun'),
  thorn: art('#3A2340', '#E58FD0', '#F8E5F3', 'moon'),
  prince: art('#12343F', '#8FD3C7', '#E2F5F1', 'dot'),
  moth: art('#2E2A1A', '#E8D47A', '#F7F1D6', 'ring'),
  vapor: art('#3B1E3F', '#FF8AC2', '#FCE3F0', 'sun'),
  iron: art('#22282E', '#9FB3C8', '#E8EEF4', 'moon'),
  bloom: art('#163A2A', '#7FE0A8', '#E3F7EC', 'dot'),
  lotus: art('#40231C', '#F4A27A', '#FBE6DA', 'ring'),
  static: art('#1A2B3A', '#6FD0FF', '#E0F4FF', 'dot'),
}

export const SOURCES: Source[] = [
  { id: 'mangadex', name: 'MangaDex', letter: 'M', color: '#5A3415', glow: '#FF9F5A', lang: 'Multi', langs: ['EN', 'JA', 'ES', 'PT-BR', 'FR', 'ID'], version: '1.4.198', installed: true, pinned: true, update: true },
  { id: 'comick', name: 'Comick', letter: 'C', color: '#1F3A33', glow: '#3DD6A3', lang: 'Multi', langs: ['EN', 'ES', 'FR'], version: '1.4.71', installed: true, pinned: true, update: false },
  { id: 'asura', name: 'Asura', letter: 'A', color: '#3A2F22', glow: '#FFB547', lang: 'EN', langs: ['EN'], version: '1.4.52', installed: true, pinned: false, update: true, warn: 'cloudflare' },
  { id: 'bato', name: 'Bato.to', letter: 'B', color: '#2A2F45', glow: '#7FA7FF', lang: 'Multi', langs: ['EN', 'ES', 'IT'], version: '1.4.40', installed: true, pinned: false, update: false },
  { id: 'weebcentral', name: 'WeebCentral', letter: 'W', color: '#22303A', glow: '#6FD0FF', lang: 'EN', langs: ['EN'], version: '1.4.9', installed: true, pinned: false, update: false },
  { id: 'mangaplus', name: 'MangaPlus', letter: 'P', color: '#45252A', glow: '#F27A6B', lang: 'EN', langs: ['EN', 'ES'], version: '1.4.33', installed: true, pinned: false, update: false },
  { id: 'novelcrow', name: 'NovelCrow', letter: 'N', color: '#2E2A40', glow: '#B48CFF', lang: 'EN', langs: ['EN'], version: '1.4.3', installed: true, pinned: false, update: false, warn: 'error' },
  { id: 'webtoons', name: 'Webtoons', letter: 'T', color: '#1F3A2A', glow: '#7FE0A8', lang: 'Multi', langs: ['EN', 'ID', 'TH'], version: '1.4.61', installed: false, pinned: false, update: false },
  { id: 'mangafire', name: 'MangaFire', letter: 'F', color: '#4A1F1F', glow: '#FF6B5E', lang: 'Multi', langs: ['EN', 'JA'], version: '1.4.22', installed: false, pinned: false, update: false },
  { id: 'tapas', name: 'Tapas', letter: 'T', color: '#3A2A12', glow: '#FFB547', lang: 'EN', langs: ['EN'], version: '1.4.14', installed: false, pinned: false, update: false },
  { id: 'lectormanga', name: 'LectorManga', letter: 'L', color: '#1E2E44', glow: '#9CC8E8', lang: 'ES', langs: ['ES'], version: '1.4.11', installed: false, pinned: false, update: false },
  { id: 'rawkuma', name: 'Rawkuma', letter: 'R', color: '#33231E', glow: '#F4A27A', lang: 'JA', langs: ['JA'], version: '1.4.8', installed: false, pinned: false, update: false, nsfw: true },
  { id: 'mangaku', name: 'Mangaku', letter: 'K', color: '#1F2D1F', glow: '#7FE0A8', lang: 'ID', langs: ['ID'], version: '1.4.5', installed: false, pinned: false, update: false },
]

const TITLES = [
  'Ashes in Bloom', 'The Glass Throne', 'Salt Road', 'Lanterns', 'The Envoy', 'Crowfall', 'Low Tide',
  'Paper Oaths', 'A Quiet Coup', 'Ninefold', 'Embers', 'Winter Court', 'The Long Table', 'Small Mercies',
  'Signal Fire', 'Undertow', 'Glass Rain', 'The Regent', 'Old Debts', 'Homecoming',
]

const DAY = 86_400_000
const fmt = (daysAgo: number) =>
  daysAgo === 0 ? 'Today' : new Date(Date.now() - daysAgo * DAY).toLocaleDateString('en', { month: 'short', day: 'numeric' })

interface ChapterOpts {
  total: number
  read: number
  newCount?: number
  sourceId: string
  cadence?: number
  page?: number
  bookmarks?: number[]
  downloads?: number[]
}

function makeChapters(prefix: string, o: ChapterOpts): Chapter[] {
  const list: Chapter[] = []
  for (let n = 1; n <= o.total; n++) {
    const pages = 20 + ((n * 7) % 18)
    list.push({
      id: `${prefix}-${n}`,
      number: n,
      label: `Ch. ${n}`,
      title: TITLES[(n * 3) % TITLES.length],
      date: fmt((o.total - n) * (o.cadence ?? 7)),
      pages,
      page: n === o.read + 1 ? (o.page ?? 0) : 0,
      read: n <= o.read,
      bookmarked: o.bookmarks?.includes(n) ?? false,
      downloaded: o.downloads?.includes(n) ?? false,
      isNew: n > o.total - (o.newCount ?? 0),
      versions: 1,
      sourceId: o.sourceId,
      layout: n % 4,
    })
  }
  return list
}

/** Hollow Crown shows every collection feature: variants, an inserted chapter, a split chapter and removed chapters. */
function hollowChapters(): Chapter[] {
  const list = makeChapters('hc', {
    total: 113, read: 111, newCount: 1, sourceId: 'mangadex', page: 0,
    bookmarks: [12, 47, 88, 107, 109], downloads: [108, 109, 110, 111],
  })
  const ch112 = list.find((c) => c.number === 112)!
  ch112.versions = 2
  ch112.page = 18
  const ch110 = list.find((c) => c.number === 110)!
  const part1: Chapter = { ...ch110, id: 'hc-110-1', label: 'Ch. 110 · Pt 1', part: 'Pages 1–24', read: true, page: 0, pages: 24, layout: 0 }
  const part2: Chapter = { ...ch110, id: 'hc-110-2', label: 'Ch. 110 · Pt 2', part: 'Pages 25–48', read: true, number: 110.2, pages: 24, layout: 3 }
  const interlude: Chapter = {
    id: 'hc-111-5', number: 111.5, label: 'Ch. 111.5', title: 'Interlude', date: fmt(10), pages: 14, page: 0,
    read: true, bookmarked: false, downloaded: true, isNew: false, versions: 1, sourceId: 'comick', insertedFrom: 'Comick', layout: 2,
  }
  const out = list.filter((c) => c.number !== 110)
  out.push(part1, part2, interlude)
  for (const n of [3, 4, 5]) {
    const c = out.find((x) => x.number === n)
    if (c) c.removed = true
  }
  // Part 1 sorts just below part 2.
  part1.number = 110.1
  return out
}

export const ENTRIES: Entry[] = [
  {
    id: 'hollow-crown', title: 'Hollow Crown', author: 'Saeki Ren', art: ART.hollow, publishing: 'Ongoing', status: 'reading',
    tabs: ['action', 'favourites'], tags: ['Fantasy', 'Political', 'Drama', 'Royalty', 'Slow burn'],
    description: 'An exiled heir returns to a capital built on glass and debt, carrying a crown that remembers every ruler who wore it. Court intrigue, quiet magic, and a slow-burning rivalry with the regent who replaced her. The longer she wears it, the less certain she is whose memories are her own.',
    sources: [
      { sourceId: 'mangadex', chapters: 113, following: true, main: true },
      { sourceId: 'asura', chapters: 108, following: true },
      { sourceId: 'comick', chapters: 98, following: false },
    ],
    chapters: hollowChapters(), inLibrary: true, lastReadAgo: 2, updatedAgo: 3, addedOrder: 1,
  },
  {
    id: 'hollow-side', title: 'Hollow Crown: Side Tales', author: 'Saeki Ren', art: ART.hollowSide, publishing: 'Ongoing', status: 'reading',
    tabs: ['action'], tags: ['Fantasy', 'Anthology'], parentId: 'hollow-crown',
    description: 'Short stories from the margins of the glass capital.',
    sources: [{ sourceId: 'mangadex', chapters: 12, following: true, main: true }],
    chapters: makeChapters('hcs', { total: 12, read: 9, sourceId: 'mangadex', newCount: 1 }), inLibrary: true, lastReadAgo: 50, updatedAgo: 30, addedOrder: 2,
  },
  {
    id: 'hollow-color', title: 'Hollow Crown (Color)', author: 'Saeki Ren', art: ART.hollowColor, publishing: 'Ongoing', status: 'planned',
    tabs: ['action'], tags: ['Fantasy', 'Full color', 'Webtoon'], parentId: 'hollow-crown',
    description: 'The official full-colour vertical edition.',
    sources: [{ sourceId: 'comick', chapters: 40, following: true, main: true }],
    chapters: makeChapters('hcc', { total: 40, read: 31, sourceId: 'comick' }), inLibrary: true, lastReadAgo: 300, updatedAgo: 90, addedOrder: 3,
  },
  {
    id: 'salt-static', title: 'Salt & Static', author: 'Ona Vale', art: ART.salt, publishing: 'Ongoing', status: 'reading',
    tabs: ['action'], tags: ['Sci-fi', 'Mystery', 'Webtoon'],
    description: 'A radio operator on a salt flat starts receiving broadcasts from a town that drowned forty years ago.',
    sources: [{ sourceId: 'mangadex', chapters: 50, following: true, main: true }, { sourceId: 'bato', chapters: 49, following: false }],
    chapters: makeChapters('ss', { total: 50, read: 47, newCount: 3, sourceId: 'mangadex', page: 6, downloads: [48, 49, 50] }), inLibrary: true, lastReadAgo: 20, updatedAgo: 2, addedOrder: 4,
  },
  {
    id: 'paper-tigers', title: 'Paper Tigers', author: 'Kaito Mura', art: ART.tigers, publishing: 'Ongoing', status: 'reading',
    tabs: ['action', 'favourites'], tags: ['Martial arts', 'Comedy'],
    description: 'Two rival origami clubs settle their differences the only reasonable way: tournament combat.',
    sources: [{ sourceId: 'comick', chapters: 201, following: true, main: true }],
    chapters: makeChapters('pt', { total: 201, read: 200, newCount: 1, sourceId: 'comick', cadence: 3 }), inLibrary: true, lastReadAgo: 26, updatedAgo: 5, addedOrder: 5,
  },
  {
    id: 'night-bus', title: 'Night Bus 9', author: 'Lune Park', art: ART.bus, publishing: 'Ongoing', status: 'reading',
    tabs: ['action'], tags: ['Supernatural', 'Horror', 'Webtoon'],
    description: 'The last bus of the night only stops for passengers who are not quite alive.',
    sources: [{ sourceId: 'asura', chapters: 13, following: true, main: true }],
    chapters: makeChapters('nb', { total: 13, read: 11, newCount: 2, sourceId: 'asura', page: 12 }), inLibrary: true, lastReadAgo: 40, updatedAgo: 9, addedOrder: 6,
  },
  {
    id: 'night-bus-extra', title: 'Night Bus 9: Transfers', author: 'Lune Park', art: ART.busExtra, publishing: 'Completed', status: 'completed',
    tabs: ['action'], tags: ['Supernatural'], parentId: 'night-bus',
    description: 'Bonus stories.',
    sources: [{ sourceId: 'asura', chapters: 6, following: false, main: true }],
    chapters: makeChapters('nbx', { total: 6, read: 6, sourceId: 'asura' }), inLibrary: true, lastReadAgo: 400, updatedAgo: 900, addedOrder: 7,
  },
  {
    id: 'glasswing', title: 'Glasswing', author: 'Mire Asano', art: ART.glass, publishing: 'Ongoing', status: 'reading',
    tabs: ['action', 'romance'], tags: ['Fantasy', 'Romance'],
    description: 'A glassblower apprentices herself to a dragon who collects broken things.',
    sources: [{ sourceId: 'mangadex', chapters: 88, following: true, main: true }],
    chapters: makeChapters('gw', { total: 88, read: 81, newCount: 1, sourceId: 'mangadex' }), inLibrary: true, lastReadAgo: 72, updatedAgo: 11, addedOrder: 8,
  },
  {
    id: 'ember-shrine', title: 'Ember Shrine', author: 'Toma Iori', art: ART.ember, publishing: 'Ongoing', status: 'onHold',
    tabs: ['action'], tags: ['Supernatural', 'Action'],
    description: 'A shrine keeper who can only fight while it is raining.',
    sources: [{ sourceId: 'bato', chapters: 64, following: true, main: true }],
    chapters: makeChapters('es', { total: 64, read: 60, newCount: 4, sourceId: 'bato' }), inLibrary: true, lastReadAgo: 160, updatedAgo: 14, addedOrder: 9,
  },
  {
    id: 'low-orbit', title: 'Low Orbit Lullaby', author: 'Pell Nakamura', art: ART.orbit, publishing: 'Ongoing', status: 'planned',
    tabs: ['slice'], tags: ['Sci-fi', 'Slice of life'],
    description: 'A night-shift crew on a space station keeps a garden alive.',
    sources: [{ sourceId: 'mangadex', chapters: 40, following: true, main: true }],
    chapters: makeChapters('lo', { total: 40, read: 7, sourceId: 'mangadex' }), inLibrary: true, lastReadAgo: 120, updatedAgo: 200, addedOrder: 10,
  },
  {
    id: 'quiet-tide', title: 'Quiet Tide', author: 'Nao Ferris', art: ART.tide, publishing: 'Ongoing', status: 'reading',
    tabs: ['slice'], tags: ['Slice of life', 'Seaside'],
    description: 'A ferry, a lighthouse, and a town that only exists at low tide.',
    sources: [{ sourceId: 'comick', chapters: 30, following: true, main: true }],
    chapters: makeChapters('qt', { total: 30, read: 29, newCount: 1, sourceId: 'comick' }), inLibrary: true, lastReadAgo: 30, updatedAgo: 20, addedOrder: 11,
  },
  {
    id: 'neon-monastery', title: 'Neon Monastery', author: 'Ivo Sato', art: ART.neon, publishing: 'Ongoing', status: 'planned',
    tabs: ['slice'], tags: ['Cyberpunk', 'Webtoon'],
    description: 'Monks maintain the last analog servers in a city that has forgotten them.',
    sources: [{ sourceId: 'webtoons', chapters: 22, following: true, main: true }],
    chapters: makeChapters('nm', { total: 22, read: 0, sourceId: 'mangadex' }), inLibrary: true, updatedAgo: 48, addedOrder: 12,
  },
  {
    id: 'rust-belt', title: 'Rust Belt Saints', author: 'Dee Okafor', art: ART.rust, publishing: 'Completed', status: 'completed',
    tabs: ['slice'], tags: ['Drama'],
    description: 'Three friends restore a dead factory town one storefront at a time.',
    sources: [{ sourceId: 'mangaplus', chapters: 60, following: false, main: true }],
    chapters: makeChapters('rb', { total: 60, read: 60, sourceId: 'mangaplus' }), inLibrary: true, lastReadAgo: 800, updatedAgo: 2000, addedOrder: 13,
  },
  {
    id: 'crown-ash', title: 'Crown of Ash', author: 'Hal Brenner', art: ART.ash, publishing: 'Hiatus', status: 'dropped',
    tabs: ['romance'], tags: ['Fantasy', 'Romance'],
    description: 'A political marriage between two people who have each been ordered to kill the other.',
    sources: [{ sourceId: 'mangadex', chapters: 34, following: false, main: true }],
    chapters: makeChapters('ca', { total: 34, read: 12, sourceId: 'mangadex' }), inLibrary: true, lastReadAgo: 1200, updatedAgo: 3000, addedOrder: 14,
  },
  {
    id: 'vapor-hearts', title: 'Vapor Hearts', author: 'Rio Tan', art: ART.vapor, publishing: 'Ongoing', status: 'reading',
    tabs: ['romance', 'favourites'], tags: ['Romance', 'Webtoon'],
    description: 'Two rival bakers share a single industrial oven.',
    sources: [{ sourceId: 'webtoons', chapters: 70, following: true, main: true }],
    chapters: makeChapters('vh', { total: 70, read: 70, sourceId: 'mangadex' }), inLibrary: true, lastReadAgo: 90, updatedAgo: 100, addedOrder: 15,
  },
  {
    id: 'iron-moth', title: 'Iron Moth', author: 'Sena Holt', art: ART.moth, publishing: 'Ongoing', status: 'planned',
    tabs: [], tags: ['Mecha'],
    description: 'A pilot whose mech only works at night.',
    sources: [{ sourceId: 'bato', chapters: 18, following: true, main: true }],
    chapters: makeChapters('im', { total: 18, read: 0, sourceId: 'bato' }), inLibrary: true, updatedAgo: 400, addedOrder: 16,
  },
]

export const LIBRARY_TABS: LibraryTab[] = [
  { id: 'reading', kind: 'reading', name: 'Reading' },
  { id: 'all', kind: 'all', name: 'All' },
  { id: 'favourites', kind: 'tab', name: 'Favourites' },
  { id: 'action', kind: 'tab', name: 'Action' },
  { id: 'slice', kind: 'tab', name: 'Slice of life' },
  { id: 'romance', kind: 'tab', name: 'Romance' },
  { id: 'webtoons', kind: 'smart', name: 'Webtoons', filters: { statuses: [], newOnly: false, progress: 'any', tag: 'Webtoon' } },
]

// One very long chapter to exercise the reader with hundreds of pages.
const longChapter = ENTRIES.find((e) => e.id === 'paper-tigers')?.chapters.at(-1)
if (longChapter) longChapter.pages = 420

const item = (id: string, title: string, a: CoverArt, publishing = 'Ongoing', entryId?: string): CatalogItem => ({ id, title, art: a, publishing, entryId })

const COMMON = [
  item('c-hc', 'Hollow Crown', ART.hollow, 'Ongoing', 'hollow-crown'),
  item('c-gw', 'Glasswing', ART.glass, 'Ongoing', 'glasswing'),
  item('c-ss', 'Salt & Static', ART.salt, 'Ongoing', 'salt-static'),
  item('c-rb', 'Rust Belt Saints', ART.rust, 'Completed', 'rust-belt'),
  item('c-qt', 'Quiet Tide', ART.tide, 'Ongoing', 'quiet-tide'),
  item('c-nm', 'Neon Monastery', ART.neon, 'Ongoing', 'neon-monastery'),
  item('c-ca', 'Crown of Ash', ART.ash, 'Hiatus', 'crown-ash'),
  item('c-pt', 'Paper Tigers', ART.tigers, 'Ongoing', 'paper-tigers'),
  item('c-lo', 'Low Orbit Lullaby', ART.orbit, 'Ongoing', 'low-orbit'),
  item('c-pc', 'The Paper Crown', ART.paper),
  item('c-cl', 'Crownless', ART.less, 'Completed'),
  item('c-anc', 'Crown & Anchor', ART.anchor),
  item('c-th', 'Thorn Crown Saga', ART.thorn),
  item('c-pz', 'Crown Prince Zero', ART.prince),
  item('c-ib', 'Iron Bloom', ART.bloom),
  item('c-lt', 'Lotus Engine', ART.lotus, 'Completed'),
  item('c-st', 'Static Saints', ART.static),
  item('c-vh', 'Vapor Hearts', ART.vapor, 'Ongoing', 'vapor-hearts'),
  item('c-im', 'Iron Moth', ART.moth, 'Ongoing', 'iron-moth'),
  item('c-ir', 'Iron Requiem', ART.iron, 'Completed'),
]

/** Each source returns a rotated slice of the shared catalogue so results differ between sources. */
export function catalogFor(sourceId: string): CatalogItem[] {
  const seed = [...sourceId].reduce((n, ch) => n + ch.charCodeAt(0), 0)
  const offset = seed % COMMON.length
  const rotated = [...COMMON.slice(offset), ...COMMON.slice(0, offset)]
  return rotated.slice(0, 15 + (seed % 5)).map((c) => ({ ...c, id: `${sourceId}-${c.id}` }))
}

export const RECENT_SEARCHES = ['crown', 'glass', 'night bus', 'tide']

