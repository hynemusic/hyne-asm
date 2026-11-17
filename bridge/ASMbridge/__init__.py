"""HYNE ASM bridge: Ableton Live remote script that lists and loads browser items."""


def create_instance(c_instance):
    from .surface import ASMbridge
    return ASMbridge(c_instance)
