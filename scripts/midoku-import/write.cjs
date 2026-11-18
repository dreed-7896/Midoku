// Stage 2: write the plan (with the server ids and chapters from server.json) into Midoku Web's database.
// node write.cjs --dry   prints what would be written.
const { createClient } = require('/home/user/Midoku-web/node_modules/@supabase/supabase-js')
const cfg = require('/home/user/Midoku-web/scripts/test-server.json')
const plan = require('./plan.json')
const srv = require('./server.json')
const DRY = process.argv.includes('--dry')
const db = createClient('https://ujrklbjeqbvzqdcrcthw.supabase.co', 'sb_publishable_6Y9ApBecGpjltrzKl1XOlQ_6o1YneEN', { auth: { persistSession: false } })
const uuid = () => crypto.randomUUID()
const ok = (r, what) => { if (r.error) throw new Error(`${what}: ${r.error.message}`); return r.data }
const iso = (s) => (s ? new Date(s * 1000).toISOString() : null)
const PUB = (st) => (st === 'COMPLETED' || st === 'PUBLISHING_FINISHED' ? 'Completed' : st === 'ON_HIATUS' ? 'Hiatus' : 'Ongoing')
const norm = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()

/** The server chapter for a backup chapter of a listing: same number, else same name, else the only chapter. */
function matchChapter(lid, v, used) {
  const list = srv.chapters[lid]
  if (!list?.length) return undefined
  const free = (c) => !used.has(c.url)
  let cands = v.number != null ? list.filter((c) => Math.abs(c.chapterNumber - v.number) < 1e-6) : []
  if (cands.length > 1) cands = cands.filter((c) => norm(c.name) === norm(v.title)).concat(cands)
  let hit = cands.find(free) ?? cands[0]
  if (!hit && v.title) hit = list.find((c) => norm(c.name) === norm(v.title))
  if (!hit && list.length === 1) hit = list[0]
  return hit
}

