import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fake_live import FakeItem  # noqa: E402
from fake_song import FakeSong, FakeTrack, LoadingBrowser, FakeDevice  # noqa: E402
from ASMbridge.loader import Loader  # noqa: E402


class _Wrapper(object):
    """Live hands out a new Python wrapper per access: equal, but not the same object."""

    def __init__(self, device):
        self.device = device

    def __eq__(self, other):
        return isinstance(other, _Wrapper) and other.device is self.device

    def __ne__(self, other):
        return not self.__eq__(other)

    def __hash__(self):
        return id(self.device)


class LoaderReviewTests(unittest.TestCase):
    def test_move_failure_keeps_the_insert_and_continues_with_other_tracks(self):
        a, b = FakeTrack("A", ["EQ"], selected=True), FakeTrack("B", ["EQ"], selected=True)
        a.view.selected_device = a.devices[0]
        b.view.selected_device = b.devices[0]
        song = FakeSong([a, b])

        def broken_move(device, target, index):
            raise RuntimeError("cannot move")
        song.move_device = broken_move
        Loader(song, LoadingBrowser(song)).load([FakeItem("Comp", "u:c")], position="after_selected", all_selected=True)
        self.assertEqual([d.name for d in a.devices], ["EQ", "Comp"])
        self.assertEqual([d.name for d in b.devices], ["EQ", "Comp"])   # second track still got it

    def test_wrapped_devices_compare_by_value(self):
        t = FakeTrack("A", ["EQ", "Verb"])
        t.view.selected_device = t.devices[0]
        song = FakeSong([t])

        class WrappingTrackView(object):
            def __init__(self, view):
                self._view = view

            @property
            def selected_device(self):
                d = self._view.selected_device
                return _Wrapper(d) if d is not None else None

        devices = t.devices

        class WrappedTrack(object):
            name = "A"
            view = WrappingTrackView(t.view)

            @property
            def devices(self):
                return [_Wrapper(d) for d in devices]

        wrapped = WrappedTrack()
        song.tracks = [wrapped]
        song.view.selected_track = wrapped

        def move(device, target, index):
            devices.remove(device.device)
            devices.insert(index, device.device)
        song.move_device = move

        class Browser(object):
            def load_item(self, item):
                devices.append(FakeDevice(item.name))   # Live left the selection on EQ

        Loader(song, Browser()).load([FakeItem("Comp", "u:c")], position="after_selected")
        # The selection didn't move to the new device, so nothing may be moved (EQ stays first).
        self.assertEqual([d.name for d in devices], ["EQ", "Verb", "Comp"])


if __name__ == "__main__":
    unittest.main()
