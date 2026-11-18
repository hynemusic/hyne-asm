"""Live actions the app offers besides plugins (new tracks, tempo, metronome …)."""


class ActionError(Exception):
    pass


def _selected_index(song):
    tracks = list(song.tracks)
    selected = song.view.selected_track
    return tracks.index(selected) if selected in tracks else len(tracks) - 1


def _toggle(song, attr):
    setattr(song, attr, not getattr(song, attr))


def run_action(song, name, value=None, value2=None):
    if name == "set_tempo":
        song.tempo = max(20.0, min(999.0, float(value if value is not None else 120)))
    elif name == "set_time_signature":
        song.signature_numerator = int(value or 4)
        song.signature_denominator = int(value2 or 4)
    elif name == "new_midi_track":
        song.create_midi_track(_selected_index(song) + 1)
    elif name == "new_audio_track":
        song.create_audio_track(_selected_index(song) + 1)
    elif name == "new_return_track":
        song.create_return_track()
    elif name == "new_scene":
        song.create_scene(-1)
    elif name == "duplicate_track":
        song.duplicate_track(_selected_index(song))
    elif name == "toggle_metronome":
        _toggle(song, "metronome")
    elif name == "toggle_loop":
        _toggle(song, "loop")
    elif name == "toggle_arrangement_record":
        _toggle(song, "record_mode")
    elif name == "toggle_session_record":
        _toggle(song, "session_record")
    elif name == "tap_tempo":
        song.tap_tempo()
    elif name == "undo":
        if song.can_undo:
            song.undo()
    elif name == "redo":
        if song.can_redo:
            song.redo()
    elif name == "capture_midi":
        song.capture_midi()
    elif name == "stop_all_clips":
        song.stop_all_clips()
    else:
        raise ActionError("unknown_action")
