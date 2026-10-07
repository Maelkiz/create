"""Shared libraries by platform-neutral name.

A leaf module: it imports nothing from `create` and nothing re-exports it.
Every FFI binding (`image`, `text`, `render`, `audio`, `_window`) opens its
library through `load_library`, so the platform's file naming and search
rules are decided in one place.

The name is the file's stem, `libpng16`, and the platform adds its suffix:
`.so` on Linux, `.dylib` on macOS. Both are the unversioned names the
conda-forge packages ship as symlinks to the versioned file.

Where the library is found differs by platform. On Linux an executable's
run path covers `dlopen` as well: `mojo`'s (`$ORIGIN/../lib`) and a `mojo
build` binary's (the environment's `lib`, absolute) both find the pixi
environment's copy from a bare name. macOS applies an executable's
`LC_RPATH` only to `@rpath/` names, so a bare name searches just the default
fallback directories and misses the environment. So:

1. The environment's `lib` directory, from `CONDA_PREFIX` (set by `pixi run`
   and `pixi shell`), on every platform.
2. On macOS, `@rpath/` and the name: a built binary run outside the
   environment, through the run path `mojo build` gave it.
3. The bare name, left to the platform's own search.
"""

from std.ffi import _DLHandle
from std.os import getenv
from std.os.path import exists
from std.sys.info import CompilationTarget


def load_library(stem: String) raises -> _DLHandle:
    """Open the shared library `stem` (`libSDL3`, `libfreetype`, ...).

    Refcounted by the platform loader, so opening one already open is cheap
    and returns the same library.
    """
    var name: String
    comptime if CompilationTarget.is_macos():
        name = stem + ".dylib"
    else:
        name = stem + ".so"
    var prefix = getenv("CONDA_PREFIX")
    if prefix:
        var path = prefix + "/lib/" + name
        if exists(path):
            return _DLHandle(path)
    comptime if CompilationTarget.is_macos():
        try:
            return _DLHandle("@rpath/" + name)
        except:
            pass
    return _DLHandle(name)
