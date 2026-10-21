"""Where an image command lands on the device, for both backends.

An image under a transform that keeps it upright — no rotation, shear or
mirroring, the plain mapping and any scale of it — is an axis-aligned device
rect, blitted directly (`blit_image`). Any other transform turns the rect into
a parallelogram, which the CPU replay fills pixel by pixel through the inverse
mapping (`blit_image_mapped`) and the GL backend draws as one quad through its
four mapped corners. Both decisions are made here, so the two backends agree
on which path an image takes and where it lands.
"""

from std.math import ceil, floor, max, min

from create.math.matrix import Matrix, apply as mat_apply, inverse
from create.math.point2d import Point2D


def upright(m: Matrix[3, 3]) -> Bool:
    """True when `m` maps an image onto an upright, unmirrored device rect:
    an axis-aligned scale (y flipped, as device rows run down) plus a
    translation. The scale may differ between the axes."""
    return (
        m[0, 1] == 0.0
        and m[1, 0] == 0.0
        and m[2, 0] == 0.0
        and m[2, 1] == 0.0
        and m[2, 2] == 1.0
        and m[0, 0] > 0.0
        and m[1, 1] < 0.0
    )


@fieldwise_init
struct UprightRect(Copyable, ImplicitlyCopyable, Movable):
    """An upright image's device rect, in whole pixels."""

    var x: Int
    var y: Int
    var width: Int
    var height: Int


def upright_rect(
    m: Matrix[3, 3], cx: Float64, cy: Float64, w: Float64, h: Float64
) -> UprightRect:
    """The device rect of the image centred at `(cx, cy)`, `w` by `h` local
    units, under an `upright` `m`: at least a pixel each way, centred on the
    mapped anchor truncated to a pixel."""
    var p = mat_apply(m, cx, cy)
    var dw = max(Int(w * m[0, 0] + 0.5), 1)
    var dh = max(Int(h * -m[1, 1] + 0.5), 1)
    return UprightRect(Int(p[0]) - dw // 2, Int(p[1]) - dh // 2, dw, dh)


def image_corners(
    m: Matrix[3, 3], cx: Float64, cy: Float64, w: Float64, h: Float64
) -> List[Point2D]:
    """The device corners of the image centred at `(cx, cy)`, `w` by `h`
    local units: top-left, top-right, bottom-right, bottom-left of the image
    as it is stored, so row 0 is the edge at local `cy + h / 2`."""
    var x0 = cx - w / 2.0
    var x1 = cx + w / 2.0
    var top = cy + h / 2.0
    var bottom = cy - h / 2.0
    var out = List[Point2D](capacity=4)
    for corner in [(x0, top), (x1, top), (x1, bottom), (x0, bottom)]:
        var p = mat_apply(m, corner[0], corner[1])
        out.append(Point2D(p[0], p[1]))
    return out^


@fieldwise_init
struct ImageMapping(Copyable, ImplicitlyCopyable, Movable):
    """An image placed by any transform: the device pixels it may cover and
    the texel each one samples.

    The texel coordinate of the pixel centre `(px, py)` is
    `(u + u_dx * px + u_dy * py, v + v_dx * px + v_dy * py)`, in source
    pixels; the pixel takes a texel only when that lies inside the image.
    """

    var x0: Int
    """Device bounds, half-open: columns `[x0, x1)`, rows `[y0, y1)`."""
    var y0: Int
    var x1: Int
    var y1: Int
    var u: Float64
    var u_dx: Float64
    var u_dy: Float64
    var v: Float64
    var v_dx: Float64
    var v_dy: Float64

    @staticmethod
    def empty() -> Self:
        """A mapping that covers no pixels."""
        return Self(0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

    def translated(self, dx: Int, dy: Int) -> Self:
        """The same mapping onto a device moved by `(dx, dy)` pixels."""
        var fx = Float64(dx)
        var fy = Float64(dy)
        return Self(
            self.x0 + dx,
            self.y0 + dy,
            self.x1 + dx,
            self.y1 + dy,
            self.u - self.u_dx * fx - self.u_dy * fy,
            self.u_dx,
            self.u_dy,
            self.v - self.v_dx * fx - self.v_dy * fy,
            self.v_dx,
            self.v_dy,
        )


def image_mapping(
    m: Matrix[3, 3],
    cx: Float64,
    cy: Float64,
    w: Float64,
    h: Float64,
    source_width: Int,
    source_height: Int,
) -> ImageMapping:
    """The `source_width` x `source_height` image centred at `(cx, cy)`,
    `w` by `h` local units, mapped onto the device by `m`. A zero extent or
    a singular `m` covers nothing."""
    if w <= 0.0 or h <= 0.0 or m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0] == 0.0:
        return ImageMapping.empty()
    var corners = image_corners(m, cx, cy, w, h)
    var lo = corners[0]
    var hi = corners[0]
    for p in corners:
        lo = Point2D(min(lo.x, p.x), min(lo.y, p.y))
        hi = Point2D(max(hi.x, p.x), max(hi.y, p.y))
    # Device to local, then local to texels: `u` runs right from the left
    # edge, `v` down from the top one.
    var i = inverse(m)
    var su = Float64(source_width) / w
    var sv = Float64(source_height) / h
    return ImageMapping(
        Int(floor(lo.x)),
        Int(floor(lo.y)),
        Int(ceil(hi.x)),
        Int(ceil(hi.y)),
        (i[0, 2] - cx + w / 2.0) * su,
        i[0, 0] * su,
        i[0, 1] * su,
        (cy + h / 2.0 - i[1, 2]) * sv,
        -i[1, 0] * sv,
        -i[1, 1] * sv,
    )


def mask_mapping(
    a: Matrix[3, 3], x: Int, y: Int, width: Int, height: Int
) -> ImageMapping:
    """A `width` x `height` mask placed at `(x, y)` in a space that `a` maps
    onto the device, texel `(tx, ty)` covering `[x + tx, x + tx + 1)` by
    `[y + ty, y + ty + 1)` there, as a laid-out glyph is. The bounds reach a
    pixel past the mapped corners, for a bilinear sample's spill. A singular
    `a` covers nothing."""
    if a[0, 0] * a[1, 1] - a[0, 1] * a[1, 0] == 0.0:
        return ImageMapping.empty()
    var x0 = Float64(x)
    var y0 = Float64(y)
    var x1 = Float64(x + width)
    var y1 = Float64(y + height)
    var p = mat_apply(a, x0, y0)
    var lo = Point2D(p[0], p[1])
    var hi = lo
    for corner in [(x1, y0), (x1, y1), (x0, y1)]:
        var q = mat_apply(a, corner[0], corner[1])
        lo = Point2D(min(lo.x, q[0]), min(lo.y, q[1]))
        hi = Point2D(max(hi.x, q[0]), max(hi.y, q[1]))
    var i = inverse(a)
    return ImageMapping(
        Int(floor(lo.x)) - 1,
        Int(floor(lo.y)) - 1,
        Int(ceil(hi.x)) + 1,
        Int(ceil(hi.y)) + 1,
        i[0, 2] - x0,
        i[0, 0],
        i[0, 1],
        i[1, 2] - y0,
        i[1, 0],
        i[1, 1],
    )
