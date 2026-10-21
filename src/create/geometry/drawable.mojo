"""What can be drawn, and what it can be drawn onto.

A shape knows which kind of shape it is; a canvas knows how to record one.
`Drawable` and `DrawTarget` meet in the middle without either package
naming the other: a shape's `draw_to` calls the target's primitive for its
kind, and `canvas.draw(shape)` is `shape.draw_to(canvas)`. So the geometry
stays free of `render`, and collision code never sees a canvas.

A program's own type can be `Drawable` too, as the shapes it is made of:

```mojo
@fieldwise_init
struct Button(Drawable):
    var body: Rectangle
    var icon: Circle

    def draw_to[T: DrawTarget](self, mut target: T):
        target.draw(self.body)
        target.draw(self.icon)
```

Style is the target's, not the shape's: each part is drawn in whatever
fill, outline and transform the canvas has when `draw` is called.
"""

from .bezier import Bezier
from .geometry import Circle, Line, Polygon, Rectangle, Sector, Triangle


trait Drawable:
    """Something a `DrawTarget` can draw: a shape, a curve, or a program's
    own type made of them."""

    def draw_to[T: DrawTarget](self, mut target: T):
        """Draw this onto `target`, through its `draw` or, for a shape, the
        primitive for its kind."""
        ...


trait Region(Drawable):
    """A drawable with an inside: `Rectangle`, `Circle`, `Triangle`,
    `Sector` and `Polygon`, the region types of `overlaps` and `contains`,
    and what `canvas.clip` takes. A curve has no inside, so it is not one."""

    pass


trait DrawTarget:
    """Somewhere shapes are drawn: `Canvas`. Its primitives, one per kind
    of shape, are the library's own; a program draws through `draw`."""

    def _rectangle(mut self, r: Rectangle):
        ...

    def _circle(mut self, c: Circle):
        ...

    def _triangle(mut self, t: Triangle):
        ...

    def _sector(mut self, s: Sector):
        ...

    def _polygon(mut self, p: Polygon):
        ...

    def _line(mut self, l: Line):
        ...

    def _curves(mut self, curves: List[Bezier]):
        """A chain of Béziers, each starting where the last ends, stroked
        as one: a `Bezier`, an `Arc` or a `Spline`."""
        ...

    def draw[D: Drawable](mut self, shape: D):
        """Draw `shape` in the current style and transform."""
        shape.draw_to(self)
