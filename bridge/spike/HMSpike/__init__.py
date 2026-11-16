# THROWAWAY spike (plan Task 1): does browser.load_item load every plugin type?
import socket
import time

import Live
from _Framework.ControlSurface import ControlSurface

PORT = 47820
ROOTS = ("plugins", "instruments", "audio_effects", "midi_effects", "max_for_live")


def create_instance(c_instance):
    return HMSpike(c_instance)


class HMSpike(ControlSurface):
    def __init__(self, c_instance):
        ControlSurface.__init__(self, c_instance)
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind(("127.0.0.1", PORT))
        self._server.listen(5)
        self._server.setblocking(False)
        self._clients = {}
        self.log_message("HMSpike listening on %d" % PORT)

    def disconnect(self):
        for c in list(self._clients):
            c.close()
        self._server.close()
        ControlSurface.disconnect(self)

    def update_display(self):
        ControlSurface.update_display(self)
        try:
            while True:
                conn, _ = self._server.accept()
                conn.setblocking(False)
                self._clients[conn] = b""
        except (BlockingIOError, OSError):
            pass
        for conn in list(self._clients):
            try:
                data = conn.recv(65536)
                if not data:
                    raise ConnectionError()
                self._clients[conn] += data
            except BlockingIOError:
                pass
            except Exception:
                conn.close()
                del self._clients[conn]
                continue
            while b"\n" in self._clients[conn]:
                line, rest = self._clients[conn].split(b"\n", 1)
                self._clients[conn] = rest
                reply = self._handle(line.decode("utf-8").strip())
                conn.setblocking(True)
                conn.sendall((reply + "\n<<END>>\n").encode("utf-8"))
                conn.setblocking(False)

    def _walk(self, item, path, out, root):
        for child in item.children:
            if child.is_loadable:
                out.append((root, path, child))
            if child.is_folder or len(child.children) > 0:
                self._walk(child, path + [child.name], out, root)

    def _all(self):
        browser = Live.Application.get_application().browser
        out = []
        for root in ROOTS:
            r = getattr(browser, root, None)
            if r is not None:
                self._walk(r, [], out, root)
        return out

    def _handle(self, line):
        try:
            if line == "list":
                t = time.time()
                items = self._all()
                rows = ["%s\t%s\t%s\t/%s" % (root, it.uri, it.name, "/".join(p)) for root, p, it in items]
                rows.append("# %d items in %.0f ms" % (len(items), (time.time() - t) * 1000))
                return "\n".join(rows)
            if line.startswith("load "):
                uri = line[5:]
                for _, _, it in self._all():
                    if it.uri == uri:
                        t = time.time()
                        Live.Application.get_application().browser.load_item(it)
                        return "loaded %s in %.0f ms" % (it.name, (time.time() - t) * 1000)
                return "not_found"
            return "unknown"
        except Exception as e:
            return "error: %r" % (e,)
