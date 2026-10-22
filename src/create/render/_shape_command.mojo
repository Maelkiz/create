"""A shape as the command that records it, for the canvas and its clips.

`shape_command` has one overload per kind of shape: the command a render
call records for it, in `style`, mapped by `transform`. Rounded polygons and
sectors are flattened here, as finely as a circle of their radius is drawn at
that transform and `scale`, so every replay sees a plain polygon. `Canvas`'s
`DrawTarget` primitives record these, and `RegionCapture` takes the one a
`clip` region draws as, so a clip and a fill of the same shape are the same
command but for its style.
"""

from std.math import max
from create.math import TAU

from create.geometry.bezier import Bezier
from create.geometry.drawable import DrawTarget
from create.geometry.geometry import (
    Circle,
    Line,
    Polygon,
    Rectangle,
    Sector,
    Triangle,
)
from create.geometry._fillet import (
    rounded_sector_vertices,
    rounded_vertices,
    sector_corner_radii,
)
from create.math.matrix import Matrix
from create.math.point2d import Point2D

from ._clip import clip_style
from ._command import (
    RenderCommand,
    bezier_chain_command,
    circle_command,
    line_command,
    polygon_command,
    rect_command,
    rounded_sector_command,
    sector_command,
    triangle_command,
)
from .style import Style
from ._tessellate import circle_segments
from ._transform import pixel_scale


def shape_command(
    r: Rectangle, transform: Matrix[3, 3], style: Style, scale: Float64
) -> RenderCommand:
    return rect_command(
        transform,
        style,
        r.position.x,
        r.position.y,
        r.w,
        r.h,
        r.corner_radius,
    )


def shape_command(
    c: Circle, transform: Matrix[3, 3], style: Style, scale: Float64
) -> RenderCommand:
    return circle_command(transform, style, c.position.x, c.position.y, c.r)


def shape_command(
    t: Triangle, transform: Matrix[3, 3], style: Style, scale: Float64
) -> RenderCommand:
    return triangle_command(
        transform,
        style,
        t.a.x,
        t.a.y,
        t.b.x,
        t.b.y,
        t.c.x,
        t.c.y,
        t.corner_radius,
    )


def shape_command(
    s: Sector, transform: Matrix[3, 3], style: Style, scale: Float64
) -> RenderCommand:
    """Rounded, the polygon through the sector's outline, its curves
    flattened as finely as circles of their radii are drawn; sharp, a
    sector's own."""
    var radii = sector_corner_radii(s.r, s.sweep_angle, s.corner_radius)
    if radii[0] <= 0.0 and radii[1] <= 0.0:
        return sector_command(
            transform,
            style,
            s.position.x,
            s.position.y,
            s.r,
            s.start_angle,
            s.sweep_angle,
        )
    var sf = pixel_scale(transform, scale)
    var fillet = max(radii[0], radii[1])
    return rounded_sector_command(
        transform,
        style,
        rounded_sector_vertices(
            s.position,
            s.r,
            s.start_angle,
            s.sweep_angle,
            s.corner_radius,
            TAU / Float64(circle_segments(fillet * sf)),
            TAU / Float64(circle_segments(s.r * sf)),
        ),
        s.position.x,
        s.position.y,
        s.r,
    )


def shape_command(
    p: Polygon, transform: Matrix[3, 3], style: Style, scale: Float64
) -> RenderCommand:
    """The polygon through `p.vertices`, every corner rounded by
    `p.corner_radius` with its fillets flattened now, in local space."""
    if p.corner_radius <= 0.0:
        return polygon_command(transform, style, p.vertices.copy())
    var radius_px = p.corner_radius * pixel_scale(transform, scale)
    var step = TAU / Float64(circle_segments(radius_px))
    return polygon_command(
        transform, style, rounded_vertices(p.vertices, p.corner_radius, step)
    )


def shape_command(
    l: Line, transform: Matrix[3, 3], style: Style, scale: Float64
) -> RenderCommand:
    return line_command(
        transform, style, l.start.x, l.start.y, l.end.x, l.end.y
    )


def curves_command(
    curves: List[Bezier], transform: Matrix[3, 3], style: Style
) -> RenderCommand:
    """`curves`, each starting where the last ends, as one stroke. At least
    one curve."""
    var points = List[Point2D](capacity=3 * len(curves) + 1)
    points.append(curves[0].start)
    for c in curves:
        points.append(c.control1)
        points.append(c.control2)
        points.append(c.end)
    return bezier_chain_command(transform, style, points^)


struct RegionCapture(DrawTarget):
    """A `DrawTarget` that keeps the command a region draws as, in
    `clip_style()`, instead of recording it: how `canvas.clip` turns any
    `Region` into its clip's command. A region draws as exactly one shape;
    a curve never reaches it, since a curve is not a `Region`."""

    var transform: Matrix[3, 3]
    var scale: Float64
    var command: Optional[RenderCommand]

    def __init__(out self, transform: Matrix[3, 3], scale: Float64):
        self.transform = transform
        self.scale = scale
        self.command = None

    def _rectangle(mut self, r: Rectangle):
        self.command = shape_command(
            r, self.transform, clip_style(), self.scale
        )

    def _circle(mut self, c: Circle):
        self.command = shape_command(
            c, self.transform, clip_style(), self.scale
        )

    def _triangle(mut self, t: Triangle):
        self.command = shape_command(
            t, self.transform, clip_style(), self.scale
        )

    def _sector(mut self, s: Sector):
        self.command = shape_command(
            s, self.transform, clip_style(), self.scale
        )

    def _polygon(mut self, p: Polygon):
        self.command = shape_command(
            p, self.transform, clip_style(), self.scale
        )

    def _line(mut self, l: Line):
        pass

    def _curves(mut self, curves: List[Bezier]):
        pass
