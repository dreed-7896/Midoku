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

Mobile-only PWA (React + Vite). It currently runs on **dummy data** (`src/data/mock.ts`) and does not talk to Suwayomi yet.

- `npm run dev` → open port 5173 (in the codespace, from the Ports tab).
- `npm run build` renders the PWA icons from `public/icon.svg`, type-checks and builds to `dist/`.
- Screens: Home feed, Library (tabs, filters, groups, collections), Entry details, Search, Sources, Source browse.
- State lives in `src/data/store.tsx`; swapping the mock for Suwayomi only needs that layer to change.
- Icons: Hugeicons (`@hugeicons/react` + `@hugeicons/core-free-icons`).
