import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fake_live import FakeItem  # noqa: E402
from fake_song import FakeSong, FakeTrack, LoadingBrowser  # noqa: E402
from ASMbridge.loader import Loader  # noqa: E402


def names(track):
    return [d.name for d in track.devices]


class LoaderTests(unittest.TestCase):
    def test_end_of_chain_by_default(self):
        t = FakeTrack("A", ["EQ", "Comp"])
        song = FakeSong([t])
        Loader(song, LoadingBrowser(song)).load([FakeItem("Lim", "u:l")])
        self.assertEqual(names(t), ["EQ", "Comp", "Lim"])

    def test_after_selected_device_keeps_chain_order(self):
        t = FakeTrack("A", ["EQ", "Comp", "Lim"])
        t.view.selected_device = t.devices[0]
        song = FakeSong([t])
        Loader(song, LoadingBrowser(song)).load([FakeItem("Sat", "u:s"), FakeItem("Verb", "u:v")], position="after_selected")
        self.assertEqual(names(t), ["EQ", "Sat", "Verb", "Comp", "Lim"])

    def test_after_selected_without_move_api_falls_back_to_end(self):
        t = FakeTrack("A", ["EQ", "Comp"])
        t.view.selected_device = t.devices[0]
        song = FakeSong([t], with_move=False)
        Loader(song, LoadingBrowser(song)).load([FakeItem("Sat", "u:s")], position="after_selected")
        self.assertEqual(names(t), ["EQ", "Comp", "Sat"])

    def test_all_selected_tracks_and_selection_restored(self):
        a, b, c = FakeTrack("A", selected=True), FakeTrack("B", selected=False), FakeTrack("C", selected=True)
        song = FakeSong([a, b, c], selected_index=2)
        Loader(song, LoadingBrowser(song)).load([FakeItem("Utility", "u:u")], all_selected=True)
        self.assertEqual((names(a), names(b), names(c)), (["Utility"], [], ["Utility"]))
        self.assertIs(song.view.selected_track, c)

    def test_all_selected_off_loads_only_selected_track(self):
        a, c = FakeTrack("A", selected=True), FakeTrack("C", selected=True)
        song = FakeSong([a, c], selected_index=1)
        Loader(song, LoadingBrowser(song)).load([FakeItem("Utility", "u:u")], all_selected=False)
        self.assertEqual((names(a), names(c)), ([], ["Utility"]))

    def test_capabilities(self):
        song = FakeSong([FakeTrack("A")])
        self.assertEqual(Loader(song, None).capabilities(), {"move_device": True, "multi_select": True})
        song = FakeSong([FakeTrack("A")], with_move=False)
        self.assertFalse(Loader(song, None).capabilities()["move_device"])


if __name__ == "__main__":
    unittest.main()
