/**
 * Reading history for sample mode (no server), kept on the device. With a server the history is the
 * `read_at` of each chapter's state in the database (see loadHistory in db.ts).
 */
export interface LocalHistoryItem { entryId: string; chapterId: string; label: string; page: number; read: boolean; at: number }

const KEY = 'midoku.history'
const MAX = 400

export function readLocalHistory(): LocalHistoryItem[] {
  try { return JSON.parse(localStorage.getItem(KEY) ?? '[]') } catch { return [] }
}
function write(list: LocalHistoryItem[]) {
  try { localStorage.setItem(KEY, JSON.stringify(list.slice(0, MAX))) } catch { /* history is a convenience */ }
}
export function recordLocalHistory(item: LocalHistoryItem) {
  write([item, ...readLocalHistory().filter((x) => !(x.entryId === item.entryId && x.chapterId === item.chapterId))])
}
export function clearLocalHistory(entryId?: string) {
  write(entryId ? readLocalHistory().filter((x) => x.entryId !== entryId) : [])
}
