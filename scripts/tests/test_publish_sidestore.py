import importlib.util
import json
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "publisher", Path(__file__).parents[1] / "publish_sidestore.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class FakeAPI:
    def __init__(self, head="abc1234", latest=None, fail_upload=False, draft=None):
        self.head = head
        self.latest = latest
        self.fail_upload = fail_upload
        self.draft = draft
        self.calls = []

    def optional(self, url):
        return self.latest if url.endswith("/latest") else self.draft

    def request(self, method, url, payload=None, file=None):
        self.calls.append((method, url, payload, file))
        if url.endswith("/git/ref/heads/main"):
            return {"object": {"sha": self.head}}
        if method == "POST" and url.endswith("/releases"):
            return {"id": 42, "upload_url": "https://uploads.github.com/repos/o/r/releases/42/assets{?name,label}"}
        if method == "GET" and "/assets?" in url:
            return [{"id": 99, "name": "apps.json"}] if self.draft else []
        if file and self.fail_upload:
            raise RuntimeError("Upload failed")
        return {}


class PublishingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ipa = Path(self.temp.name) / "Midoku-unsigned.ipa"
        self.write_ipa()
        for name in ("BUILD.txt", "SHA256SUMS.txt"):
            (self.ipa.parent / name).write_text("fixture\n")

    def write_ipa(self, bundle=publisher.BUNDLE_ID, version="0.9.123"):
        with zipfile.ZipFile(self.ipa, "w") as ipa:
            ipa.writestr("Payload/Midoku.app/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": bundle,
                "CFBundleShortVersionString": version,
                "MinimumOSVersion": "27.0",
            }, fmt=plistlib.FMT_BINARY))
            ipa.writestr("Payload/Midoku.app/Frameworks/F.app/Info.plist", b"ignored")

    def test_source_matches_binary_and_uses_versioned_download(self):
        tag, source = publisher.make_source(self.ipa, "o/r", "abc1234")
        self.assertEqual(tag, "v0.9.123")
        app = source["apps"][0]
        entry = app["versions"][0]
        self.assertEqual(app["bundleIdentifier"], publisher.BUNDLE_ID)
        self.assertEqual(entry["version"], app["version"])
        self.assertEqual(entry["minOSVersion"], "27.0")
        self.assertEqual(entry["size"], self.ipa.stat().st_size)
        self.assertIn("/download/v0.9.123/", entry["downloadURL"])
        self.assertTrue(source["sourceURL"].endswith("/latest/download/apps.json"))
        self.assertNotIn("buildVersion", entry)
        self.assertNotIn("marketplaceID", app)

    def test_rejects_wrong_bundle_and_unnumbered_version(self):
        for bundle, version in (("app.aidoku.Aidoku", "0.9.123"), (publisher.BUNDLE_ID, "0.9")):
            with self.subTest(bundle=bundle, version=version):
                self.write_ipa(bundle, version)
                with self.assertRaises(ValueError):
                    publisher.make_source(self.ipa, "o/r", "abc1234")

    def test_uploads_all_assets_before_publishing(self):
        api = FakeAPI()
        publisher.publish(api, self.ipa, "o/r", "abc1234")
        uploads = [call for call in api.calls if call[3]]
        self.assertEqual([call[3].name for call in uploads],
                         ["Midoku-unsigned.ipa", "apps.json", "SHA256SUMS.txt", "BUILD.txt"])
        self.assertEqual(api.calls[-1][0], "PATCH")
        self.assertEqual(api.calls[-1][2], {"draft": False, "make_latest": "true"})
        self.assertTrue(next(call[2] for call in api.calls if call[0] == "POST" and not call[3])["draft"])
        self.assertEqual(json.loads((self.ipa.parent / "apps.json").read_text())["apps"][0]["version"], "0.9.123")

    def test_failed_upload_never_publishes(self):
        api = FakeAPI(fail_upload=True)
        with self.assertRaises(RuntimeError):
            publisher.publish(api, self.ipa, "o/r", "abc1234")
        self.assertFalse(any(call[0] == "PATCH" for call in api.calls))

    def test_build_superseded_during_upload_stays_draft(self):
        class SupersededAPI(FakeAPI):
            def request(self, method, url, payload=None, file=None):
                result = super().request(method, url, payload, file)
                if file:
                    self.head = "new"
                return result
        api = SupersededAPI()
        publisher.publish(api, self.ipa, "o/r", "abc1234")
        self.assertFalse(any(call[0] == "PATCH" for call in api.calls))

    def test_skips_superseded_or_already_published_builds(self):
        for api in (FakeAPI(head="new"), FakeAPI(latest={"tag_name": "v0.9.123"}),
                    FakeAPI(latest={"tag_name": "v0.9.124"}), FakeAPI(draft={"draft": False})):
            publisher.publish(api, self.ipa, "o/r", "abc1234")
            self.assertFalse(any(call[0] != "GET" for call in api.calls))

    def test_resumes_draft_replacing_only_incomplete_assets(self):
        api = FakeAPI(draft={"draft": True, "id": 42,
                             "upload_url": "https://uploads.github.com/repos/o/r/releases/42/assets{?name,label}"})
        publisher.publish(api, self.ipa, "o/r", "abc1234")
        self.assertFalse(any(call[0] == "POST" and call[1].endswith("/releases") for call in api.calls))
        self.assertTrue(any(call[0] == "DELETE" and call[1].endswith("/assets/99") for call in api.calls))
        self.assertEqual(api.calls[-1][0], "PATCH")


if __name__ == "__main__":
    unittest.main()
