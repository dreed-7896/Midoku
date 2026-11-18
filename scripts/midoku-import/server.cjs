// Stage 1: put every listing of the plan on the Suwayomi server and fetch its details and chapters.
// Results are saved to server.json, so a rerun only does what's missing.
const fs = require('fs')
const { execFileSync } = require('child_process')
const c = require('/home/user/Midoku-web/scripts/test-server.json')
const base = c.url.replace(/\/$/, ''), auth = 'Basic ' + Buffer.from(c.user + ':' + c.pass).toString('base64')
const plan = require('./plan.json')
const OUT = './server.json'
const state = fs.existsSync(OUT) ? JSON.parse(fs.readFileSync(OUT)) : { urls: {}, mangas: {}, chapters: {}, failed: {} }
const save = () => fs.writeFileSync(OUT, JSON.stringify(state))
const q = async (query, variables, tries = 2) => {
  for (let i = 0; ; i++) {
    try {
      const r = await fetch(base + '/api/graphql', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: auth }, body: JSON.stringify({ query, variables }), signal: AbortSignal.timeout(90000) }).then((x) => x.json())
      if (r.errors && i < tries - 1) throw new Error(r.errors[0].message)
      return r
    } catch (e) {
      if (i >= tries - 1) return { errors: [{ message: e.message }] }
      await new Promise((r) => setTimeout(r, 2000 * (i + 1)))
    }
  }
}
const norm = (s) => (s || '').toLowerCase().replace(/\[[^\]]*\]|\([^)]*\)/g, '').replace(/[^a-z0-9]+/g, ' ').trim()

async function resolveSearch() {
  for (const l of Object.values(plan.listings).filter((x) => x.search && !state.urls[x.id])) {
    const r = await q('mutation($s: LongString!, $q: String){ fetchSourceManga(input:{source:$s,type:SEARCH,page:1,query:$q}){ mangas{ url title } } }',
      { s: l.sourceId, q: l.title.replace(/\[[^\]]*\]|\([^)]*\)/g, '').trim().slice(0, 80) })
    const ms = r.data?.fetchSourceManga?.mangas ?? []
    const hit = l.sourceKey === 'multi.hitomi' ? ms.find((m) => m.url.includes(`-${l.externalID}.html`) || m.url.includes(`/${l.externalID}.html`))
      : ms.find((m) => norm(m.title) === norm(l.title)) ?? ms.find((m) => m.url.includes(l.externalID.replace(/^\/|\/$/g, '').replace(/_/g, '-')))
    if (hit) state.urls[l.id] = hit.url
    else state.failed[l.id] = `not found by search: ${l.title}`
    console.log('search', l.sourceKey, l.title.slice(0, 40), '->', hit?.url ?? 'NOT FOUND')
  }
  save()
}

async function restore() {
  const list = Object.values(plan.listings).map((l) => ({ ...l, url: l.url ?? state.urls[l.id] })).filter((l) => l.url && !state.mangas[l.id])
  if (!list.length) return
  const spec = { mangas: list.map((l) => ({ source: l.sourceId, url: l.url, title: l.title, favorite: false })), sources: [...new Map(list.map((l) => [l.sourceId, { name: l.sourceName, id: l.sourceId }])).values()] }
  fs.writeFileSync('import.json', JSON.stringify(spec))
  execFileSync('python3', ['-I', 'tachibk.py', 'import.json', 'import.tachibk'], { stdio: 'inherit' })
  execFileSync('node', ['restore.cjs', 'import.tachibk'], { stdio: 'inherit', timeout: 600000 })
  // Find the server ids by source + address.
  for (const sid of [...new Set(list.map((l) => l.sourceId))]) {
    const urls = list.filter((l) => l.sourceId === sid).map((l) => l.url)
    const r = await q('query($s: LongString!, $u: [String!]){ mangas(filter:{sourceId:{equalTo:$s}, url:{in:$u}}){ nodes { id url } } }', { s: sid, u: urls })
    const byUrl = new Map((r.data?.mangas?.nodes ?? []).map((m) => [m.url, m.id]))
    for (const l of list.filter((x) => x.sourceId === sid)) {
      if (byUrl.has(l.url)) state.mangas[l.id] = { id: byUrl.get(l.url), url: l.url, sourceId: sid }
      else state.failed[l.id] = 'not created on the server'
    }
  }
  save()
}

async function fetchAll() {
  // One try per title; a source that fails twice in a row is skipped (its reading state is applied later by the app).
  const todo = Object.entries(state.mangas).filter(([lid]) => !state.chapters[lid] && !state.skipped?.[lid])
  state.skipped = state.skipped ?? {}
  const strikes = {}
  let done = 0
  const worker = async () => {
    for (let job = todo.shift(); job; job = todo.shift()) {
      const [lid, m] = job
      const key = plan.listings[lid].sourceKey
      if ((strikes[key] ?? 0) >= 2) { state.skipped[lid] = 'source not answering'; continue }
      const chs = await q('mutation($id: Int!){ fetchChapters(input:{mangaId:$id}){ chapters { id url name chapterNumber scanlator sourceOrder } } }', { id: m.id }, 1)
      if (chs.data?.fetchChapters) {
        strikes[key] = 0
        state.chapters[lid] = chs.data.fetchChapters.chapters; delete state.failed[lid]
        const det = await q('mutation($id: Int!){ fetchManga(input:{id:$id}){ manga { title author artist description genre status thumbnailUrl } } }', { id: m.id }, 1)
        if (det.data?.fetchManga) m.details = det.data.fetchManga.manga
      } else {
        strikes[key] = (strikes[key] ?? 0) + 1
        state.failed[lid] = `chapters: ${(chs.errors?.[0]?.message ?? 'no answer').split('\n')[0].slice(0, 120)}`
      }
      done++
      if (done % 5 === 0) { save(); console.log(`fetched ${done}`) }
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()])
  save()
}

;(async () => {
  await resolveSearch()
  await restore()
  await fetchAll()
  const n = Object.keys(plan.listings).length
  console.log('listings', n, 'on server', Object.keys(state.mangas).length, 'with chapters', Object.keys(state.chapters).length)
  const fails = Object.entries(state.failed)
  console.log('failed', fails.length)
  for (const [lid, why] of fails) console.log(' ', plan.listings[lid].sourceKey, plan.listings[lid].title.slice(0, 50), '|', why)
})()
