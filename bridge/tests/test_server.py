import json
import os
import socket
import sys
import threading
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from ASMbridge.server import LineServer  # noqa: E402


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.server = LineServer("127.0.0.1", 0)
        self.client = socket.create_connection(("127.0.0.1", self.server.port), timeout=2)

    def tearDown(self):
        self.client.close()
        self.server.close()

    def poll_until(self, count, timeout=2.0):
        got = []
        end = time.time() + timeout
        while len(got) < count and time.time() < end:
            got += self.server.poll()
            time.sleep(0.01)
        return got

    def test_server_handles_line_split_across_sends(self):
        self.poll_until(0, 0.05)
        self.client.sendall(b'{"id": 1, "cm')
        self.assertEqual(self.poll_until(1, 0.2), [])
        self.client.sendall(b'd": "hello"}\n')
        got = self.poll_until(1)
        self.assertEqual([line for _, line in got], ['{"id": 1, "cmd": "hello"}'])

    def test_server_two_messages_in_one_send(self):
        self.client.sendall(b'{"id": 1}\n{"id": 2}\n')
        got = self.poll_until(2)
        self.assertEqual([line for _, line in got], ['{"id": 1}', '{"id": 2}'])

    def test_send_large_reply_arrives_complete(self):
        self.client.sendall(b'{"id": 1}\n')
        conn, _ = self.poll_until(1)[0]
        payload = {"items": ["x" * 100] * 30000}
        received = []

        def read():
            buf = b""
            while not buf.endswith(b"\n"):
                buf += self.client.recv(65536)
            received.append(buf)

        reader = threading.Thread(target=read)
        reader.start()
        self.server.send(conn, payload)
        reader.join(5)
        self.assertEqual(json.loads(received[0].decode()), payload)


if __name__ == "__main__":
    unittest.main()
