import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fake_live import FakeBrowser, FakeItem, folder  # noqa: E402
from ASMbridge import browser_index  # noqa: E402
from ASMbridge.browser_index import BrowserIndex, is_preset_file  # noqa: E402


def library_browser():
    return FakeBrowser(
        audio_effects=[FakeItem("EQ Eight", "query:AudioFx#EQ%20Eight")],
        user_library=[
            folder("Presets", "u:presets", [
                folder("Audio Effects", "u:fx", [
                    FakeItem("My Glue.adg", "userlibrary:Presets/Audio%20Effects/My%20Glue.adg"),
                    FakeItem("Vocal Chain", "userlibrary:Presets/Audio%20Effects/Vocal%20Chain.adg"),
                ]),
                FakeItem("Lead.vstpreset", "userlibrary:Presets/Lead.vstpreset"),
            ]),
            folder("Samples", "u:samples", [FakeItem("Kick.adg", "userlibrary:Samples/Kick.adg")]),
            FakeItem("Loop.wav", "userlibrary:Loop.wav"),
            FakeItem("Song.als", "userlibrary:Song.als"),
        ],
        user_folders=[folder("My Racks", "place:racks", [FakeItem("Bus.adg", "place:racks/Bus.adg")])],
    )


class UserPresetTests(unittest.TestCase):
    def setUp(self):
        self.items = BrowserIndex(library_browser()).build()
        self.by_name = {i["name"]: i for i in self.items}
        self.by_uri = {i["uri"]: i for i in self.items}

    def test_user_library_presets_listed_with_path(self):
        glue = self.by_name["My Glue"]
        self.assertEqual(glue["source"], "user_library")
        self.assertEqual(glue["path"], ["Presets", "Audio Effects"])
        self.assertEqual(glue["format"], "adg")
        self.assertEqual(self.by_name["Lead"]["format"], "vstpreset")
        self.assertEqual(self.by_name["Lead"]["path"], ["Presets"])

    def test_extension_taken_from_uri_when_name_hides_it(self):
        self.assertEqual(self.by_name["Vocal Chain"]["format"], "adg")

    def test_samples_folder_and_non_presets_are_skipped(self):
        for name in ("Kick", "Loop.wav", "Song.als", "Loop", "Song"):
            self.assertNotIn(name, self.by_name)

    def test_places_folders_listed_under_their_name(self):
        self.assertEqual(self.by_name["Bus"]["source"], "user_folders")
        self.assertEqual(self.by_name["Bus"]["path"], ["My Racks"])

    def test_devices_still_listed_and_presets_findable(self):
        index = BrowserIndex(library_browser())
        self.assertEqual(index.find("place:racks/Bus.adg").name, "Bus.adg")
        self.assertIn("EQ Eight", self.by_name)
        self.assertNotIn("format", self.by_name["EQ Eight"])

    def test_node_budget_stops_runaway_walk(self):
        old = browser_index.MAX_PRESET_NODES
        browser_index.MAX_PRESET_NODES = 10
        try:
            many = [FakeItem("P%d.adg" % n, "u:%d.adg" % n) for n in range(100)]
            items = BrowserIndex(FakeBrowser(user_library=many)).build()
            self.assertLess(len(items), 10)
        finally:
            browser_index.MAX_PRESET_NODES = old

    def test_is_preset_file(self):
        self.assertTrue(is_preset_file("X.ADV", ""))
        self.assertTrue(is_preset_file("X", "a/X.aupreset"))
        self.assertFalse(is_preset_file("X.alc", "a/X.alc"))

    def test_browse_lists_children(self):
        index = BrowserIndex(library_browser())
        names = [c["name"] for c in index.browse(["Presets"])]
        self.assertEqual(names, ["Audio Effects", "Lead.vstpreset"])
        self.assertIsNone(index.browse(["Nope"]))


if __name__ == "__main__":
    unittest.main()
