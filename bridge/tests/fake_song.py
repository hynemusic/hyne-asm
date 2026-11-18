"""Fake Live song/tracks/devices for the loader and action tests."""


class FakeDevice:
    def __init__(self, name):
        self.name = name


class _TrackView:
    def __init__(self):
        self.selected_device = None


class FakeTrack:
    def __init__(self, name, devices=(), selected=False):
        self.name = name
        self.devices = [FakeDevice(d) for d in devices]
        self.view = _TrackView()
        self.is_part_of_selection = selected


class _SongView:
    def __init__(self, track):
        self.selected_track = track


class FakeSong:
    def __init__(self, tracks, selected_index=0, with_move=True):
        self.tracks = tracks
        self.return_tracks = []
        self.master_track = FakeTrack("Master")
        self.view = _SongView(tracks[selected_index])
        self.tempo = 120.0
        self.metronome = False
        self.loop = False
        self.signature_numerator = 4
        self.signature_denominator = 4
        self.record_mode = False
        self.session_record = False
        self.can_undo = True
        self.can_redo = True
        self.calls = []
        if with_move:
            self.move_device = self._move_device

    def _move_device(self, device, target, index):
        target.devices.remove(device)
        target.devices.insert(index, device)

    def create_midi_track(self, index):
        self.calls.append(("create_midi_track", index))

    def create_audio_track(self, index):
        self.calls.append(("create_audio_track", index))

    def create_return_track(self):
        self.calls.append(("create_return_track",))

    def create_scene(self, index):
        self.calls.append(("create_scene", index))

    def duplicate_track(self, index):
        self.calls.append(("duplicate_track", index))

    def tap_tempo(self):
        self.calls.append(("tap_tempo",))

    def undo(self):
        self.calls.append(("undo",))

    def redo(self):
        self.calls.append(("redo",))

    def capture_midi(self):
        self.calls.append(("capture_midi",))

    def stop_all_clips(self):
        self.calls.append(("stop_all_clips",))


class LoadingBrowser:
    """load_item appends a device to the selected track and selects it, like Live."""

    def __init__(self, song):
        self.song = song

    def load_item(self, item):
        track = self.song.view.selected_track
        device = FakeDevice(item.name)
        track.devices.append(device)
        track.view.selected_device = device
