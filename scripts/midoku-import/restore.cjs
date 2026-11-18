const fs = require('fs')
const c = require('/home/user/Midoku-web/scripts/test-server.json')
const base = c.url.replace(/\/$/, ''), auth = 'Basic ' + Buffer.from(c.user + ':' + c.pass).toString('base64')
const q = (query, variables) => fetch(base + '/api/graphql', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: auth }, body: JSON.stringify({ query, variables }) }).then((r) => r.json())
;(async () => {
  const fd = new FormData()
  fd.append('operations', JSON.stringify({ query: 'mutation($b: Upload!){ restoreBackup(input:{backup:$b}){ id status { state mangaProgress totalManga } } }', variables: { b: null } }))
  fd.append('map', JSON.stringify({ 0: ['variables.b'] }))
  fd.append('0', new Blob([fs.readFileSync(process.argv[2])]), 'import.tachibk')
  const r = await fetch(base + '/api/graphql', { method: 'POST', headers: { Authorization: auth }, body: fd }).then((x) => x.json())
  console.log(JSON.stringify(r).slice(0, 400))
  for (let i = 0; i < 120; i++) {
    await new Promise((r) => setTimeout(r, 2000))
    const s = await q('query($id: String!){ restoreStatus(id:$id){ state mangaProgress totalManga } }', { id: r.data.restoreBackup.id })
    const st = s.data?.restoreStatus
    process.stdout.write(`\r${st?.state} ${st?.mangaProgress}/${st?.totalManga}   `)
    if (!st || /SUCCESS|FAILURE/.test(st.state)) { console.log(); break }
  }
})()
