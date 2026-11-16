"""HM Launcher bridge: Ableton Live remote script that lists and loads browser items."""


def create_instance(c_instance):
    from .surface import HMLauncherBridge
    return HMLauncherBridge(c_instance)
