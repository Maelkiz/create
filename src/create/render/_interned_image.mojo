"""An image's pixels once the backend owns them.

Its own module rather than a member of `_backend.mojo` because both replay
paths need it and the GL one cannot import the CPU one: `_backend` reaches
`_gl_backend`, so an edge back would close a cycle — the same reason
`_transform.mojo` exists.
"""


struct _InternedImage(Copyable, Movable):
    """Interned on the first render of a given image version, so the command
    buffer carries an id rather than a borrow of program-owned memory. The GL
    backend keys its textures by the same id.

    Dropped once no render has used it for `IMAGE_KEEP_FRAMES` frames: a
    program that makes a new image every frame (a snapshot, say) would
    otherwise keep every one of them alive in the cache.
    """

    var pixels: List[UInt8]
    var width: Int
    var height: Int
    var source: Int
    """The `Image._id` this is a copy of."""
    var version: Int
    """The `Image._version` it was copied at."""
    var last_used: Int
    """The frame it was last rendered in, counted by `Backend.frame`."""

    def __init__(
        out self,
        var pixels: List[UInt8],
        width: Int,
        height: Int,
        source: Int,
        version: Int,
        last_used: Int,
    ):
        self.pixels = pixels^
        self.width = width
        self.height = height
        self.source = source
        self.version = version
        self.last_used = last_used


comptime IMAGE_KEEP_FRAMES = 120
"""How many frames an interned image survives without being rendered —
about two seconds at 60 fps. Long enough that an image shown now and then is
not copied and uploaded again each time; short enough that a fresh image per
frame costs a bounded amount of memory."""
