from std.reflection import call_location


@always_inline
def source_path(relative: String) -> String:
    """`relative`, resolved against the directory of the calling source file.

    `Sprite.load(source_path("../assets/sprite.png"))` finds the asset from
    wherever the program is run, where a bare relative path resolves against
    the CWD. Called from a helper, it resolves against the helper's file —
    the same rule as Python's `__file__`.

    The caller's path is baked in at compile time, which is why this has to be
    inlined: `call_location` reports the site it is inlined into. So `mojo run`
    and `mojo build` agree on the answer, and it is spelled the way the
    compiler was handed the file — a binary built from a relative path finds
    its assets only when run from the directory it was built in.
    """
    var file = String(call_location().file_name())
    return String(file[byte = : file.rfind("/") + 1]) + relative
