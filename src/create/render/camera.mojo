from create.math.point2d import Point2D
from create.math.matrix import (
    Matrix,
    scale as mat_scale,
    translate as mat_translate,
)


struct Camera(Copyable, Movable):
    """What part of world space maps onto the screen.

    `position` is the world point centred on screen; `zoom` scales around it
    (1.0 = no scaling). A field the program owns and moves on its own
    schedule — like `Sprite` or `Tween` — not something the run loop writes.
    `frame.camera(cam)` applies it to every draw call from that point on;
    the default identity camera behaves exactly like no camera at all.
    """

    var position: Point2D
    var zoom: Float64

    def __init__(
        out self, position: Point2D = Point2D(0.0, 0.0), zoom: Float64 = 1.0
    ):
        self.position = position
        self.zoom = zoom

    def matrix(self) -> Matrix[3, 3]:
        """World-to-screen mapping: scale around `position`, then recentre."""
        return mat_scale(self.zoom, self.zoom) @ mat_translate(
            -self.position.x, -self.position.y
        )

    def to_world(self, screen: Point2D) -> Point2D:
        """A screen-space point — `input.mouse`, say — into world space.

        The inverse of `matrix()`, done in arithmetic rather than through a
        general matrix inverse.
        """
        return Point2D(
            screen.x / self.zoom + self.position.x,
            screen.y / self.zoom + self.position.y,
        )

    def to_screen(self, world: Point2D) -> Point2D:
        """A world-space point into screen space."""
        return Point2D(
            (world.x - self.position.x) * self.zoom,
            (world.y - self.position.y) * self.zoom,
        )
