"""Puts browser items into tracks: at the end of the chain or after the selected device, on the selected track
or on every selected track. Live's newer API calls are used only when present."""


class Loader(object):
    def __init__(self, song, browser):
        self._song = song
        self._browser = browser

    def capabilities(self):
        tracks = list(getattr(self._song, "tracks", []))
        return {
            "move_device": hasattr(self._song, "move_device"),
            "multi_select": any(hasattr(t, "is_part_of_selection") for t in tracks),
        }

    def load(self, items, position="end", all_selected=False):
        """Loads `items` in order. Raises whatever Live raises; the caller turns it into an error reply."""
        song = self._song
        original = song.view.selected_track
        targets = self._selected_tracks() if all_selected else []
        if not targets:
            targets = [original]
        try:
            for track in targets:
                if song.view.selected_track != track:
                    song.view.selected_track = track
                self._load_into(track, items, position)
        finally:
            if song.view.selected_track != original:
                song.view.selected_track = original

    def _selected_tracks(self):
        song = self._song
        everything = list(song.tracks) + list(getattr(song, "return_tracks", []))
        return [t for t in everything if getattr(t, "is_part_of_selection", False)]

    def _load_into(self, track, items, position):
        anchor = track.view.selected_device if position == "after_selected" else None
        can_move = anchor is not None and hasattr(self._song, "move_device")
        for item in items:
            self._browser.load_item(item)
            if not can_move:
                continue
            # Live hands out a new wrapper object per access: compare with ==, never `is`.
            loaded = track.view.selected_device
            devices = list(track.devices)
            if loaded is None or loaded == anchor or anchor not in devices or loaded not in devices:
                continue  # selection didn't move to the new device: leave everything where Live put it
            try:
                self._song.move_device(loaded, track, devices.index(anchor) + 1)
            except Exception:
                continue  # best effort: the device is inserted, just at the end
            anchor = loaded  # the next item of a chain goes behind this one
