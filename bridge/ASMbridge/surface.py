import json

import Live
from _Framework.ControlSurface import ControlSurface

from .browser_index import BrowserIndex
from .loader import Loader
from .protocol import handle_request
from .server import LineServer

PORT = 47820


class ASMbridge(ControlSurface):
    def __init__(self, c_instance):
        ControlSurface.__init__(self, c_instance)
        app = Live.Application.get_application()
        self._browser = app.browser
        self._live_version = "%d.%d.%d" % (
            app.get_major_version(), app.get_minor_version(), app.get_bugfix_version())
        self._index = BrowserIndex(self._browser)
        self._song = self.song()
        self._loader = Loader(self._song, self._browser)
        self._server = None
        try:
            self._server = LineServer("127.0.0.1", PORT)
            self.log_message("ASMbridge listening on %d" % PORT)
        except OSError as e:
            self.log_message("ASMbridge could not listen on %d: %s" % (PORT, e))

    def disconnect(self):
        if self._server is not None:
            self._server.close()
            self._server = None
        ControlSurface.disconnect(self)

    def update_display(self):
        ControlSurface.update_display(self)
        if self._server is None:
            return
        for conn, line in self._server.poll():
            try:
                req = json.loads(line)
            except ValueError:
                req = None
            self._server.send(conn, handle_request(req, self._index, self._browser, self._live_version,
                                                         loader=self._loader, song=self._song))
