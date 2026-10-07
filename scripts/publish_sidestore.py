"""Publish a complete SideStore release using only Python's standard library."""

import json
import os
import plistlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

BUNDLE_ID = "com.raahat.Midoku"


def make_source(ipa_path, repo, commit):
    with zipfile.ZipFile(ipa_path) as ipa:
        plists = [name for name in ipa.namelist()
                  if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        if len(plists) != 1:
            raise ValueError("IPA must contain exactly one root app Info.plist")
        info = plistlib.loads(ipa.read(plists[0]))
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError("Unexpected app bundle identifier")
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected an automatically numbered three-part version")
    tag = "v" + version
    base = f"https://github.com/{repo}/releases"
    entry = {
        "version": version,
        "date": datetime.now(timezone.utc).isoformat(),
        "localizedDescription": f"Midoku main build {commit[:7]}.",
        "downloadURL": f"{base}/download/{tag}/{ipa_path.name}",
        "size": ipa_path.stat().st_size,
        "minOSVersion": info["MinimumOSVersion"],
    }
    source = {
        "name": "Midoku",
        "identifier": "com.raahat.Midoku.source",
        "sourceURL": f"{base}/latest/download/apps.json",
        "apps": [{
            "name": "Midoku",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "Raahat",
            "subtitle": "Manga and webtoon reader",
            "localizedDescription": "Midoku manga and webtoon reader. Updates from the main branch.",
            "iconURL": f"https://raw.githubusercontent.com/{repo}/{commit}/"
                       "Midoku/App/Resources/Assets.xcassets/AppIcon.appiconset/"
                       "icon-ios-marketing-1024@1x.png",
            "versions": [entry],
            # Older SideStore versions also accept these legacy fields.
            "version": version,
            "versionDate": entry["date"],
            "versionDescription": entry["localizedDescription"],
            "downloadURL": entry["downloadURL"],
            "size": entry["size"],
        }],
        "news": [],
    }
    return tag, source


class GitHub:
    def __init__(self, token):
        self.token = token

    def request(self, method, url, payload=None, file=None):
        if urllib.parse.urlparse(url).hostname not in ("api.github.com", "uploads.github.com"):
            raise ValueError("Unexpected GitHub API host")
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Midoku-release-publisher",
        }
        data = None
        if file is not None:
            data = file.read_bytes()
            headers["Content-Type"] = "application/octet-stream"
        elif payload is not None:
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(request, timeout=300) as response:
            body = response.read()
            return json.loads(body) if body else None

    def optional(self, url):
        try:
            return self.request("GET", url)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            return None


def publish(api, ipa_path, repo, commit):
    tag, source = make_source(ipa_path, repo, commit)
    root = f"https://api.github.com/repos/{repo}"
    # Never let a queued older build replace the current main release.
    if api.request("GET", f"{root}/git/ref/heads/main")["object"]["sha"] != commit:
        print("Skipping superseded main build")
        return
    latest = api.optional(f"{root}/releases/latest")
    if latest and re.fullmatch(r"v\d+\.\d+\.\d+", latest["tag_name"]):
        current = tuple(map(int, tag[1:].split(".")))
        previous = tuple(map(int, latest["tag_name"][1:].split(".")))
        if previous >= current:
            print("Release already published, or a newer version exists")
            return
    release = api.optional(f"{root}/releases/tags/{tag}")
    if release and not release["draft"]:
        print("Release already published; keeping its assets immutable")
        return
    if release is None:
        release = api.request("POST", f"{root}/releases", {
            "tag_name": tag,
            "target_commitish": commit,
            "name": f"Midoku {tag[1:]}",
            "body": f"Main build `{commit}`.\n\nInstall or update through SideStore. "
                    "This IPA is unsigned; SideStore signs it with your Apple ID.",
            "draft": True,
            "prerelease": False,
        })
    source_path = ipa_path.parent / "apps.json"
    source_path.write_text(json.dumps(source, indent=2) + "\n")
    # Only incomplete draft assets can be replaced (e.g. after a failed upload).
    assets = api.request("GET", f"{root}/releases/{release['id']}/assets?per_page=100")
    files = [ipa_path, source_path, ipa_path.parent / "SHA256SUMS.txt", ipa_path.parent / "BUILD.txt"]
    for file in files:
        for asset in assets:
            if asset["name"] == file.name:
                api.request("DELETE", f"{root}/releases/assets/{asset['id']}")
        upload = release["upload_url"].split("{")[0]
        api.request("POST", upload + "?" + urllib.parse.urlencode({"name": file.name}), file=file)
    # The stable source URL changes only after every asset has uploaded.
    if api.request("GET", f"{root}/git/ref/heads/main")["object"]["sha"] != commit:
        print("Build superseded during upload; leaving release as a draft")
        return
    api.request("PATCH", f"{root}/releases/{release['id']}", {
        "draft": False, "make_latest": "true",
    })
    print(f"Published {tag}; SideStore source: {source['sourceURL']}")


if __name__ == "__main__":
    publish(GitHub(os.environ["GH_TOKEN"]), Path(sys.argv[1]),
            os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"])
