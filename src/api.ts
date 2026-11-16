export async function gql<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
  const res = await fetch('/api/graphql', {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ query, variables }),
  })
  if (!res.ok) throw new Error(`Server returned ${res.status}`)
  const json = await res.json()
  if (json.errors?.length) throw new Error(json.errors[0].message)
  return json.data as T
}

/** Suwayomi returns server-relative image paths; keep them relative so they go through /api. */
export const img = (u?: string | null) => (u ? u.replace(/^https?:\/\/[^/]+(?=\/api\/)/, '') : '')

export interface Source {
  id: string
  displayName: string
  lang: string
  supportsLatest: boolean
  iconUrl: string
}

export interface Extension {
  pkgName: string
  name: string
  lang: string
  iconUrl: string
  versionName: string
  isInstalled: boolean
  hasUpdate: boolean
  isNsfw: boolean
  source?: { nodes: Source[] }
}

export interface Manga {
  id: number
  title: string
  thumbnailUrl: string | null
  inLibrary: boolean
}

const EXT_FIELDS = 'pkgName name lang iconUrl versionName isInstalled hasUpdate isNsfw'
const SOURCE_FIELDS = 'id displayName lang supportsLatest iconUrl'

export const listExtensions = () =>
  gql<{ extensions: { nodes: Extension[] } }>(`{ extensions { nodes { ${EXT_FIELDS} } } }`).then((d) =>
    d.extensions.nodes,
  )

export const refreshExtensions = () =>
  gql<{ fetchExtensions: { extensions: Extension[] } }>(
    `mutation { fetchExtensions(input: {}) { extensions { ${EXT_FIELDS} } } }`,
  ).then((d) => d.fetchExtensions.extensions)

export const setInstalled = (pkgName: string, install: boolean) =>
  gql(
    `mutation($id: String!) { updateExtension(input: { id: $id, patch: { ${install ? 'install' : 'uninstall'}: true } }) { extension { pkgName isInstalled } } }`,
    { id: pkgName },
  )

export const getExtension = (pkgName: string) =>
  gql<{ extensions: { nodes: Extension[] } }>(
    `query($pkg: String!) { extensions(condition: { pkgName: $pkg }) { nodes { ${EXT_FIELDS} source { nodes { ${SOURCE_FIELDS} } } } } }`,
    { pkg: pkgName },
  ).then((d) => d.extensions.nodes[0])

export type BrowseType = 'POPULAR' | 'LATEST' | 'SEARCH'

export const browseSource = (source: string, type: BrowseType, page: number, query?: string) =>
  gql<{ fetchSourceManga: { hasNextPage: boolean; mangas: Manga[] } }>(
    `mutation($source: LongString!, $type: FetchSourceMangaType!, $page: Int!, $query: String) {
      fetchSourceManga(input: { source: $source, type: $type, page: $page, query: $query }) {
        hasNextPage mangas { id title thumbnailUrl inLibrary }
      }
    }`,
    { source, type, page, query },
  ).then((d) => d.fetchSourceManga)
