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

- Dev (inside the codespace): `npm run dev` → open port 5173. `/api` is proxied to Suwayomi.
- Vercel: set `SUWAYOMI_URL` to the Suwayomi URL (e.g. the codespace's public 4567 URL). `/api/*` is forwarded there by `api/suwayomi.ts`.
