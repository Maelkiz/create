"""An image's pixels once the backend owns them.

Its own module rather than a member of `_backend.mojo` because both replay
paths need it and the GL one cannot import the CPU one: `_backend` reaches
`_gl_backend`, so an edge back would close a cycle — the same reason
`_transform.mojo` exists.
"""

from std.memory import ArcPointer


struct _InternedImage(Copyable, Movable):
    """Interned on the first render of an image, so the command
    buffer carries an id rather than a borrow of program-owned memory. The GL
    backend keys its textures by the same id.

    Dropped once no render has used it for `IMAGE_KEEP_FRAMES` frames: a
    program that makes a new image every frame (a snapshot, say) would
    otherwise keep every one of them alive in the cache.
    """

    var pixels: ArcPointer[List[UInt8]]
    """The image's own pixels, shared rather than copied: an image never
    changes, so holding them is as good as a copy."""
    var width: Int
    var height: Int
    var source: Int
    """The `Image._id` this is a copy of."""
    var last_used: Int
    """The frame it was last rendered in, counted by `Backend.frame`."""

    def __init__(
        out self,
        var pixels: ArcPointer[List[UInt8]],
        width: Int,
        height: Int,
        source: Int,
        last_used: Int,
    ):
        self.pixels = pixels^
        self.width = width
        self.height = height
        self.source = source
        self.last_used = last_used


comptime IMAGE_KEEP_FRAMES = 120
"""How many frames an interned image survives without being rendered —
about two seconds at 60 fps. Long enough that an image shown now and then is
not copied and uploaded again each time; short enough that a fresh image per
frame costs a bounded amount of memory."""
