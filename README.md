# Midoku

Midoku combines the native reader and source engine from [Aidoku-M](https://github.com/Mohammad-Rahat/Aidoku-M) with Midoku’s editable personal collection.

- Independent local entries, title/author/description/cover edits, reading status and categories.
- Copy selected source chapters and paste them into any entry. Explicit duplicate review supports skip, separate, alternative and replacement.
- Persistent mixed-source chapter order, manual ordering, exclusions and source-follow controls.
- Portrait chapter thumbnails, list/grid layouts and custom chapter titles/covers.
- The native reader resolves each release to its own source, image processor, downloads and physical reading history.
- Midoku icon, launch screen, colors, app name, Xcode scheme and `com.raahat.Midoku` identity.

Open `Midoku.xcodeproj` and select the `Midoku` scheme. The app targets iOS 27, matching the original Midoku project. The `main` branch contains the merged app, and its workflow generates unsigned device IPAs for LiveContainer.

Run the portable composition tests with `swift test`. Normal pushes only build and package the IPA. To run collection core and simulator regression checks, manually run the iOS workflow with `run_tests` enabled.

Collection backups are included in the normal `.aib` backup when collection entries are selected. Collection also supports a standalone JSON export/import with a restore preview. Original Midoku app data is not automatically interpreted as Aidoku data; this branch uses a separate `MidokuCollection.json` file and preserves the original Midoku database.

## Attribution

This derivative includes Aidoku code under GNU GPL v3 (see `LICENSE`). Original authorship and copyright notices are retained. AidokuRunner, source ABI names, compatible file protocols, registered tracker/source authentication callbacks and upstream dependency/documentation URLs intentionally retain their original names. This is an independent Midoku fork, not an official Aidoku release.

Base: Aidoku-M `0a17679b67bd8379d6f09de6a3d73054118b60a8`; Midoku collection model and assets: `23ffc8e002ff5f607a4d89f6fdbebe997e529fb4`.
