"""The command-line arguments the examples share.

    pixi run example shadows gpu    # the GPU backend instead of the CPU one

A module beside the examples, not a program: they import it by name, as a
multi-file example imports its own modules.
"""

from std.sys import argv

from create import RenderBackend


def has_argument(name: String) -> Bool:
    """Whether `name` was passed after the program's own path."""
    var arguments = argv()
    for i in range(1, len(arguments)):
        if arguments[i] == name:
            return True
    return False


def backend_argument() -> RenderBackend:
    """The GPU backend when `gpu` was passed, the CPU one otherwise."""
    if has_argument("gpu"):
        return RenderBackend.GPU
    return RenderBackend.CPU
