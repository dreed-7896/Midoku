# Midoku merged branch

- This branch intentionally uses Aidoku-M as its native reader and source engine, per the user’s merge request. Keep upstream licenses and dependency/ABI identifiers intact.
- The personal collection ports Midoku’s identity, slots/variants, overrides, exclusions and direct chapter insertion semantics. Network and source refresh code must not overwrite user edits or conflate physical chapter identities.
- App branding, project, scheme and bundle identity are Midoku. Target iOS 27 with the existing Midoku team. Unsigned builds are for LiveContainer.
- All chapter page, image, download and progress operations resolve the physical source/manga/chapter tuple. Synthetic reader keys only distinguish variants within a frozen collection sequence.
- Keep preview data under DEBUG. Do not seed it into normal app launches.
- There are no automated tests; the user verifies on device. Run the iOS archive workflow to confirm the app builds.
- Always publish: once the iOS build passes, merge the work to `main` so the workflow publishes the unsigned IPA.
