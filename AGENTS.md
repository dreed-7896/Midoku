# Midoku Web

- Always push work straight to `main`. Do not create side branches.
- Mobile-only PWA built with React, Vite and TypeScript. Run `npm run build` before pushing to confirm it compiles.
- Boxy design: square corners everywhere, dark theme, coral accent (`--accent` in `src/styles.css`). Icons come from Hugeicons (`src/components/Icon.tsx`).
- Suwayomi: the server address (and optional basic-auth login) is entered in Settings and kept on the device; the app calls the server directly (Suwayomi allows any origin, without cookies). No Vercel proxy. `src/data/suwayomi.ts` is the client; without an address the app shows sample data from `src/data/mock.ts`.
- Suwayomi is read-only: it supplies titles, chapters, pages and extensions only. Never write to it, and ignore its reading state.
- Midoku's own data (library, tabs, reading progress, read/bookmark/removed marks) lives in Supabase project `Midoku-web` (`src/data/db.ts`), with row-level security. There are no accounts: one built-in user (`owner@midoku.invalid`), and the app password screen (`PasswordGate` in `src/components/Lock.tsx`) signs in as it. The password is asked again every 10 days per device; it can be changed in Settings → Privacy. Schema changes go in `supabase/migrations/`. Without a server address the sample data is kept in localStorage.
- Server titles use ids `s<mangaId>` and chapters `c<chapterId>` in the app; the database keys titles by source id + manga url and chapter state by source chapter url.
- Library organisation: tabs (categories) the person files titles into, plus Reading, All and saved-filter tabs, in a swipeable pager. A title can be in several tabs. On a server, tabs and filing are stored in Supabase; the Reading tab lists started, unfinished titles. A title that holds nested titles is shown as a series.
- Navigation is a custom screen stack (`StackRoutes` in `src/components/Nav.tsx`): each screen is its own scrolling layer, the previous one stays mounted underneath. Do not go back to the View Transitions API; it misrenders on iOS Safari. The iOS edge swipe is the system's own; history steps the app did not start are not animated again.
- Head tags follow K&K Agro: web manifest only, no `apple-mobile-web-app-capable` or translucent status bar (those leave a black band at the bottom of the installed app on iOS).
- Each deploy gets a new service worker version (`vite.config.ts`); the app offers "Restart to update" when one is waiting.
- Midoku collection semantics carry over: entries can nest titles, link several sources, hold chapter versions, inserted and split chapters, and removed chapters that can be restored. Reading actions resolve the physical source chapter.
- The reader renders only pages near the current one; keep it that way so very long chapters stay light.
