from std.math import (
    acos,
    atan2,
    ceil,
    clamp,
    cos,
    max,
    min,
    pi,
    sin,
    sqrt,
    tan,
    tau,
)

from create.math import Point2D


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

    One radius for the whole triangle, not one per corner: the requested
    radius is a single value, and a uniform fillet is what that reads as.
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


def rounded_vertices(
    vertices: List[Point2D], radius: Float64, max_step: Float64
) -> List[Point2D]:
    """The closed outline through `vertices` with every corner rounded by
    `radius`, its fillets flattened into points at most `max_step` radians
    apart.

    Each corner is clamped on its own (`_vertex_max_radius`), so a sharp
    tip rounds less without holding back the rest. A concave corner rounds
    too: its fillet sits in the notch and fills it, since the circle tangent
    to both edges lies on the side the edges open towards either way. A
    corner with no room to round, a zero-length edge beside it or none at
    all, stays the vertex it was.
    """
    var n = len(vertices)
    if radius <= 0.0 or n < 3:
        return vertices.copy()
    var out = List[Point2D](capacity=n * 4)
    for i in range(n):
        var v = vertices[i]
        var before = vertices[(i + n - 1) % n]
        var after = vertices[(i + 1) % n]
        var r = min(
            radius,
            _vertex_max_radius(v.x, v.y, before.x, before.y, after.x, after.y),
        )
        if r <= 0.0:
            out.append(v)
            continue
        _append_corner(out, v, before, after, r, max_step)
    return out^


def _append_corner(
    mut out: List[Point2D],
    v: Point2D,
    before: Point2D,
    after: Point2D,
    r: Float64,
    max_step: Float64,
):
    """The fillet of radius `r` at the corner `v` between the lines to
    `before` and `after`, from the first's side to the second's; `v` itself
    where the lines run straight on."""
    var f = corner_fillet(v.x, v.y, before.x, before.y, after.x, after.y, r)
    # The arc facing the vertex, the shorter way round.
    var sweep = _shorter(f[7] - f[6])
    if abs(sweep) < 1e-9:
        out.append(v)
        return
    _append_arc(out, Point2D(f[0], f[1]), r, f[6], sweep, max_step)


def _shorter(sweep: Float64) -> Float64:
    """`sweep` the shorter way round, in `[-pi, pi]`."""
    if sweep > pi:
        return sweep - tau
    if sweep < -pi:
        return sweep + tau
    return sweep


def _append_arc(
    mut out: List[Point2D],
    center: Point2D,
    r: Float64,
    start: Float64,
    sweep: Float64,
    max_step: Float64,
):
    """Points along the arc about `center`, both ends included, at most
    `max_step` radians apart."""
    var steps = max(Int(ceil(abs(sweep) / max_step)), 1)
    for k in range(steps + 1):
        var a = start + sweep * Float64(k) / Float64(steps)
        out.append(Point2D(center.x + r * cos(a), center.y + r * sin(a)))


def sector_corner_radii(
    r: Float64, sweep: Float64, radius: Float64
) -> Tuple[Float64, Float64]:
    """How far a sector of radius `r` and signed `sweep` can round its tip
    and each end of its arc for a requested `radius`, as `(tip, ends)`.

    Each corner claims at most half of what lies beside it, as a polygon's
    does: the tip half of each radius, an end the other half and half the
    arc. A tip running straight on (a half turn) or a whole disc has no
    corner to round.
    """
    var turn = abs(sweep)
    if radius <= 0.0 or r <= 0.0 or turn >= tau or turn == 0.0:
        return (0.0, 0.0)
    # The narrower wedge between the two radii.
    var wedge = min(turn, tau - turn)
    var tip = 0.0
    if abs(wedge - pi) > 1e-9:
        tip = min(radius, tan(wedge / 2.0) * r / 2.0)
    # An end's fillet touches its radius sqrt(r^2 - 2 r f) out from the tip,
    # at least halfway for f <= 3r/8, and the arc atan(f / that) round from
    # the end, at most half the sweep.
    var ends = min(radius, 3.0 * r / 8.0)
    var half = turn / 2.0
    if half < pi / 2.0:
        var t2 = tan(half) * tan(half)
        ends = min(ends, r * (sqrt(t2 * t2 + t2) - t2))
    return (max(tip, 0.0), max(ends, 0.0))


def rounded_sector_vertices(
    position: Point2D,
    r: Float64,
    start: Float64,
    sweep: Float64,
    radius: Float64,
    fillet_step: Float64,
    arc_step: Float64,
) -> List[Point2D]:
    """The outline of the sector at `position` with radius `r`, from
    `start` round by `sweep`, its tip and both ends of its arc rounded by
    `radius` (clamped by `sector_corner_radii`): the fillets at most
    `fillet_step` radians between points, the arc at most `arc_step`.

    The ends' fillets are tangent to their radius and, from inside, to the
    sector's circle. The tip's is a polygon corner's, so past a half turn,
    where the tip is concave, it fills the notch.
    """
    var radii = sector_corner_radii(r, sweep, radius)
    var tip_r = radii[0]
    var end_r = radii[1]
    var side = 1.0 if sweep > 0.0 else -1.0
    var u0 = (cos(start), sin(start))
    var end_angle = start + sweep
    var u1 = (cos(end_angle), sin(end_angle))
    var out = List[Point2D]()
    # The tip, from the end radius round to the start one.
    var on_end = Point2D(position.x + r * u1[0], position.y + r * u1[1])
    var on_start = Point2D(position.x + r * u0[0], position.y + r * u0[1])
    if tip_r > 0.0:
        _append_corner(out, position, on_end, on_start, tip_r, fillet_step)
    else:
        out.append(position)
    # Out along the start radius, round the arc, back down the end radius.
    var along = sqrt(max(r * r - 2.0 * r * end_r, 0.0))
    var offset = atan2(end_r, along) if end_r > 0.0 else 0.0
    if end_r > 0.0:
        # Into the sector: the start radius turned towards the sweep.
        var c = Point2D(
            position.x + along * u0[0] - side * end_r * u0[1],
            position.y + along * u0[1] + side * end_r * u0[0],
        )
        var on_line = atan2(
            position.y + along * u0[1] - c.y, position.x + along * u0[0] - c.x
        )
        var on_arc = start + side * offset
        _append_arc(
            out, c, end_r, on_line, _shorter(on_arc - on_line), fillet_step
        )
    _append_arc(
        out,
        position,
        r,
        start + side * offset,
        sweep - 2.0 * side * offset,
        arc_step,
    )
    if end_r > 0.0:
        var c = Point2D(
            position.x + along * u1[0] + side * end_r * u1[1],
            position.y + along * u1[1] - side * end_r * u1[0],
        )
        var on_arc = end_angle - side * offset
        var on_line = atan2(
            position.y + along * u1[1] - c.y, position.x + along * u1[0] - c.x
        )
        _append_arc(
            out, c, end_r, on_arc, _shorter(on_line - on_arc), fillet_step
        )
    return out^
