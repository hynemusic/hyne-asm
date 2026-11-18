import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fake_live import FakeBrowser, FakeItem  # noqa: E402
from fake_song import FakeSong, FakeTrack, LoadingBrowser  # noqa: E402
from ASMbridge.browser_index import BrowserIndex  # noqa: E402
from ASMbridge.loader import Loader  # noqa: E402
from ASMbridge.protocol import handle_request  # noqa: E402


class ProtocolV4Tests(unittest.TestCase):
    def setUp(self):
        self.track = FakeTrack("A", ["EQ"])
        self.track.view.selected_device = self.track.devices[0]
        self.song = FakeSong([self.track])
        index_browser = FakeBrowser(audio_effects=[FakeItem("Comp", "u:c"), FakeItem("Lim", "u:l")])
        self.index = BrowserIndex(index_browser)
        self.loader = Loader(self.song, LoadingBrowser(self.song))

    def call(self, req):
        return handle_request(req, self.index, None, "12.4.16", loader=self.loader, song=self.song)

    def test_hello_reports_capabilities(self):
        r = self.call({"id": 1, "cmd": "hello"})
        self.assertEqual(r["result"]["script_version"], "4")
        self.assertEqual(r["result"]["capabilities"], {"move_device": True, "multi_select": True})

    def test_load_several_uris_with_position(self):
        r = self.call({"id": 2, "cmd": "load", "uris": ["u:c", "u:l"], "position": "end"})
        self.assertTrue(r["ok"])
        self.assertEqual([d.name for d in self.track.devices], ["EQ", "Comp", "Lim"])

    def test_load_after_selected(self):
        self.track.devices.append(type(self.track.devices[0])("Verb"))
        r = self.call({"id": 3, "cmd": "load", "uris": ["u:c"], "position": "after_selected"})
        self.assertTrue(r["ok"])
        self.assertEqual([d.name for d in self.track.devices], ["EQ", "Comp", "Verb"])

    def test_old_single_uri_request_still_works(self):
        r = self.call({"id": 4, "cmd": "load", "uri": "u:l"})
        self.assertTrue(r["ok"])
        self.assertEqual([d.name for d in self.track.devices], ["EQ", "Lim"])

    def test_missing_uri_in_chain_is_not_found_and_loads_nothing(self):
        r = self.call({"id": 5, "cmd": "load", "uris": ["u:c", "u:nope"]})
        self.assertEqual((r["ok"], r["error"]), (False, "not_found: u:nope"))
        self.assertEqual([d.name for d in self.track.devices], ["EQ"])

    def test_action(self):
        r = self.call({"id": 6, "cmd": "action", "name": "set_tempo", "value": 174})
        self.assertTrue(r["ok"])
        self.assertEqual(self.song.tempo, 174)
        r = self.call({"id": 7, "cmd": "action", "name": "nope"})
        self.assertEqual((r["ok"], r["error"]), (False, "unknown_action"))


if __name__ == "__main__":
    unittest.main()
