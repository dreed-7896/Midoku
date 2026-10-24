import importlib.util
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location(
    "combined", Path(__file__).parents[1] / "publish_combined_source.py")
combined = importlib.util.module_from_spec(spec)
spec.loader.exec_module(combined)


def app(bundle, name, version):
    return {"bundleIdentifier": bundle, "name": name, "version": version,
            "downloadURL": f"https://example.com/{bundle}.ipa", "versions": [{"version": version}]}


class CombinedSourceTests(unittest.TestCase):
    def test_lists_every_app_once(self):
        result = combined.combine([
            {"apps": [app("com.raahat.Midoku", "Midoku", "0.9.2")]},
            {"apps": [app("com.dreed7896.IDownloader", "Pulled", "1.0.3"), app("com.raahat.Midoku", "Midoku", "0.9.1")]},
        ], None, "https://github.com/o/r/releases/download/source/apps.json")
        self.assertEqual([a["name"] for a in result["apps"]], ["Midoku", "Pulled"])
        self.assertEqual(result["apps"][0]["version"], "0.9.2")
        self.assertEqual(result["sourceURL"], "https://github.com/o/r/releases/download/source/apps.json")

    def test_unreachable_source_keeps_previous_listing(self):
        previous = {"apps": [app("com.dreed7896.IDownloader", "Pulled", "1.0.3")]}
        result = combined.combine([{"apps": [app("com.raahat.Midoku", "Midoku", "0.9.2")]}, None], previous, "url")
        self.assertEqual({a["bundleIdentifier"] for a in result["apps"]}, {"com.raahat.Midoku", "com.dreed7896.IDownloader"})

    def test_removed_app_is_dropped_when_all_sources_answer(self):
        previous = {"apps": [app("old.app", "Old", "1.0.0")]}
        result = combined.combine([{"apps": [app("com.raahat.Midoku", "Midoku", "0.9.2")]}, {"apps": []}], previous, "url")
        self.assertEqual([a["bundleIdentifier"] for a in result["apps"]], ["com.raahat.Midoku"])

    def test_nothing_to_publish_fails(self):
        with self.assertRaises(ValueError):
            combined.combine([None, None], None, "url")


if __name__ == "__main__":
    unittest.main()
