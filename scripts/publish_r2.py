"""Upload the IPA and a SideStore source (apps.json) to a public Cloudflare R2 bucket.

Standard library only. Configuration comes from the environment:
  R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY  (repository secrets)
  R2_BUCKET, R2_PUBLIC_URL                                (repository variables)

SideStore source URL: <R2_PUBLIC_URL>/apps.json
"""

import hashlib
import hmac
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
KEEP_VERSIONS = 5
ICON = Path("Midoku/App/Resources/Assets.xcassets/AppIcon.appiconset/icon-ios-marketing-1024@1x.png")


class R2:
    def __init__(self, account, key_id, secret, bucket):
        self.host = f"{account}.r2.cloudflarestorage.com"
        self.key_id, self.secret, self.bucket = key_id, secret, bucket

    def _sign(self, key, msg):
        return hmac.new(key, msg.encode(), hashlib.sha256).digest()

    def request(self, method, key, data=b"", content_type=None, cache_control=None):
        now = datetime.now(timezone.utc)
        amz_date, date = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
        path = "/" + urllib.parse.quote(f"{self.bucket}/{key}")
        payload_hash = hashlib.sha256(data).hexdigest()
        headers = {"host": self.host, "x-amz-content-sha256": payload_hash, "x-amz-date": amz_date}
        if content_type:
            headers["content-type"] = content_type
        if cache_control:
            headers["cache-control"] = cache_control
        signed = ";".join(sorted(headers))
        canonical = "\n".join([
            method, path, "",
            "".join(f"{k}:{headers[k]}\n" for k in sorted(headers)),
            signed, payload_hash,
        ])
        scope = f"{date}/auto/s3/aws4_request"
        to_sign = "\n".join(["AWS4-HMAC-SHA256", amz_date, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        k = self._sign(("AWS4" + self.secret).encode(), date)
        for part in ("auto", "s3", "aws4_request"):
            k = self._sign(k, part)
        signature = hmac.new(k, to_sign.encode(), hashlib.sha256).hexdigest()
        headers["authorization"] = (f"AWS4-HMAC-SHA256 Credential={self.key_id}/{scope}, "
                                    f"SignedHeaders={signed}, Signature={signature}")
        request = urllib.request.Request(f"https://{self.host}{path}", data=data or None,
                                         headers=headers, method=method)
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.read()

    def put(self, key, data, content_type, cache_control=None):
        self.request("PUT", key, data, content_type, cache_control)

    def delete(self, key):
        try:
            self.request("DELETE", key)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise


def app_info(ipa_path):
    with zipfile.ZipFile(ipa_path) as ipa:
        plists = [n for n in ipa.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(plists) != 1:
            raise ValueError("IPA must contain exactly one root app Info.plist")
        info = plistlib.loads(ipa.read(plists[0]))
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError("Unexpected app bundle identifier")
    return info


def existing_versions(public):
    try:
        with urllib.request.urlopen(f"{public}/apps.json?ts={int(datetime.now().timestamp())}", timeout=30) as r:
            return json.loads(r.read())["apps"][0].get("versions", [])
    except Exception:
        return []


def main():
    ipa_path = Path(sys.argv[1])
    env = os.environ
    public = env["R2_PUBLIC_URL"].rstrip("/")
    r2 = R2(env["R2_ACCOUNT_ID"], env["R2_ACCESS_KEY_ID"], env["R2_SECRET_ACCESS_KEY"], env["R2_BUCKET"])
    commit = env.get("GITHUB_SHA", "")

    info = app_info(ipa_path)
    version = info["CFBundleShortVersionString"]
    ipa_key = f"Midoku-{version}.ipa"
    print(f"Uploading {ipa_key}")
    r2.put(ipa_key, ipa_path.read_bytes(), "application/octet-stream", "public, max-age=31536000, immutable")
    if ICON.exists():
        r2.put("icon.png", ICON.read_bytes(), "image/png", "public, max-age=86400")

    entry = {
        "version": version,
        "date": datetime.now(timezone.utc).isoformat(),
        "localizedDescription": f"Midoku main build {commit[:7]}.",
        "downloadURL": f"{public}/{ipa_key}",
        "size": ipa_path.stat().st_size,
        "minOSVersion": info["MinimumOSVersion"],
    }
    versions = [entry] + [v for v in existing_versions(public) if v.get("version") != version]
    kept, dropped = versions[:KEEP_VERSIONS], versions[KEEP_VERSIONS:]
    source = {
        "name": "Midoku",
        "identifier": "com.raahat.Midoku.source",
        "sourceURL": f"{public}/apps.json",
        "apps": [{
            "name": "Midoku",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "Raahat",
            "subtitle": "Manga and webtoon reader",
            "localizedDescription": "Midoku manga and webtoon reader. Updates from the main branch.",
            "iconURL": f"{public}/icon.png",
            "versions": kept,
            # Older SideStore versions also accept these legacy fields.
            "version": version,
            "versionDate": entry["date"],
            "versionDescription": entry["localizedDescription"],
            "downloadURL": entry["downloadURL"],
            "size": entry["size"],
        }],
        "news": [],
    }
    # The source changes only after the IPA it points at is uploaded.
    r2.put("apps.json", (json.dumps(source, indent=2) + "\n").encode(), "application/json", "no-cache")
    for old in dropped:
        name = old.get("downloadURL", "").rsplit("/", 1)[-1]
        if re.fullmatch(r"Midoku-[\d.]+\.ipa", name):
            print(f"Removing {name}")
            r2.delete(name)
    print(f"Source: {public}/apps.json")


if __name__ == "__main__":
    main()
