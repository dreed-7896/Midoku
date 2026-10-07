# SideStore updates

After the first successful release build, add this source in SideStore's Sources screen:

https://github.com/dreed-7896/Midoku/releases/latest/download/apps.json

Install/update Midoku from that listing using the same Apple ID as your existing installation. Do not delete your existing app: uninstalling can remove its reading data. If SideStore does not associate the manually installed app with the source, install the source's Midoku over the existing app, without uninstalling first.

Future successful main builds appear in the source. Tap Update in SideStore; you no longer need to download Actions artifacts manually. Signing refresh and installing a newer version are separate operations.

The IPA remains unsigned; SideStore performs signing. The app still requires iOS 27. Native code changes require an IPA update, not a hot patch.

## Publishing

The IPA workflow uses versions `0.9.<workflow run number>` so updates are detectable even when the project marketing version has not changed. Reruns use the same version. Published releases are not overwritten. The next marketing series should update the workflow's `0.9` prefix.

`scripts/publish_sidestore.py` reads the packaged IPA's bundle ID, version, minimum iOS version and file size. It uploads a versioned IPA and source JSON to a draft GitHub Release, then publishes it as latest only after all uploads succeed. Failed/superseded builds leave the previous public source untouched. Incomplete drafts can be resumed on rerun. No extra secrets are needed; the build job uses `GITHUB_TOKEN` with repository contents write permission.

The source uses the stable latest-release download URL; each listed IPA uses an immutable version-specific URL. No generated commits or separate source branch are needed.

Run publishing tests with `python3 -m unittest discover -s scripts/tests -v`.
