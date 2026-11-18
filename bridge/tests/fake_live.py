class FakeItem:
    def __init__(self, name, uri, children=None, is_loadable=True, is_folder=False):
        self.name = name
        self.uri = uri
        self.children = children or []
        self.is_loadable = is_loadable
        self.is_folder = is_folder


def folder(name, uri, children):
    return FakeItem(name, uri, children, is_loadable=False, is_folder=True)


class FakeBrowser:
    def __init__(self, user_folders=None, **roots):
        for name, children in roots.items():
            setattr(self, name, folder(name, "root:" + name, children))
        self.user_folders = user_folders or []
        self.loaded = []

    def load_item(self, item):
        if item.uri == "boom":
            raise RuntimeError("kaputt")
        self.loaded.append(item)
