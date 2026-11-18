import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fake_song import FakeSong, FakeTrack  # noqa: E402
from ASMbridge.actions import run_action, ActionError  # noqa: E402


class ActionTests(unittest.TestCase):
    def setUp(self):
        self.song = FakeSong([FakeTrack("A"), FakeTrack("B")], selected_index=0)

    def test_tempo_and_signature(self):
        run_action(self.song, "set_tempo", 128)
        self.assertEqual(self.song.tempo, 128)
        run_action(self.song, "set_time_signature", 7, 8)
        self.assertEqual((self.song.signature_numerator, self.song.signature_denominator), (7, 8))

    def test_tempo_is_clamped_to_live_range(self):
        run_action(self.song, "set_tempo", 5000)
        self.assertEqual(self.song.tempo, 999)

    def test_new_tracks_go_after_the_selected_one(self):
        run_action(self.song, "new_midi_track")
        run_action(self.song, "new_audio_track")
        self.assertEqual(self.song.calls, [("create_midi_track", 1), ("create_audio_track", 1)])

    def test_toggles(self):
        run_action(self.song, "toggle_metronome")
        run_action(self.song, "toggle_loop")
        run_action(self.song, "toggle_arrangement_record")
        self.assertEqual((self.song.metronome, self.song.loop, self.song.record_mode), (True, True, True))

    def test_simple_calls(self):
        for name in ("tap_tempo", "undo", "redo", "capture_midi", "stop_all_clips", "new_scene", "duplicate_track", "new_return_track"):
            run_action(self.song, name)
        self.assertEqual([c[0] for c in self.song.calls],
                         ["tap_tempo", "undo", "redo", "capture_midi", "stop_all_clips", "create_scene", "duplicate_track", "create_return_track"])

    def test_unknown_action(self):
        with self.assertRaises(ActionError):
            run_action(self.song, "launch_rocket")


if __name__ == "__main__":
    unittest.main()
