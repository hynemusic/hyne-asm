ROOTS = ("plugins", "instruments", "audio_effects", "midi_effects", "max_for_live")
PRESET_MARKER = ":FileId_"


class BrowserIndex(object):
    """Flattens Live's browser roots into loadable device/plugin entries (presets excluded)."""

    def __init__(self, browser):
        self._browser = browser
        self._by_uri = {}

    def build(self):
        items = []
        self._by_uri = {}
        for root in ROOTS:
            node = getattr(self._browser, root, None)
            if node is not None:
                self._walk(node, root, [], items)
        return items

    def find(self, uri):
        if uri not in self._by_uri:
            self.build()
        return self._by_uri.get(uri)

    def _walk(self, node, root, path, out):
        for child in node.children:
            if child.is_loadable and self._keep(root, child.uri):
                out.append({"uri": child.uri, "name": child.name, "source": root, "path": list(path)})
                self._by_uri[child.uri] = child
            if child.is_folder:
                self._walk(child, root, path + [child.name], out)

    @staticmethod
    def _keep(root, uri):
        return root == "max_for_live" or PRESET_MARKER not in uri
