from .actions import ActionError, run_action

# 5: the plugin list skips the presets under plugins and devices (fast with big libraries).
SCRIPT_VERSION = "5"


def _reply(req_id, ok, result=None, error=None):
    return {"id": req_id, "ok": ok, "result": result, "error": error}


def handle_request(req, index, browser, live_version, loader=None, song=None):
    if not isinstance(req, dict) or "cmd" not in req:
        return _reply(req.get("id") if isinstance(req, dict) else None, False, error="bad_request")
    req_id, cmd = req.get("id"), req["cmd"]
    if cmd == "hello":
        result = {"script_version": SCRIPT_VERSION, "live_version": live_version}
        if loader is not None:
            result["capabilities"] = loader.capabilities()
        return _reply(req_id, True, result)
    if cmd == "list":
        return _reply(req_id, True, {"items": index.items(refresh=bool(req.get("refresh")))})
    if cmd == "load":
        return _load(req, req_id, index, browser, loader)
    if cmd == "action":
        if song is None:
            return _reply(req_id, False, error="unknown_cmd")
        try:
            run_action(song, req.get("name"), req.get("value"), req.get("value2"))
        except ActionError as e:
            return _reply(req_id, False, error=str(e))
        except Exception as e:  # Live raises plain RuntimeErrors
            return _reply(req_id, False, error="action_failed: %s" % e)
        return _reply(req_id, True)
    if cmd == "browse":
        children = index.browse(req.get("path") or [])
        if children is None:
            return _reply(req_id, False, error="not_found")
        return _reply(req_id, True, {"children": children})
    return _reply(req_id, False, error="unknown_cmd")


def _load(req, req_id, index, browser, loader):
    """`uri` (one item, the original request) or `uris` (a chain, loaded in order). Every item is looked up first,
    so a chain with a missing item loads nothing."""
    uris = req.get("uris") or ([req.get("uri")] if req.get("uri") else [])
    items = []
    for uri in uris:
        item = index.find(uri)
        if item is None:
            return _reply(req_id, False, error="not_found" if len(uris) == 1 else "not_found: %s" % uri)
        items.append(item)
    if not items:
        return _reply(req_id, False, error="not_found")
    try:
        if loader is not None:
            loader.load(items, position=req.get("position") or "end", all_selected=bool(req.get("all_selected")))
        else:
            for item in items:
                browser.load_item(item)
    except Exception as e:  # Live raises plain RuntimeErrors
        return _reply(req_id, False, error="load_failed: %s" % e)
    return _reply(req_id, True)
