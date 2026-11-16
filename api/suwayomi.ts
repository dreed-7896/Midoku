// Forwards /api/* to the Suwayomi server set in SUWAYOMI_URL (GraphQL + images).
export const config = { runtime: 'edge' }

export default async function handler(req: Request): Promise<Response> {
  const base = process.env.SUWAYOMI_URL
  if (!base) return new Response('SUWAYOMI_URL is not set', { status: 500 })

  const url = new URL(req.url)
  const path = url.searchParams.get('path') ?? ''
  url.searchParams.delete('path')
  const target = `${base.replace(/\/$/, '')}/api/${path}${url.search}`

  const headers = new Headers()
  for (const h of ['content-type', 'accept', 'authorization']) {
    const v = req.headers.get(h)
    if (v) headers.set(h, v)
  }

  const upstream = await fetch(target, {
    method: req.method,
    headers,
    body: req.method === 'GET' || req.method === 'HEAD' ? undefined : await req.arrayBuffer(),
    redirect: 'follow',
  })

  const out = new Headers()
  for (const h of ['content-type', 'cache-control', 'content-length', 'etag', 'last-modified']) {
    const v = upstream.headers.get(h)
    if (v) out.set(h, v)
  }
  return new Response(upstream.body, { status: upstream.status, headers: out })
}