;(async () => {
  ok(await db.auth.signInWithPassword({ email: 'owner@midoku.invalid', password: cfg.appPassword }), 'sign in')
  const stats = { entries: 0, reused: 0, sources: 0, states: 0, read: 0, splits: 0, unmatched: 0, noServer: 0, positioned: 0 }
  const unmatched = []

  // Tabs: reuse by name, create the missing ones after the existing ones.
  const tabs = ok(await db.from('tabs').select('id, name, kind, position'), 'tabs')
  const tabId = new Map(tabs.filter((t) => t.kind === 'tab').map((t) => [t.name.toLowerCase(), t.id]))
  let tabPos = Math.max(0, ...tabs.map((t) => t.position ?? 0))
  const newTabs = []
  for (const name of plan.categories) if (!tabId.has(name.toLowerCase())) { const id = uuid(); tabId.set(name.toLowerCase(), id); newTabs.push({ id, kind: 'tab', name, position: ++tabPos }) }

  // Titles already in the database (by their main source) are updated instead of added again.
  const existing = ok(await db.from('entry_sources').select('entry_id, source_id, manga_url').eq('is_main', true), 'existing sources')
  const byMain = new Map(existing.map((s) => [`${s.source_id}|${s.manga_url}`, s.entry_id]))

  const dbId = new Map() // backup entry id -> db entry id
  const entryRows = [], sourceRows = [], tabRows = [], stateRows = [], splitRows = [], importRows = []
  for (const e of plan.entries) {
    const srcs = e.sources.filter((s) => srv.mangas[s.listing])
    stats.noServer += e.sources.length - srcs.length
    const main = srcs.find((s) => s.main) ?? srcs[0]
    const mainM = main && srv.mangas[main.listing]
    const reuse = mainM && byMain.get(`${mainM.sourceId}|${mainM.url}`)
    const id = reuse ?? uuid()
    if (reuse) stats.reused++
    dbId.set(e.id, id)
    const d = mainM?.details ?? {}
    const listingTitle = main ? plan.listings[main.listing].title : ''
    const custom = {}
    if (e.title) custom.title = e.title
    if (e.author) custom.author = e.author
    if (e.description) custom.description = e.description
    if (e.cover) custom.cover = e.cover
    if (e.thumbs) custom.thumbs = true
    if (!srcs.length && !custom.title) custom.title = 'Series'
    entryRows.push({
      id, title: d.title || listingTitle || custom.title || '', author: d.author || d.artist || '', description: d.description || '',
      cover_path: d.thumbnailUrl ?? null, tags: d.genre ?? [], publishing: PUB(d.status), parent_id: null, in_library: true,
      added_at: iso(e.createdAt) ?? new Date().toISOString(), last_read_at: iso(e.lastReadAt), custom, position: 0, renumber: false,
    })
    for (const s of srcs) {
      const m = srv.mangas[s.listing]
      sourceRows.push({ entry_id: id, source_id: m.sourceId, manga_url: m.url, server_manga_id: m.id, source_name: plan.listings[s.listing].sourceName, following: s.following, is_main: s === main, segment: s.segment })
    }
    for (const t of e.tabs) tabRows.push({ entry_id: id, tab_id: tabId.get(t.toLowerCase()) })

    // Chapters: match each slot's chapters to the server's; titles whose chapters the server couldn't fetch keep
    // their state by chapter number (chapter_imports) until the app loads them.
    const used = new Set()
    const segOf = new Map(e.sources.map((s) => [s.listing, s.segment]))
    const backupCount = new Map()
    for (const vs of e.slots) for (const v of vs) backupCount.set(v.listing, (backupCount.get(v.listing) ?? 0) + 1)
    const slots = e.slots.map((vs) => vs.map((v) => {
      if (!srv.mangas[v.listing]) return null
      if (!srv.chapters[v.listing]) return { v, pending: true, num: v.number ?? 0 }
      const ch = matchChapter(v.listing, v, used)
      if (!ch) { stats.unmatched++; unmatched.push(`${listingTitle.slice(0, 30)} · ${v.name ?? v.title ?? v.number}`); return null }
      used.add(ch.url)
      return { v, ch, num: ch.chapterNumber }
    }).filter(Boolean))
    const key = (x) => [segOf.get(x.v.listing) ?? 0, x.num]
    const firsts = slots.filter((s) => s.length).map((s) => key(s[0]))
    const inOrder = firsts.every((k, i) => i === 0 || k[0] > firsts[i - 1][0] || (k[0] === firsts[i - 1][0] && k[1] >= firsts[i - 1][1]))
    const states = new Map(), parts = new Map()
    slots.forEach((vs, si) => {
      for (const x of vs) {
        const { v } = x
        const m = srv.mangas[v.listing]
        const k = x.pending ? `pending|${v.listing}|${v.chapterExt}` : `${m.sourceId}|${x.ch.url}`
        const row = states.get(k) ?? (x.pending
          ? { pending: true, entry_id: id, source_id: m.sourceId, manga_url: m.url, number: v.number, title: v.title, read: false, page: 0, removed: false, preferred: false, position: null, name: null, thumb: null, only_chapter: backupCount.get(v.listing) === 1 }
          : { entry_id: id, source_id: m.sourceId, chapter_url: x.ch.url, chapter_number: x.ch.chapterNumber, page: 0, read: false, bookmarked: false, removed: false, preferred: false, position: null, name: null, thumb: null })
        if (v.pages) {
          const p = parts.get(k) ?? { ranges: v.pages.ranges, excluded: v.pages.excluded, read: [], total: v.pages.ranges.length }
          if (v.read) p.read.push(v.pages.part)
          parts.set(k, p)
          if (v.read) row.page = Math.max(row.page, v.pages.ranges[v.pages.part]?.end ?? 0)
          if (v.name && v.pages.part === 0) row.name = v.name
        } else {
          row.read = row.read || v.read
          if (v.name) row.name = v.name
        }
        if (v.removed) row.removed = true
        if (v.preferred) row.preferred = true
        if (v.thumb) row.thumb = v.thumb
        if (!inOrder || e.manualOrder) { if (row.position == null) row.position = si + 1 }
        else if (v.editNumber != null && !isNaN(Number(v.editNumber)) && row.position == null) row.position = Number(v.editNumber)
        states.set(k, row)
      }
    })
    for (const [k, p] of parts) {
      const row = states.get(k)
      if (p.read.length >= p.total) row.read = true
      const breaks = p.ranges.slice(1).map((r) => r.start)
      const excluded = p.excluded.flatMap((r) => Array.from({ length: r.end - r.start + 1 }, (_, i) => r.start + i))
      if (!breaks.length && !excluded.length) continue
      if (row.pending) { row.breaks = breaks; row.excluded = excluded }
      else splitRows.push({ entry_id: id, source_id: row.source_id, chapter_url: row.chapter_url, breaks, excluded })
    }
    for (const row of states.values()) {
      if (row.position != null) stats.positioned++
      if (row.read) stats.read++
      const keep = row.read || row.page || row.removed || row.preferred || row.position != null || row.name || row.thumb || row.breaks
      if (!keep) continue
      if (row.pending) { const { pending, ...r } = row; importRows.push(r) } else stateRows.push(row)
    }
    stats.entries++
  }

  // Nesting: children point at their parent and keep the parent's order (contentOrder), else when they were added.
  const kids = new Map()
  for (const e of plan.entries) if (e.parent && dbId.has(e.parent)) kids.set(e.parent, [...(kids.get(e.parent) ?? []), e])
  for (const [pid, list] of kids) {
    const parent = plan.entries.find((x) => x.id === pid)
    const ordered = parent.contentOrder.map((o) => o.entry?._0 ?? o.title?._0).filter(Boolean)
    list.sort((a, b) => ((ordered.indexOf(a.id) + 1 || 1e9) - (ordered.indexOf(b.id) + 1 || 1e9)) || (a.createdAt - b.createdAt))
    list.forEach((k, i) => { const row = entryRows.find((r) => r.id === dbId.get(k.id)); row.parent_id = dbId.get(pid); row.position = i })
  }
  stats.sources = sourceRows.length; stats.states = stateRows.length; stats.splits = splitRows.length; stats.imports = importRows.length

  console.log(JSON.stringify(stats), 'new tabs', newTabs.map((t) => t.name))
  console.log('unmatched chapters (first 15):', unmatched.slice(0, 15))
  if (DRY) return

  const chunk = async (table, rows, onConflict) => {
    for (let i = 0; i < rows.length; i += 200) ok(await db.from(table).upsert(rows.slice(i, i + 200), onConflict ? { onConflict } : undefined), table)
  }
  if (newTabs.length) ok(await db.from('tabs').insert(newTabs), 'new tabs')
  // Parents first (rows without parent), then the rest, so parent ids exist.
  await chunk('entries', entryRows.map((r) => ({ ...r, parent_id: null })))
  await chunk('entries', entryRows.filter((r) => r.parent_id).map((r) => ({ ...r })))
  await chunk('entry_sources', sourceRows, 'entry_id,source_id,manga_url')
  await chunk('entry_tabs', [...new Map(tabRows.map((r) => [`${r.entry_id}|${r.tab_id}`, r])).values()], 'entry_id,tab_id')
  await chunk('chapter_states', stateRows.map((r) => ({ ...r, updated_at: new Date().toISOString() })), 'entry_id,source_id,chapter_url')
  await chunk('chapter_splits', splitRows, 'entry_id,source_id,chapter_url')
  // Imports are replaced per title, so running this again doesn't double them.
  for (const eid of new Set(importRows.map((r) => r.entry_id))) ok(await db.from('chapter_imports').delete().eq('entry_id', eid), 'old imports')
  for (let i = 0; i < importRows.length; i += 200) ok(await db.from('chapter_imports').insert(importRows.slice(i, i + 200)), 'imports')
  console.log('written')
})().catch((e) => { console.error('FAILED', e.message); process.exit(1) })
