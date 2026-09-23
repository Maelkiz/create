"""The platform layer: native windows, the event loop and the two
rendering surfaces, over SDL3.

Internal, like `_bytes` — the root preamble does not import it, since no
program opens a window itself; `run` does. `core` is its only consumer, and
`render` never imports it (see `_gl.mojo`), so the rendering stack stays
usable with no window at all.

`Window` presents a CPU-side RGBA8 buffer; `GLWindow` owns a current OpenGL
3.3 Core context and binds no GL itself. Every SDL event is translated into
a typed `Event` before it leaves this package, and nothing SDL-specific
crosses into a signature outside `_sdl.mojo`.
"""

from .window import Window
from .gl_window import GLWindow
from .event import (
    Event,
    Quit,
    Resized,
    KeyDown,
    KeyUp,
    MouseMoved,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,
)
