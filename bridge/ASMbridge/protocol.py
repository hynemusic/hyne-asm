SCRIPT_VERSION = "3"


def _reply(req_id, ok, result=None, error=None):
    return {"id": req_id, "ok": ok, "result": result, "error": error}


def handle_request(req, index, browser, live_version):
    if not isinstance(req, dict) or "cmd" not in req:
        return _reply(req.get("id") if isinstance(req, dict) else None, False, error="bad_request")
    req_id, cmd = req.get("id"), req["cmd"]
    if cmd == "hello":
        return _reply(req_id, True, {"script_version": SCRIPT_VERSION, "live_version": live_version})
    if cmd == "list":
        return _reply(req_id, True, {"items": index.items(refresh=bool(req.get("refresh")))})
    if cmd == "load":
        item = index.find(req.get("uri"))
        if item is None:
            return _reply(req_id, False, error="not_found")
        try:
            browser.load_item(item)
        except Exception as e:  # Live raises plain RuntimeErrors
            return _reply(req_id, False, error="load_failed: %s" % e)
        return _reply(req_id, True)
    if cmd == "browse":
        children = index.browse(req.get("path") or [])
        if children is None:
            return _reply(req_id, False, error="not_found")
        return _reply(req_id, True, {"children": children})
    return _reply(req_id, False, error="unknown_cmd")
