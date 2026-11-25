import time

try:
    from urllib.parse import unquote
except ImportError:  # pragma: no cover - Live's older Python
    from urllib import unquote

ROOTS = ("plugins", "instruments", "audio_effects", "midi_effects", "max_for_live")
PRESET_MARKER = ":FileId_"

# Own presets: only the User Library and the folders added under "Places" in Live's browser.
PRESET_EXTENSIONS = (".adg", ".adv", ".vstpreset", ".aupreset", ".fxp", ".fxb", ".amxd")
# User Library folders that never hold device presets but can be huge (walking them would stall Live).
SKIPPED_USER_LIBRARY_FOLDERS = ("Samples", "Clips", "Grooves", "Templates", "Remote Scripts", "Defaults")
# Upper bound on browser nodes visited per preset root, so a giant sample folder can't freeze Live.
MAX_PRESET_NODES = 40000
# Walking the browser takes ~1 s and blocks Live's UI, so an unknown URI triggers a rebuild at most this often.
MIN_REBUILD_INTERVAL = 30.0


def preset_format(name, uri):
    """The preset's file extension without the dot ("adg"), from its name or URI; None if it is no preset."""
    for text in ((name or "").lower(), unquote(uri or "").lower()):
        for ext in PRESET_EXTENSIONS:
            if text.endswith(ext):
                return ext[1:]
    return None


def is_preset_file(name, uri):
    return preset_format(name, uri) is not None


def display_name(name, fmt):
    suffix = "." + fmt
    return name[:-len(suffix)] if name.lower().endswith(suffix) else name


class BrowserIndex(object):
    """Flattens Live's browser roots into loadable entries: devices and plugins (factory presets excluded)
    plus the user's own presets from the User Library and Places folders."""

    def __init__(self, browser, clock=time.time):
        self._browser = browser
        self._by_uri = {}
        self._items = None
        self._built_at = None
        self._clock = clock

    def build(self):
        items = []
        self._by_uri = {}
        for root in ROOTS:
            node = getattr(self._browser, root, None)
            if node is not None:
                self._walk(node, root, [], items)
        self._walk_presets(items)
        self._items = items
        self._built_at = self._clock()
        return items

    def items(self, refresh=False):
        """The last walk's result; walks the browser only the first time or when asked to (blocks Live ~1 s)."""
        if refresh or self._items is None:
            return self.build()
        return self._items

    def find(self, uri):
        recent = self._built_at is not None and self._clock() - self._built_at < MIN_REBUILD_INTERVAL
        if uri not in self._by_uri and not recent:
            self.build()
        return self._by_uri.get(uri)

    def browse(self, path):
        """Children of a User Library path (debugging aid): name, uri and flags."""
        node = getattr(self._browser, "user_library", None)
        for name in path or []:
            node = next((c for c in node.children if c.name == name), None) if node is not None else None
        if node is None:
            return None
        return [{"name": c.name, "uri": c.uri, "is_folder": bool(c.is_folder), "is_loadable": bool(c.is_loadable)}
                for c in list(node.children)[:300]]

    def _walk(self, node, root, path, out):
        for child in node.children:
            if child.is_loadable and self._keep(root, child.uri):
                out.append({"uri": child.uri, "name": child.name, "source": root, "path": list(path)})
                self._by_uri[child.uri] = child
            if child.is_folder and self._descend(root, child):
                self._walk(child, root, path + [child.name], out)

    @staticmethod
    def _descend(root, node):
        """A loadable plugin or device that is also a folder only holds its presets, which are skipped anyway.
        Not opening them keeps big libraries fast: each node costs a call into Live, and the presets under
        plugins and Live's devices can outnumber the plugins a hundred to one. Max for Live keeps its presets."""
        return root == "max_for_live" or not node.is_loadable

    def _walk_presets(self, out):
        library = getattr(self._browser, "user_library", None)
        if library is not None:
            self._walk_preset_root(library, "user_library", [], out, skip=SKIPPED_USER_LIBRARY_FOLDERS)
        for place in list(getattr(self._browser, "user_folders", None) or []):
            self._walk_preset_root(place, "user_folders", [place.name], out, skip=())

    def _walk_preset_root(self, root_node, source, base, out, skip):
        budget = [MAX_PRESET_NODES]
        stack = [(root_node, list(base), True)]
        while stack and budget[0] > 0:
            node, path, top = stack.pop()
            for child in node.children:
                budget[0] -= 1
                if budget[0] <= 0:
                    return
                fmt = preset_format(child.name, child.uri) if child.is_loadable else None
                if fmt is not None:
                    if child.uri not in self._by_uri:
                        out.append({"uri": child.uri, "name": display_name(child.name, fmt), "source": source,
                                    "path": list(path), "format": fmt})
                        self._by_uri[child.uri] = child
                elif child.is_folder and not (top and child.name in skip):
                    stack.append((child, path + [child.name], False))

    @staticmethod
    def _keep(root, uri):
        return root == "max_for_live" or PRESET_MARKER not in uri
