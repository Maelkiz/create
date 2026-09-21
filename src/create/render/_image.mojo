"""A sprite's pixels once the backend owns them.

Its own module rather than a member of `_backend.mojo` because both replay
paths need it and the GL one cannot import the CPU one: `_backend` reaches
`_gl_backend`, so an edge back would close a cycle — the same reason
`_transform.mojo` exists.
"""


struct _Image(Movable):
    """Interned on the first render of a given sprite and kept until the cache
    is dropped, so the command buffer carries an id rather than a borrow of
    program-owned memory. The GL backend keys its textures by the same id.
    """

    var pixels: List[UInt8]
    var width: Int
    var height: Int

    def __init__(out self, var pixels: List[UInt8], width: Int, height: Int):
        self.pixels = pixels^
        self.width = width
        self.height = height
