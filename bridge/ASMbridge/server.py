import json
import socket


class LineServer(object):
    """Non-blocking TCP server for newline-delimited messages; poll() from Live's main thread."""

    def __init__(self, host, port):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind((host, port))
        self._sock.listen(5)
        self._sock.setblocking(False)
        self.port = self._sock.getsockname()[1]
        self._buffers = {}

    def poll(self):
        self._accept()
        lines = []
        for conn in list(self._buffers):
            try:
                data = conn.recv(65536)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                self._drop(conn)
                continue
            if not data:
                self._drop(conn)
                continue
            buf = self._buffers[conn] + data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode("utf-8", "replace").strip()
                if text:
                    lines.append((conn, text))
            self._buffers[conn] = buf
        return lines

    def send(self, conn, obj):
        data = (json.dumps(obj) + "\n").encode("utf-8")
        try:
            conn.setblocking(True)
            conn.settimeout(5)
            conn.sendall(data)
            conn.setblocking(False)
        except OSError:
            self._drop(conn)

    def close(self):
        for conn in list(self._buffers):
            self._drop(conn)
        self._sock.close()

    def _accept(self):
        while True:
            try:
                conn, _ = self._sock.accept()
            except (BlockingIOError, InterruptedError, OSError):
                return
            conn.setblocking(False)
            self._buffers[conn] = b""

    def _drop(self, conn):
        self._buffers.pop(conn, None)
        try:
            conn.close()
        except OSError:
            pass
