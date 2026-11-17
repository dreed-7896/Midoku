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
- Updates: each deploy ships a new service worker; the app shows "New version available · Restart".
- App lock: a device passkey (Face ID / Touch ID / fingerprint) guards the app on this device. Turn it on in Settings.
- State lives in `src/data/store.tsx`. Suwayomi is read-only (titles, chapters, pages, extensions). The library, tabs and reading progress are stored in Supabase (`src/data/db.ts`, schema in `supabase/migrations/`); sign in under **Settings → Account**.
- Icons: Hugeicons (`@hugeicons/react` + `@hugeicons/core-free-icons`).
