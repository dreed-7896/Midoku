import { Capacitor, registerPlugin } from '@capacitor/core'

/**
 * On-device Aidoku extensions, available when the app runs in the iOS shell (`plugins/midoku-sources`).
 * Models are AidokuRunner's own JSON: hand a manga or chapter you got from here straight back.
 */

export type DFilterValue = Record<string, unknown>

export interface DSource {
  key: string
  name: string
  version: number
  languages: string[]
  urls: string[]
  contentRating: number
  onlySearch: boolean
  providesListings: boolean
  providesHome: boolean
  icon?: string
  listings: { id: string; name: string; kind?: number }[]
  filters: Record<string, unknown>[]
}

export interface DChapter {
  key: string
  title?: string
  chapterNumber?: number
  volumeNumber?: number
  dateUploaded?: number
  scanlators?: string[]
  url?: string
  language?: string
  thumbnail?: string
  locked: boolean
}

export interface DManga {
  sourceKey: string
  key: string
  title: string
  cover?: string
  artists?: string[]
  authors?: string[]
  description?: string
  url?: string
  tags?: string[]
  status: number
  contentRating: number
  viewer: number
  updateStrategy: number
  nextUpdateTime?: number
  chapters?: DChapter[]
}

export interface DPageResult { entries: DManga[]; hasNextPage: boolean }

export type DPage =
  | { type: 'url'; url: string; context?: Record<string, string> }
  | { type: 'text'; text: string }
  | { type: 'image'; data: string; mime: string }
  | { type: 'unsupported' }

interface Plugin {
  fetchText(o: { url: string }): Promise<{ status: number; text: string }>
  installed(): Promise<{ sources: DSource[] }>
  install(o: { url: string }): Promise<DSource>
  uninstall(o: { key: string }): Promise<void>
  search(o: { key: string; query?: string; page: number; filters?: DFilterValue[] }): Promise<DPageResult>
  listing(o: { key: string; id: string; page: number }): Promise<DPageResult>
  manga(o: { key: string; manga: DManga; details?: boolean; chapters?: boolean }): Promise<DManga>
  pages(o: { key: string; manga: DManga; chapter: DChapter }): Promise<{ pages: DPage[] }>
  image(o: { key: string; url: string; context?: Record<string, string>; cover?: boolean }): Promise<{ data: string; mime: string; status?: number }>
  settings(o: { key: string }): Promise<{ settings: Record<string, unknown>[]; values: Record<string, unknown> }>
  setSetting(o: { key: string; name: string; value: unknown }): Promise<void>
}

export const MidokuSources = registerPlugin<Plugin>('MidokuSources')

/** True inside the iOS shell, where on-device extensions can run. */
export const hasDeviceSources = () => Capacitor.isNativePlatform() && Capacitor.isPluginAvailable('MidokuSources')

export async function deviceImage(key: string, url: string, context?: Record<string, string>, cover = false): Promise<Blob> {
  const { data, mime } = await MidokuSources.image({ key, url, context, cover })
  const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0))
  return new Blob([bytes], { type: mime })
}
