"""Publish one SideStore source that lists every app from the per-app sources."""

import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from publish_sidestore import GitHub  # noqa: E402

TAG = "source"
ASSET = "apps.json"
# Each app keeps publishing its own source; this one only collects them.
SOURCES = [
    "https://github.com/dreed-7896/Midoku/releases/latest/download/apps.json",
    "https://github.com/dreed-7896/IDownloader/releases/download/nightly/source.json",
]


def fetch_json(url):
    if urllib.parse.urlparse(url).hostname != "github.com":
        raise ValueError("Unexpected source host")
    request = urllib.request.Request(url, headers={"User-Agent": "Midoku-source-publisher"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read())


def combine(sources, previous, source_url):
    """Merge per-app sources. An app whose source could not be read keeps its previous listing."""
    apps = {}
    for source in sources:
        for app in (source or {}).get("apps", []):
            if app.get("bundleIdentifier") and app.get("downloadURL") and app.get("versions"):
                apps.setdefault(app["bundleIdentifier"], app)
    if any(source is None for source in sources):
        for app in (previous or {}).get("apps", []):
            apps.setdefault(app.get("bundleIdentifier"), app)
    if not apps:
        raise ValueError("No apps available to publish")
    return {
        "name": "Raahat's Apps",
        "identifier": "com.raahat.source",
        "sourceURL": source_url,
        "subtitle": "Midoku and Pulled testing builds",
        "website": "https://github.com/dreed-7896",
        "iconURL": next((app.get("iconURL") for app in apps.values() if app.get("iconURL")), None),
        "apps": sorted(apps.values(), key=lambda app: app.get("name", "").lower()),
        "news": [],
    }


def publish(api, repo, commit, output):
    root = f"https://api.github.com/repos/{repo}"
    source_url = f"https://github.com/{repo}/releases/download/{TAG}/{ASSET}"
    sources = []
    for url in SOURCES:
        try:
            sources.append(fetch_json(url))
        except Exception as error:  # A failing source must not remove the other apps.
            print(f"Could not read {url}: {error}")
            sources.append(None)
    try:
        previous = fetch_json(source_url)
    except Exception:
        previous = None
    combined = combine(sources, previous, source_url)
    if combined == previous:
        print("Combined source is already current")
        return
    output.write_text(json.dumps(combined, indent=2) + "\n")

    release = api.optional(f"{root}/releases/tags/{TAG}")
    if release is None:
        # A prerelease that is never "latest", so Midoku's latest-release source URL is unaffected.
        release = api.request("POST", f"{root}/releases", {
            "tag_name": TAG,
            "target_commitish": commit,
            "name": "SideStore source (all apps)",
            "body": f"Add this source in SideStore to get every app in one place:\n\n{source_url}",
            "draft": False,
            "prerelease": True,
            "make_latest": "false",
        })
    for asset in api.request("GET", f"{root}/releases/{release['id']}/assets?per_page=100"):
        if asset["name"] == ASSET:
            api.request("DELETE", f"{root}/releases/assets/{asset['id']}")
    upload = release["upload_url"].split("{")[0]
    api.request("POST", upload + "?" + urllib.parse.urlencode({"name": ASSET}), file=output)
    print(f"Published combined source with {len(combined['apps'])} apps: {source_url}")


if __name__ == "__main__":
    publish(GitHub(os.environ["GH_TOKEN"]), os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"],
            Path(sys.argv[1]))
