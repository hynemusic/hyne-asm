import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fake_live import FakeBrowser, FakeItem  # noqa: E402
from ASMbridge.browser_index import BrowserIndex  # noqa: E402
from ASMbridge.protocol import handle_request  # noqa: E402


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.browser = FakeBrowser(audio_effects=[
            FakeItem("EQ Eight", "u:eq"), FakeItem("Boom", "boom")])
        self.index = BrowserIndex(self.browser)

    def call(self, req):
        return handle_request(req, self.index, self.browser, "12.4.16")

    def test_hello_reports_versions(self):
        r = self.call({"id": 1, "cmd": "hello"})
        self.assertEqual(r, {"id": 1, "ok": True, "error": None,
                             "result": {"script_version": "2", "live_version": "12.4.16"}})

    def test_list_returns_items(self):
        r = self.call({"id": 2, "cmd": "list"})
        self.assertTrue(r["ok"])
        self.assertEqual([i["name"] for i in r["result"]["items"]], ["EQ Eight", "Boom"])

    def test_load_calls_load_item_with_matching_item(self):
        r = self.call({"id": 3, "cmd": "load", "uri": "u:eq"})
        self.assertEqual(r, {"id": 3, "ok": True, "result": None, "error": None})
        self.assertEqual([i.uri for i in self.browser.loaded], ["u:eq"])

    def test_load_unknown_uri_returns_not_found(self):
        r = self.call({"id": 4, "cmd": "load", "uri": "u:nope"})
        self.assertEqual((r["ok"], r["error"]), (False, "not_found"))

    def test_load_exception_returns_load_failed(self):
        r = self.call({"id": 5, "cmd": "load", "uri": "boom"})
        self.assertFalse(r["ok"])
        self.assertTrue(r["error"].startswith("load_failed: "))

    def test_unknown_cmd(self):
        r = self.call({"id": 6, "cmd": "dance"})
        self.assertEqual((r["id"], r["ok"], r["error"]), (6, False, "unknown_cmd"))

    def test_bad_request_without_cmd(self):
        r = self.call("not a dict")
        self.assertEqual((r["id"], r["ok"], r["error"]), (None, False, "bad_request"))


if __name__ == "__main__":
    unittest.main()
