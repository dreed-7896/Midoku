# Import a native Midoku backup (.aib)

Run from this folder, with `../test-server.json` holding the Suwayomi login and app password.

1. `python3 -I -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); open("collection.json","wb").write(d["collectionData"])' Backup.aib`
2. `python3 -I plan.py collection.json plan.json` — entries, edits, chapter names/order/splits, tabs, read marks (no history). Edit `SOURCES` in plan.py to map native source keys to Suwayomi source ids.
3. `node server.cjs` — creates the titles on Suwayomi (via a generated .tachibk restore, not in its library) and fetches chapters; resumable (`server.json`). Sources that don't answer are skipped.
4. `node write.cjs --dry`, then `node write.cjs` — writes entries, sources, tabs, chapter states and splits. Titles without fetched chapters get `chapter_imports` rows that the app applies when their chapters load.
