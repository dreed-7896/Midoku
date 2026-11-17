# Midoku Web

- Always push work straight to `main`. Do not create side branches.
- Mobile-only PWA built with React, Vite and TypeScript. Run `npm run build` before pushing to confirm it compiles.
- Boxy design: square corners everywhere, dark theme, coral accent (`--accent` in `src/styles.css`). Icons come from Hugeicons (`src/components/Icon.tsx`).
- The app runs on dummy data (`src/data/mock.ts`) and is not connected to Suwayomi yet. `src/data/store.tsx` is the layer to swap when wiring a real backend.
- Library organisation: collections are root folders (a title can sit in more than one). A title that holds nested titles is shown as a series.
- Midoku collection semantics carry over: entries can nest titles, link several sources, hold chapter versions, inserted and split chapters, and removed chapters that can be restored. Reading actions resolve the physical source chapter.
- The reader renders only pages near the current one; keep it that way so very long chapters stay light.
