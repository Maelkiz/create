from create.math import acos, atan2, clamp, pi, sin, sqrt, tan
from std.math import max, min


def rect_corner_radius(radius: Float64, w: Float64, h: Float64) -> Float64:
    """Clamp a requested corner radius so a rectangle's four corners never
    overrun its own width or height."""
    return max(min(radius, min(w / 2.0, h / 2.0)), 0.0)


def _dist(x1: Float64, y1: Float64, x2: Float64, y2: Float64) -> Float64:
    var dx = x2 - x1
    var dy = y2 - y1
    return sqrt(dx * dx + dy * dy)


def _vertex_max_radius(
    vx: Float64,
    vy: Float64,
    prev_x: Float64,
    prev_y: Float64,
    next_x: Float64,
    next_y: Float64,
) -> Float64:
    """The largest fillet radius one vertex can claim without overrunning
    more than half of either adjacent edge.

    This is the conservative bound, not CSS's tighter iterative one: two
    vertices sharing an edge can never together overrun it, so no coupling
    between vertices is needed. It collapses to exactly `min(L1, L2) / 2` at
    a right angle, matching `rect_corner_radius` at 90 degrees.
    """
    var l1 = _dist(vx, vy, prev_x, prev_y)
    var l2 = _dist(vx, vy, next_x, next_y)
    if l1 <= 0.0 or l2 <= 0.0:
        return 0.0
    var ux = (prev_x - vx) / l1
    var uy = (prev_y - vy) / l1
    var wx = (next_x - vx) / l2
    var wy = (next_y - vy) / l2
    var cos_theta = clamp(ux * wx + uy * wy, -1.0, 1.0)
    var theta = clamp(acos(cos_theta), 1e-6, pi - 1e-6)
    return tan(theta / 2.0) * min(l1, l2) / 2.0


def triangle_corner_radius(
    radius: Float64,
    x1: Float64,
    y1: Float64,
    x2: Float64,
    y2: Float64,
    x3: Float64,
    y3: Float64,
) -> Float64:
    """Clamp a requested corner radius so all three of a triangle's corners
    can round without self-intersecting.

    One radius for the whole triangle, not one per corner: the style
    property is a single `Int`, and a uniform fillet is what that reads as.
    The cost is that one thin vertex suppresses rounding on the whole
    triangle — the right failure direction, since no rounding is safer than
    a self-intersecting one. A degenerate (near-collinear) triangle drives
    this to 0 on its own, no separate check needed.
    """
    var r1 = min(radius, _vertex_max_radius(x1, y1, x2, y2, x3, y3))
    var r2 = min(radius, _vertex_max_radius(x2, y2, x3, y3, x1, y1))
    var r3 = min(radius, _vertex_max_radius(x3, y3, x1, y1, x2, y2))
    return max(min(min(r1, r2), r3), 0.0)


def corner_fillet(
    vx: Float64,
    vy: Float64,
    prev_x: Float64,
    prev_y: Float64,
    next_x: Float64,
    next_y: Float64,
    r: Float64,
) -> Tuple[
    Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
]:
    """The fillet circle tangent to both edges at one vertex.

    Returns `(center_x, center_y, tangent_in_x, tangent_in_y, tangent_out_x,
    tangent_out_y, angle_in, angle_out)` — the tangent points sit `r /
    tan(theta/2)` back from the vertex along each edge, the centre sits `r /
    sin(theta/2)` along the interior bisector (the normalised sum of the two
    unit edge vectors leaving the vertex, which points inward for any convex
    corner regardless of winding), and the two angles are `atan2` about that
    centre for whatever arc-rendering code sweeps between them. Used
    unconditionally by both rect corners (theta fixed at pi/2) and triangle
    corners (theta from real geometry) — no shape-specific special-casing.
    """
    var l1 = _dist(vx, vy, prev_x, prev_y)
    var l2 = _dist(vx, vy, next_x, next_y)
    var ux = (prev_x - vx) / l1
    var uy = (prev_y - vy) / l1
    var wx = (next_x - vx) / l2
    var wy = (next_y - vy) / l2
    var cos_theta = clamp(ux * wx + uy * wy, -1.0, 1.0)
    var theta = clamp(acos(cos_theta), 1e-6, pi - 1e-6)
    var half = theta / 2.0
    var tin_x = vx + ux * (r / tan(half))
    var tin_y = vy + uy * (r / tan(half))
    var tout_x = vx + wx * (r / tan(half))
    var tout_y = vy + wy * (r / tan(half))
    var bx = ux + wx
    var by = uy + wy
    var bl = sqrt(bx * bx + by * by)
    var cx = vx + (bx / bl) * (r / sin(half))
    var cy = vy + (by / bl) * (r / sin(half))
    var angle_in = atan2(tin_y - cy, tin_x - cx)
    var angle_out = atan2(tout_y - cy, tout_x - cx)
    return (cx, cy, tin_x, tin_y, tout_x, tout_y, angle_in, angle_out)
