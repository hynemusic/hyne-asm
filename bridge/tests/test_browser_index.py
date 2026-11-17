import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fake_live import FakeBrowser, FakeItem, folder  # noqa: E402
from ASMbridge.browser_index import BrowserIndex  # noqa: E402


def sample_browser():
    prol = FakeItem("Pro-L 2", "query:Plugins#VST3:FabFilter:Pro-L%202", children=[
        FakeItem("Pro-L 2.vstpreset", "query:Plugins#VST3:FabFilter:Pro-L%202:FileId_1"),
    ])
    return FakeBrowser(
        plugins=[folder("VST3", "u:vst3", [folder("FabFilter", "u:ff", [prol])])],
        audio_effects=[FakeItem("EQ Eight", "query:AudioFx#EQ%20Eight")],
        instruments=[FakeItem("Analog", "query:Synths#Analog", children=[
            folder("Bass", "u:bass", [FakeItem("Basic.adg", "query:Synths#Analog:Bass:FileId_9")])])],
        max_for_live=[folder("Max Audio Effect", "u:mae", [
            FakeItem("Carver 1.2", "query:M4L#Max%20Audio%20Effect:FileId_350335")])],
    )


class BrowserIndexTests(unittest.TestCase):
    def test_list_returns_items_from_all_roots_with_paths(self):
        items = BrowserIndex(sample_browser()).build()
        by_name = {i["name"]: i for i in items}
        self.assertEqual(by_name["Pro-L 2"], {
            "uri": "query:Plugins#VST3:FabFilter:Pro-L%202", "name": "Pro-L 2",
            "source": "plugins", "path": ["VST3", "FabFilter"]})
        self.assertEqual(by_name["EQ Eight"]["source"], "audio_effects")
        self.assertEqual(by_name["EQ Eight"]["path"], [])
        self.assertNotIn("FabFilter", by_name)

    def test_presets_excluded_except_max_for_live(self):
        names = {i["name"] for i in BrowserIndex(sample_browser()).build()}
        self.assertNotIn("Pro-L 2.vstpreset", names)
        self.assertNotIn("Basic.adg", names)
        self.assertIn("Analog", names)
        self.assertIn("Carver 1.2", names)

    def test_missing_root_is_skipped(self):
        items = BrowserIndex(FakeBrowser(audio_effects=[FakeItem("Utility", "u:util")])).build()
        self.assertEqual([i["name"] for i in items], ["Utility"])

    def test_list_with_3000_items(self):
        many = [FakeItem("P%d" % n, "u:%d" % n) for n in range(3000)]
        items = BrowserIndex(FakeBrowser(plugins=many)).build()
        self.assertEqual(len(items), 3000)

    def test_find_rebuilds_once_on_miss(self):
        browser = FakeBrowser(audio_effects=[FakeItem("EQ Eight", "u:eq")])
        index = BrowserIndex(browser)
        index.build()
        browser.audio_effects.children.append(FakeItem("Utility", "u:util"))
        self.assertEqual(index.find("u:util").name, "Utility")
        self.assertIsNone(index.find("u:nope"))


if __name__ == "__main__":
    unittest.main()
