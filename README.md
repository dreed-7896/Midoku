# Midoku Web

Web client for Midoku, backed by [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server).

## Dev server (GitHub Codespaces)

1. On GitHub, switch to the `web` branch → **Code → Codespaces → Create codespace on web**.
2. Wait for setup. Suwayomi + FlareSolverr start automatically.
3. **Ports** tab → open **Suwayomi (4567)**. Keep the port Private (GitHub login required).

- GraphQL playground: `<forwarded-url>/api/graphql`
- Keiyoushi extension repo and FlareSolverr are preconfigured.
- Data persists until the codespace is deleted. Codespaces stop after 30 min idle; reopening restarts everything.

## Web app

Mobile-only PWA (React + Vite). Enter your Suwayomi server address in **Settings → Server**; until then it shows sample data (`src/data/mock.ts`). The app talks to the server directly from the browser, so the server needs an https address.

- `npm run dev` → open port 5173 (in the codespace, from the Ports tab).
- `npm run build` renders the PWA icons from `public/icon.svg`, type-checks and builds to `dist/`.
- Screens: Home feed, Library (tabs, filters, groups, collections), Entry details, Search, Sources, Source browse, Reader (webtoon by default, paged optional), Settings.
- Navigation is a native-style screen stack: pushes slide in from the right over the darkened previous screen; back reverses it. In the installed app, swiping from the left edge drags the screen away and reveals the real previous one.
- Library: tabs you can swipe between (Reading, All, your own tabs, saved filters).
- Offline: download chapters from a title (or select chapters → Save); the library and titles opened in the last 3 days stay available offline, and changes made offline sync when back online. Settings → Storage shows what is kept.
- Chapters: long-press a chapter to pick which version (source) to read, split a long chapter into parts, insert a chapter from another title or source, bookmark, download or hide it.
- Titles: edit the title, author, description, cover and reading status (⋯ → Edit details, or tap the cover).
- Library: Select titles to group them into a series or merge their chapters into one title, file them into tabs or remove them. The shuffle button opens a random title from the tab (hold for the whole library). Filter sheet → Find duplicates.
- Chapters: long-press a chapter → Move to change the reading order, or Add to entry to put it in another library entry (Select → Add to for several).
- New chapters: checked on launch (every 6 hours) or with the refresh button in Library.
- Updates: each deploy ships a new service worker; the app shows "New version available · Restart".
- App lock: a device passkey (Face ID / Touch ID / fingerprint) guards the app on this device. Turn it on in Settings.
- State lives in `src/data/store.tsx`. Suwayomi is read-only (titles, chapters, pages, extensions). The library, tabs and reading progress are stored in Supabase (`src/data/db.ts`, schema in `supabase/migrations/`); the app opens with a password screen (asked every 10 days per device; change it in **Settings → Privacy**).
- Icons: Hugeicons (`@hugeicons/react` + `@hugeicons/core-free-icons`).
