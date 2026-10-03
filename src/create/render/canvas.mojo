from std.collections import Optional
from std.math import floor
from std.utils.numerics import isnan, nan

from create.color.color import Color
from create.color.gradient import Gradient
from .align import Align
from create.color.blend_mode import BlendMode
from .autoscale import AutoScale
from .font import Font
from ._viewport import Viewport
from .camera import Camera
from create.math.bezier import Bezier
from create.math.spline import Spline
from create.math.geometry import (
    Arc,
    Circle,
    Line,
    Rectangle,
    Polygon,
    Sector,
    Triangle,
)
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D
from create.math.matrix import (
    Matrix,
    identity,
    inverse,
    apply as mat_apply,
    scale as mat_scale,
    translate as mat_translate,
)
from create.sprite.sprite import Sprite
from create.sprite.animator import SpriteAnimator
from ._backend import Backend, _ImageRequest
from .render_backend import RenderBackend
from ._command import (
    bezier_chain_command,
    bezier_command,
    circle_command,
    clear_command,
    letterbox_command,
    line_command,
    polygon_command,
    rect_command,
    sector_command,
    sprite_command,
    text_command,
    triangle_command,
)
from .style import Style, _KEEP
from ._clip import clip_style
from ._command import RenderCommand
from ._transform import pixel_scale


comptime _AUTOCLEAR_COLOR = Color(200)


struct PersistentCanvasState(Movable):
    """The part of a `Canvas` that outlives the frame it was rendered in.

    A `Canvas` is built fresh each frame, so anything it must remember between
    frames — the backend, and through it the loaded fonts, the glyph cache and
    the interned sprite images — is moved out at the end of one frame and into
    the next. The transform stack and the style are deliberately absent: both
    start fresh every frame by construction, so a missing pop or a forgotten
    `outline_enabled(False)` cannot leak into the next frame.

    Machinery, not dials. What the *program* sets between frames lives in
    `Context`, which the loop carries beside this and never hands to a
    `Canvas` to own — that is what lets `update` be given both at once.

    It also owns what the run loop needs *before* a `Canvas` exists: event
    processing maps pointer positions through `view`, and the dimension wait
    reads `view.width`/`height` before the first frame exists at all.
    """

    var backend: Backend
    var view: Viewport
    """The authoritative design-to-pixel mapping, re-derived by the loop every
    frame from `Context`. A `Canvas` copies it; `Canvas._release` deliberately
    does not write it back, which would undo the loop's own resize handling."""

    def __init__(out self, kind: RenderBackend = RenderBackend.CPU) raises:
        """`kind` picks the backend that will present the frames — a GPU one
        builds its GL resources now, so a context must already be current."""
        self.backend = Backend(kind)
        self.view = Viewport()

    def _set_viewport(
        mut self,
        autoscale: AutoScale,
        design_w: Int,
        design_h: Int,
        pixel_w: Int,
        pixel_h: Int,
    ):
        """Remap onto a framebuffer of this size.

        The design size and the autoscale mode are pushed in from `Context`
        rather than stored here, so there is one authority for both and a
        dial the last frame turned is picked up at exactly one place — the
        top of the next frame. Plain values rather than the `Context`, which
        lives in `core` above this package.
        """
        self.view.autoscale = autoscale
        self.view.set_design(design_w, design_h)
        self.view.set_size(pixel_w, pixel_h)


struct TransformGuard[origin: Origin[mut=True]](Movable):
    """Pops the matrix `canvas.transform` pushed, on scope exit."""

    var _canvas: Pointer[Canvas, Self.origin]

    def __init__(out self, ref[Self.origin] canvas: Canvas):
        self._canvas = Pointer(to=canvas)

    def __enter__(mut self):
        pass

    def __exit__(mut self):
        self._canvas[]._pop_transform()


struct OverlayGuard[origin: Origin[mut=True]](Movable):
    """Restores the camera and transform `canvas.overlay` suspended, on scope
    exit."""

    var _canvas: Pointer[Canvas, Self.origin]
    var _saved_camera: Camera
    var _saved_user: Matrix[3, 3]
    var _saved_user_inv: Matrix[3, 3]
    var _saved_transform: Matrix[3, 3]
    var _saved_transform_inv: Matrix[3, 3]

    def __init__(out self, ref[Self.origin] canvas: Canvas):
        self._saved_camera = canvas._camera
        self._saved_user = canvas._user
        self._saved_user_inv = canvas._user_inv
        self._saved_transform = canvas._transform
        self._saved_transform_inv = canvas._transform_inv
        canvas._camera = Camera()
        canvas._user = identity[3]()
        canvas._user_inv = identity[3]()
        canvas._transform = canvas._base.copy()
        canvas._transform_inv = canvas._base_inv.copy()
        self._canvas = Pointer(to=canvas)

    def __enter__(mut self):
        pass

    def __exit__(mut self):
        self._canvas[]._camera = self._saved_camera
        self._canvas[]._user = self._saved_user
        self._canvas[]._user_inv = self._saved_user_inv
        self._canvas[]._transform = self._saved_transform
        self._canvas[]._transform_inv = self._saved_transform_inv


struct StyleGuard[origin: Origin[mut=True]](Movable):
    """Restores the style the frame had when the scope was entered.

    `Style` is a plain value, so the guard carries its own snapshot and no
    stack is needed — nesting works because each guard restores what it saw.
    """

    var _canvas: Pointer[Canvas, Self.origin]
    var _saved: Style

    def __init__(out self, ref[Self.origin] canvas: Canvas):
        self._saved = canvas._style
        self._canvas = Pointer(to=canvas)

    def __init__(out self, ref[Self.origin] canvas: Canvas, style: Style):
        """Snapshot, then replace the canvas's style with `style`."""
        self._saved = canvas._style
        canvas._style = style
        self._canvas = Pointer(to=canvas)

    def __enter__(mut self):
        pass

    def __exit__(mut self):
        self._canvas[]._style = self._saved


struct ClipGuard[origin: Origin[mut=True]](Movable):
    """Closes the clip `canvas.clip` opened, on scope exit.

    Holds the clip that was current before it rather than popping a stack, so
    nesting works the way `StyleGuard`'s does.
    """

    var _canvas: Pointer[Canvas, Self.origin]
    var _saved: Int

    def __init__(
        out self,
        ref[Self.origin] canvas: Canvas,
        var region: RenderCommand,
        invert: Bool,
    ):
        self._saved = canvas._state.backend.push_clip(region^, invert)
        self._canvas = Pointer(to=canvas)

    def __enter__(mut self):
        pass

    def __exit__(mut self):
        self._canvas[]._state.backend.clip = self._saved


struct Canvas:
    """One frame: the geometry and the rendering API.

    This is the object a program is handed to render a frame with. `width`/`height`
    are the screen extent and `left`/`right`/`bottom`/`top` its edges — use
    those rather than width arithmetic, since the origin is centred and two of
    them are negative. `scale` is the autoscale factor. Screen space is camera-independent: these don't know a
    `Camera` exists, since a program sets one on the canvas's transform, not on
    the geometry it reports.

    A `mut` parameter because the program renders on it, and the recording it
    appends to is the frame's whole output. What it does *not* carry is a
    setting, the clock or input: everything that outlives a frame is in
    `Context`, handed to `update` beside it. A `Canvas` that carried a dial would be offering to
    change something it is not around to see the effect of.

    Built fresh each frame and dropped before the frame is presented. The
    machinery that must survive the frame goes in and out through
    `PersistentCanvasState`.

    **It takes no parameters, and holds no `Surface`.** It used to need one
    origin parameter for the framebuffer it borrowed, which constrained the
    whole API: a second parameter would have broken every
    `Program.update` signature at once, and pointing an existing `Canvas` at a
    new framebuffer could not compile at all. Both
    limits are gone because a `Canvas` no longer touches pixels — it records,
    and the backend replays onto a `Surface` the canvas never sees. Don't
    reintroduce a `Surface` field or a parameter to hold one.

    Its extent comes from the `Viewport` rather than from a framebuffer. The
    two can disagree for one frame after a resize, which is harmless here: the
    extent is only used for coordinate arithmetic, and the replay clips against
    the real surface it is handed.

    A render call touches no pixels: it appends a `RenderCommand` to the backend's
    recording, and the backend replays the whole frame afterwards. So a
    `Canvas` is a recorder, and the geometry it records is *local* — the shape
    as the program asked for it, paired with the current transform — never
    device pixels. A style is resolved at record time, so a later `fill()`
    cannot reach back and change what an earlier command paints.

    Every pixel write blends source-over, so a fill, outline, sprite, glyph or
    `background` with `a < 255` composites with what is already there —
    unless `blend_mode` picks another way to combine them.
    """

    var width: Int
    var height: Int
    var scale: Float64
    var _view: Viewport
    var _letterbox_color: Color
    """This frame's bar colour, snapshotted from `Context` at construction —
    the frame is rendered under one set of dials, whatever `update` does to them
    for the next."""
    var _autoclear: Bool
    """Whether this frame opened with a clear, so whether a read starts
    from transparent or from the last frame's pixels."""
    var _state: PersistentCanvasState
    # Style is per-frame, not carried in `_state`: `Canvas` is only reachable
    # from `update`, so nothing can seed a style outside a frame and carrying
    # one across would only preserve a forgotten setting.
    var _style: Style
    var _base: Matrix[3, 3]
    var _base_inv: Matrix[3, 3]
    # Camera is per-frame too, and for the same reason as style: it resets to
    # identity every frame, so `render` sets one explicitly each time it wants
    # one rather than it leaking from the last frame that set it.
    var _camera: Camera
    # `_user` is the composition of the matrices the program pushed, mapping
    # local coordinates to world. `_base` maps screen to pixels, `_camera`
    # world to screen. Rendering uses the full product; `to_world`/`to_local`
    # use `_user` alone, so a program never sees the mapping below world space
    # it did not ask for.
    var _user: Matrix[3, 3]
    var _user_inv: Matrix[3, 3]
    var _transform: Matrix[3, 3]
    var _transform_inv: Matrix[3, 3]
    var _transform_stack: List[Matrix[3, 3]]

    def __init__(
        out self,
        var state: PersistentCanvasState,
        *,
        autoclear: Bool,
        letterbox_color: Color,
    ):
        """Adopt the carried-over state, and this frame's mapping and dials.

        The dials are `Context`'s, copied in by value when the frame begins:
        the frame is rendered under them as they stood then, so a program
        turning one mid-frame changes the next frame rather than this one
        halfway through.
        """
        self._view = state.view
        self.width = state.view.width
        self.height = state.view.height
        self.scale = state.view.scale
        self._letterbox_color = letterbox_color
        self._autoclear = autoclear
        self._state = state^
        self._style = Style()
        self._base = self._view.base_matrix()
        self._base_inv = inverse(self._base)
        self._camera = Camera()
        # The stack starts empty, so the base mapping is the current transform;
        # user transforms compose on top of it.
        self._user = identity[3]()
        self._user_inv = identity[3]()
        self._transform = self._base
        self._transform_inv = self._base_inv
        self._transform_stack = List[Matrix[3, 3]]()
        self._state.backend.begin_frame(self._base, self.width, self.height)
        # Recorded here rather than by the loop so both loops get it from one
        # place, and so a program's own `background()` can coalesce with it.
        if autoclear:
            self._state.backend.record_clear(clear_command(_AUTOCLEAR_COLOR))

    def _release(deinit self) -> PersistentCanvasState:
        """Hand back the state the next frame's `Canvas` should start from.

        Consumes the canvas, so the recording is complete before the loop
        presents it — nothing can append to a frame that is being replayed.

        Nothing is written back. `self._view` is this frame's copy of a mapping
        the loop re-derives every frame, and the dials a program turns are in `Context`, which a `Canvas`
        never owned — so there is no merge to get wrong here.
        """
        return self._state^

    def to_screen(self, pixel: Point2D) -> Point2D:
        """Map a window pixel position into screen space."""
        return self._view.to_screen(pixel)

    def left(self) -> Float64:
        """Screen x of the left edge — negative, since the origin is centred."""
        return self._view.left()

    def right(self) -> Float64:
        return self._view.right()

    def bottom(self) -> Float64:
        """Screen y of the bottom edge — negative, since y grows upward."""
        return self._view.bottom()

    def top(self) -> Float64:
        return self._view.top()

    def _render_letterbox(mut self):
        """Record the window area outside the design bounds.

        Runs after render, so it doubles as the clip for anything rendered past
        the edges of the design area. Nothing to do under `AutoScale.EXTEND`:
        the design covers the whole frame, so there is neither a bar to paint
        nor an out-of-bounds region to clip — and rounding the extended size
        could otherwise leave a one-pixel seam along an edge.

        The one command whose geometry is already in device pixels: it is the
        frame's clip rather than something the program drew, so no transform
        applies to it.
        """
        if not self._view.scaled() or self._view.autoscale == AutoScale.EXTEND:
            return
        var cx0 = Float64(Int(self._view.offset_x))
        var cy0 = Float64(Int(self._view.offset_y))
        var cx1 = Float64(
            Int(self._view.offset_x + Float64(self.width) * self.scale + 0.5)
        )
        var cy1 = Float64(
            Int(self._view.offset_y + Float64(self.height) * self.scale + 0.5)
        )
        self._state.backend.record(
            letterbox_command(self._letterbox_color, cx0, cy0, cx1, cy1)
        )

    # `_uniform`, `_pixel_scale`, `_device_bounds` and `_outline_thickness_px`
    # used to live here. They are properties of a matrix, not of a frame, and only
    # the replay needs them now — see `_backend.mojo`.

    def transform(mut self, m: Matrix[3, 3]) -> TransformGuard[origin_of(self)]:
        """Apply `m` to everything rendered inside a `with` block.

        ```mojo
        with canvas.transform(translate(50.0, 50.0)):
            canvas.rectangle((0, 0), 100, 100)
        ```

        The matrix pops on exit, including on an early return or a raise.
        `_push_transform` is the same push without that guarantee -- a missed
        pop shifts every later render in the frame, so go through here.
        """
        self._push_transform(m)
        return TransformGuard[origin_of(self)](self)

    def style(
        mut self,
        *,
        fill: Optional[Color] = None,
        fill_gradient: Optional[Gradient] = None,
        fill_enabled: Optional[Bool] = None,
        outline: Optional[Color] = None,
        outline_thickness: Optional[Int] = None,
        outline_enabled: Optional[Bool] = None,
        corner_radius: Optional[Int] = None,
        text_color: Optional[Color] = None,
        font_size: Optional[Int] = None,
        font_weight: Optional[Int] = None,
        text_align: Optional[Align] = None,
        opacity: Optional[Float64] = None,
        blend_mode: Optional[BlendMode] = None,
        shadow: Optional[Color] = None,
        shadow_offset: Optional[Vector2D] = None,
        shadow_blur: Float64 = _KEEP,
        shadow_spread: Float64 = _KEEP,
        shadow_inset: Optional[Bool] = None,
        shadow_follows_transform: Optional[Bool] = None,
        shadow_enabled: Optional[Bool] = None,
    ) -> StyleGuard[origin_of(self)]:
        """Scope style changes to a `with` block, restoring the previous style
        on exit.

        Each keyword applied goes through the setter of the same name, so it
        behaves exactly like calling that setter; the rest of the style is kept.
        `fill_gradient` goes through `fill`'s `Gradient` overload; given
        beside `fill`, the gradient paints. With no keywords it only scopes: for helpers that set style before
        rendering, where without it a callee's `outline_enabled(False)`
        silently applies to whatever the caller renders next.

        ```mojo
        with canvas.style(fill=Color.RED, outline_enabled=False):
            canvas.circle(position, 10)
        ```
        """
        var guard = StyleGuard[origin_of(self)](self)
        if fill:
            self.fill(fill.value())
        # After the colour, which clears a gradient: given both, the gradient
        # paints and the colour is kept.
        if fill_gradient:
            self.fill(fill_gradient.value())
        if outline or outline_thickness:
            self.outline(outline, outline_thickness)
        # After the colors, which switch fill and outline on: an explicit
        # `*_enabled=False` beside a color wins.
        if fill_enabled:
            self.fill_enabled(fill_enabled.value())
        if outline_enabled:
            self.outline_enabled(outline_enabled.value())
        if corner_radius:
            self.corner_radius(corner_radius.value())
        if text_color:
            self.text_color(text_color.value())
        if font_size:
            self.font_size(font_size.value())
        if font_weight:
            self.font_weight(font_weight.value())
        if text_align:
            self.text_align(text_align.value())
        if opacity:
            self.opacity(opacity.value())
        if blend_mode:
            self.blend_mode(blend_mode.value())
        if (
            shadow
            or shadow_offset
            or not isnan(shadow_blur)
            or not isnan(shadow_spread)
            or shadow_inset
        ):
            self.shadow(
                shadow, shadow_offset, shadow_blur, shadow_spread, shadow_inset
            )
        if shadow_follows_transform:
            self.shadow_follows_transform(shadow_follows_transform.value())
        # After the shadow parts, which switch it on: an explicit
        # `shadow_enabled=False` beside them wins.
        if shadow_enabled:
            self.shadow_enabled(shadow_enabled.value())
        return guard^

    def style(mut self, style: Style) -> StyleGuard[origin_of(self)]:
        """Render with `style` for a `with` block, then restore the previous
        one.

        Replaces the whole style: a field `style` doesn't set is at its
        `Style()` default inside the block, not whatever was set before.
        Applied as soon as this is called, like `transform(m)`, so outside a
        `with` it holds for the rest of the frame.

        ```mojo
        with canvas.style(self.label_style):
            canvas.text("Score", (0, canvas.top() - 20))
        ```
        """
        return StyleGuard[origin_of(self)](self, style)

    def _push_transform(mut self, m: Matrix[3, 3]):
        # Parent first, then child: a point is mapped by the innermost matrix
        # before the ones it nests inside. Composing the other way round would
        # apply the outer transform last, so a nested translate would move in
        # the frame of its own children rather than its parent's.
        self._transform_stack.append(self._user)
        self._user = self._user @ m
        self._sync_transform()

    def _pop_transform(mut self):
        if len(self._transform_stack) > 0:
            self._user = self._transform_stack.pop()
            self._sync_transform()

    def _sync_transform(mut self):
        self._user_inv = inverse(self._user)
        var cam_m = self._camera.matrix()
        self._transform = self._base @ cam_m @ self._user
        self._transform_inv = self._user_inv @ inverse(cam_m) @ self._base_inv

    def to_world(self, local: Point2D) -> Point2D:
        """Map a point from the current transform's frame into world space."""
        var p = mat_apply(self._user, local.x, local.y)
        return Point2D(p[0], p[1])

    def clip(
        mut self, r: Rectangle, invert: Bool = False
    ) -> ClipGuard[origin_of(self)]:
        """Render only inside `r` for a `with` block — or, with `invert`, only
        outside it.

        ```mojo
        with canvas.clip(Rectangle((0, 0), 200, 120)):
            canvas.sprite(self.photo, (0, 0))
        ```

        `r` is placed by the transform and camera current here, and stays
        there for the block: a `transform` or `overlay` inside it moves what
        is rendered, not the clip. A clip inside another keeps only what both
        keep. Every render call is clipped, its shadow and `background()`
        included; the letterbox is not. The clip's edge is the edge a
        `canvas.rectangle(r)` would have.

        Closes on exit, including on an early return or a raise.
        """
        return ClipGuard[origin_of(self)](
            self,
            rect_command(
                self._transform,
                clip_style(),
                r.position.x,
                r.position.y,
                r.w,
                r.h,
            ),
            invert,
        )

    def clip(
        mut self, c: Circle, invert: Bool = False
    ) -> ClipGuard[origin_of(self)]:
        """Render only inside `c` for a `with` block, or only outside it
        with `invert`; see `clip(Rectangle)`."""
        var center = c.center()
        return ClipGuard[origin_of(self)](
            self,
            circle_command(
                self._transform, clip_style(), center.x, center.y, c.r
            ),
            invert,
        )

    def clip(
        mut self, t: Triangle, invert: Bool = False
    ) -> ClipGuard[origin_of(self)]:
        """Render only inside `t` for a `with` block, or only outside it
        with `invert`; see `clip(Rectangle)`."""
        return ClipGuard[origin_of(self)](
            self,
            triangle_command(
                self._transform,
                clip_style(),
                t.a.x,
                t.a.y,
                t.b.x,
                t.b.y,
                t.c.x,
                t.c.y,
            ),
            invert,
        )

    def clip(
        mut self, s: Sector, invert: Bool = False
    ) -> ClipGuard[origin_of(self)]:
        """Render only inside `s` for a `with` block, or only outside it
        with `invert`; see `clip(Rectangle)`."""
        return ClipGuard[origin_of(self)](
            self,
            sector_command(
                self._transform,
                clip_style(),
                s.position.x,
                s.position.y,
                s.r,
                s.start_angle,
                s.sweep_angle,
            ),
            invert,
        )

    def clip(
        mut self, p: Polygon, invert: Bool = False
    ) -> ClipGuard[origin_of(self)]:
        """Render only inside `p` for a `with` block, or only outside it
        with `invert`; see `clip(Rectangle)`. Inside is by the nonzero rule,
        as for `canvas.polygon`."""
        return ClipGuard[origin_of(self)](
            self,
            polygon_command(self._transform, clip_style(), p.vertices.copy()),
            invert,
        )

    def to_local(self, world: Point2D) -> Point2D:
        """Map a world-space point — a mouse position already converted
        through `Camera.to_world`, say — into the current transform's frame.
        """
        var p = mat_apply(self._user_inv, world.x, world.y)
        return Point2D(p[0], p[1])

    def camera(mut self, cam: Camera):
        """Set the active camera. Applies to every render call and every nested
        `transform()` from here on, until changed again or `canvas.overlay()`
        suspends it — and resets to identity next frame, like the rest of the
        transform state.

        ```mojo
        canvas.camera(self.cam)
        canvas.sprite(self.player.position, ...)  # world-space coordinates
        with canvas.overlay():
            canvas.text("Score: " + str(self.score), (0, canvas.top() - 20))
        ```
        """
        self._camera = cam
        self._sync_transform()

    def overlay(mut self) -> OverlayGuard[origin_of(self)]:
        """Suspend the camera and any active transform for a `with` block, so
        what's rendered inside lands in screen space regardless of where the
        camera looks — for a HUD or other UI that must stay put.

        Pops back to whatever camera and transform were active on exit,
        including on an early return or a raise.
        """
        return OverlayGuard[origin_of(self)](self)

    def fill(mut self, color: Optional[Color] = None):
        """Paint the inside of shapes, switching the fill on. A `color`
        replaces any gradient; left unset, the current fill is kept, colour
        or gradient, so `fill()` alone brings back the last fill. The fill is *off* by default, in white, so `fill()` on a fresh
        frame paints shapes white.

        Holds until changed or until the frame ends — every frame starts from
        the `Style` defaults, so nothing set here leaks into the next one.
        """
        if color:
            self._style.fill_color = color.value()
            self._style.fill_gradient = None
        self._style.fill_enabled = True

    def fill(mut self, gradient: Gradient):
        """Paint the inside of shapes with `gradient`, switching the fill on.
        It spans each shape's own bounding box, so it moves and turns with
        the shape; see `Gradient`. Only fills take one: outlines, text and
        shadows keep their colours.

        Holds until a `fill(color)` replaces it or the frame ends. The fill
        color is kept meanwhile, so `fill(color)` alone brings a solid back.
        """
        self._style.fill_gradient = gradient
        self._style.fill_enabled = True

    def outline(
        mut self,
        color: Optional[Color] = None,
        thickness: Optional[Int] = None,
    ):
        """Outline shapes, switching the outline on if `outline_enabled(False)`
        had turned it off. `color`/`thickness` left unset keep their current
        values. Worth knowing outline is *on* by default, in black, 1 unit
        thick — a `rectangle` rendered without `outline_enabled(False)` gets
        one nobody asked for.

        Thickness is in world units, scaled by autoscale like every other
        coordinate, and never rendered thinner than one pixel.
        """
        if color:
            self._style.outline_color = color.value()
        if thickness:
            self._style.outline_thickness = thickness.value()
        self._style.outline_enabled = True

    def fill_enabled(mut self, enabled: Bool):
        """Switch the fill off or back on. The fill color and any gradient
        are kept while off, so `fill_enabled(True)` brings back the same
        fill; `fill(...)` switches it on too."""
        self._style.fill_enabled = enabled

    def outline_enabled(mut self, enabled: Bool):
        """Switch the outline off or back on. Color and thickness are kept
        while off, so `outline_enabled(True)` brings back the same outline;
        `outline(...)` switches it on too."""
        self._style.outline_enabled = enabled

    def background(mut self, color: Color):
        """Paint the whole framebuffer — the usual first call in `update`.

        A translucent color blends instead of clearing, which is how motion
        trails are rendered: `canvas.background(Color(0x11, 0x11, 0x11, 24))`
        fades the previous frame a little further each time. Trails need
        `context.autoclear(False)` set in `create`, or the frame's own clear wipes
        what they were fading.

        An opaque color replaces `context.autoclear`'s clear rather than
        stacking on it, so opening `update` with this costs one clear, not two.
        """
        self._state.backend.record_clear(clear_command(color))

    def background(mut self, gradient: Gradient):
        """Paint the whole framebuffer with `gradient` — a sky, a vignette.

        It spans the screen, `left()` to `right()` and `bottom()` to
        `top()`, whatever the camera is doing; under `EXTEND` that is the
        whole window. Where `FIT` leaves letterbox bars, the bars are painted
        over it as usual.

        Like a colour, it replaces `context.autoclear`'s clear if every stop
        is opaque, and blends over what is there otherwise.
        """
        self._state.backend.record_clear(
            clear_command(
                gradient,
                self._base,
                Float64(self.width),
                Float64(self.height),
            )
        )

    def save_image(
        mut self,
        path: String,
        scale: Float64 = 1.0,
        transparent: Bool = False,
    ) raises:
        """Save this frame as a PNG at the design resolution, times `scale`.

        Window-independent by construction: the size of the file is the space
        the program renders in, never the size of the window, and the letterbox
        bars are absent because they belong to a window this image is not of.
        The same call under either backend produces the same image — the
        capture is rasterised on the CPU from the recorded commands, so the
        GPU path needs no readback. That is what makes this the export to use
        for artwork, posters and golden-image tests; use `save_screenshot` for
        what the user actually saw.

        `transparent` drops the frame's `background`, leaving alpha 0 wherever
        nothing was rendered. `scale` multiplies the output resolution, so
        `scale=2.0` gives a 2x export of the identical layout.

        Deferred, not immediate: the file is written when the frame is
        presented, so it holds the whole frame however early in `update` this
        was called. A failure to write raises there, from `present`, rather
        than here.
        """
        if scale <= 0.0:
            raise Error(
                "save_image needs a positive scale, got " + String(scale)
            )
        var capture = Viewport()
        # The design size, not the window's: under `EXTEND` that is the
        # extended space, which is exactly the area the program drew into.
        capture.autoscale = AutoScale.FIT
        capture.set_design(self.width, self.height)
        var pw = Int(Float64(self.width) * scale + 0.5)
        var ph = Int(Float64(self.height) * scale + 0.5)
        capture.set_size(pw, ph)
        self._state.backend.request_image(
            _ImageRequest(
                path,
                pw,
                ph,
                capture.scale,
                # Commands carry the *window's* mapping baked in; undoing it
                # and applying the capture's is a pure similarity, so one
                # matrix in front of the replay is the whole rebase.
                capture.base_matrix() @ self._base_inv,
                transparent,
            )
        )

    def pixel(mut self, position: Point2D) raises -> Color:
        """The colour at `position` in what this frame has drawn so far.

        `position` is in screen space, whatever the camera or transform —
        a read is of the screen, not the scene — so
        `canvas.pixel(context.input.mouse)` picks under the mouse as it is.
        Outside the screen it is `Color.TRANSPARENT`.

        Reads what is drawn *so far*: a render call after this one does not
        change what it returned. The pixels are those `save_image` would
        write at scale 1, on either backend, without the letterbox. Reading
        replays the frame on the CPU once, and again only after something
        more is drawn, so many reads in a row cost one replay.

        With `context.autoclear(False)`, a read starts from the last frame's
        pixels, as the frame did — from the second frame that reads on; the
        first sees only what it drew itself. That needs the CPU backend,
        which is also the only one that accumulates.
        """
        var x = Int(floor(position.x + Float64(self.width) / 2.0))
        var y = Int(floor(Float64(self.height) / 2.0 - position.y))
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return Color.TRANSPARENT
        self._state.backend.read_frame(seeded=not self._autoclear)
        return self._state.backend.frame_read.value().pixel(x, y)

    def snapshot(mut self, scale: Float64 = 1.0) raises -> Sprite:
        """What this frame has drawn so far, as a `Sprite` of the whole
        screen: `width * scale` by `height * scale` pixels.

        Drawn back with `canvas.sprite(shot, (0, 0), canvas.width,
        canvas.height)` it lines up with the frame exactly — a feedback
        effect is a snapshot kept as a field and drawn under the next frame.
        `scale=canvas.scale` gives the window's own resolution instead.
        Everything `pixel` says about what is read applies.
        """
        return self.snapshot(
            Rectangle(
                Point2D(0.0, 0.0), Float64(self.width), Float64(self.height)
            ),
            scale,
        )

    def snapshot(
        mut self, region: Rectangle, scale: Float64 = 1.0
    ) raises -> Sprite:
        """What this frame has drawn so far inside `region`, as a `Sprite`
        of `region.w * scale` by `region.h * scale` pixels.

        `region` is in screen space, like `pixel`'s position, so it is always
        upright; outside the screen the sprite is transparent.
        """
        if scale <= 0.0:
            raise Error("snapshot needs a positive scale, got " + String(scale))
        var pw = Int(region.w * scale + 0.5)
        var ph = Int(region.h * scale + 0.5)
        if pw <= 0 or ph <= 0:
            raise Error(
                "snapshot needs a region of at least one pixel, got "
                + String(region)
            )
        ref backend = self._state.backend
        if (
            scale == 1.0
            and pw == self.width
            and ph == self.height
            and region.position == Point2D(0.0, 0.0)
        ):
            # The whole screen at design resolution is what `pixel` reads,
            # so the two share one replay.
            backend.read_frame(seeded=not self._autoclear)
            return Sprite.from_rgba(pw, ph, backend.frame_read.value().data)
        var to_target = mat_translate(
            (region.w / 2.0 - region.position.x) * scale,
            (region.h / 2.0 + region.position.y) * scale,
        ) @ mat_scale(scale, -scale)
        var mem = backend.read(pw, ph, scale, to_target, not self._autoclear)
        return Sprite.from_rgba(pw, ph, mem.data)

    def save_screenshot(mut self, path: String) raises:
        """Save this frame as a PNG at the framebuffer's own resolution.

        The complement of `save_image`: this answers what the user *saw*, so
        it is the size of the drawable, letterbox bars included, rendered by
        whichever rasteriser actually drew the frame. That makes it
        deliberately machine-dependent — window size, HiDPI scaling and any
        driver antialiasing are all in it, and two machines will not produce
        the same file. Right for a bug report or for sharing a running sketch;
        use `save_image` for anything that has to be reproducible.

        Deferred and raising in the same way as `save_image`: the file is
        written when the frame is presented, and a failure raises from there.
        """
        self._state.backend.request_screenshot(path)

    def rectangle(mut self, position: Point2D, w: Float64, h: Float64):
        self._state.backend.record(
            rect_command(
                self._transform, self._style, position.x, position.y, w, h
            )
        )

    def rectangle(mut self, position: Point2D, w: Int, h: Int):
        self.rectangle(position, Float64(w), Float64(h))

    def rectangle(mut self, r: Rectangle):
        self.rectangle(r.position, r.w, r.h)

    def circle(mut self, position: Point2D, r: Float64):
        self._state.backend.record(
            circle_command(
                self._transform, self._style, position.x, position.y, r
            )
        )

    def circle(mut self, position: Point2D, r: Int):
        self.circle(position, Float64(r))

    def circle(mut self, c: Circle):
        self.circle(c.center(), c.r)

    def sector(
        mut self,
        position: Point2D,
        r: Float64,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        """Draw the pie slice of the circle around `position` with radius
        `r`, from `start_angle` round by `sweep_angle`: a `Sector`, its tip at
        `position`.

        Angles are radians, counter-clockwise from the +x axis (y is up); a
        negative sweep runs clockwise, and a full turn or more is the whole
        disc. The outline is inset, as a circle's is: the fill stops where it
        starts, and a translucent sector composites once. `corner_radius` does
        not round a sector, and it casts no inset shadow; a blurred drop
        shadow costs what a `bezier`'s does. A zero radius or sweep draws
        nothing.
        """
        self._state.backend.record(
            sector_command(
                self._transform,
                self._style,
                position.x,
                position.y,
                r,
                start_angle,
                sweep_angle,
            )
        )

    def sector(
        mut self,
        position: Point2D,
        r: Int,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        self.sector(position, Float64(r), start_angle, sweep_angle)

    def sector(mut self, s: Sector):
        self.sector(s.position, s.r, s.start_angle, s.sweep_angle)

    def polygon(mut self, p: Polygon):
        """Draw the polygon through `p.vertices`, closed back to the first.

        Filled by the nonzero rule, so a self-crossing polygon fills every
        area its edges wind round, whichever way they run. The outline is
        inset along the outside, as a sector's is, and centred on an edge
        running through the inside — a pentagram's inner pentagon — so every
        edge is stroked as thick; a translucent polygon composites once.
        `corner_radius` does not round a polygon, and it casts no inset
        shadow; a blurred drop shadow costs what a `bezier`'s does. Fewer than
        three vertices draw nothing.
        """
        self._state.backend.record(
            polygon_command(self._transform, self._style, p.vertices.copy())
        )

    def polygon(mut self, *vertices: Point2D):
        var points = List[Point2D](capacity=len(vertices))
        for v in vertices:
            points.append(v)
        self._state.backend.record(
            polygon_command(self._transform, self._style, points^)
        )

    def line(mut self, start: Point2D, end: Point2D):
        # Recorded only when it would render: an outline-less line is the one
        # shape with nothing left to paint, so the command would be pure
        # overhead.
        if not self._style.outline_enabled:
            return
        self._state.backend.record(
            line_command(
                self._transform, self._style, start.x, start.y, end.x, end.y
            )
        )

    def line(mut self, l: Line):
        self.line(l.start, l.end)

    def bezier(
        mut self,
        start: Point2D,
        control1: Point2D,
        control2: Point2D,
        end: Point2D,
    ):
        """Stroke the cubic Bézier from `start` to `end`, shaped by the two
        controls, in the outline colour and thickness.

        A curve, like a line, has no interior: `fill` never applies, and with
        the outline off nothing is drawn. The curve is flattened at replay,
        in device pixels, so it stays smooth under any camera zoom; its ends
        are butt, like a line's, unless `end` is `start`: then the curve
        closes on a mitred joint. Joints are mitred, so a translucent stroke
        composites once, except at a sharp cusp, where it may overlap slightly.

        A blurred shadow is blurred afresh every frame (it cannot be cached
        like a sprite's), and on the GPU costs one extra draw call.
        """
        self.bezier(Bezier(start, control1, control2, end))

    def bezier(mut self, b: Bezier):
        # Recorded only when it would render, as `line` is.
        if not self._style.outline_enabled:
            return
        self._state.backend.record(
            bezier_command(self._transform, self._style, b)
        )

    def spline(
        mut self,
        var points: List[Point2D],
        alpha: Float64 = 0.5,
        closed: Bool = False,
    ):
        """Stroke a smooth curve through every one of `points`, in order, in
        the outline colour and thickness: a `Spline`, which is Catmull-Rom.

        `alpha` sets how the spacing of the points shapes the curve: 0 can
        loop or cusp where points bunch up, 0.5 (centripetal) never does,
        1 hugs the points more loosely still. With `closed`, the curve runs
        on from the last point back to the first, and that joint is mitred
        like the rest.

        Drawn as one stroke, like `bezier`: no fill, nothing with the outline
        off, butt ends when open, and a translucent stroke composites once. A
        blurred shadow costs what a `bezier`'s does. Fewer than two distinct
        points draw nothing.
        """
        self.spline(Spline(points^, alpha, closed))

    def spline(mut self, spline: Spline):
        if not self._style.outline_enabled:
            return
        # Converted here, in local space: the knot spacing is measured where
        # the points were given, so a non-uniform scale can't reshape it.
        self._bezier_chain(spline.beziers())

    def arc(
        mut self,
        position: Point2D,
        r: Float64,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        """Stroke the arc of the circle around `position` with radius `r`,
        from `start_angle` round by `sweep_angle`, in the outline colour and
        thickness: an `Arc`.

        Angles are radians, counter-clockwise from the +x axis (y is up); a
        negative sweep runs clockwise, and a full turn or more is the whole
        circle, closed on a mitred joint.

        Drawn as one stroke, like `bezier`: no fill, nothing with the outline
        off, butt ends when open, and a translucent stroke composites once. A
        blurred shadow costs what a `bezier`'s does. A zero radius or sweep
        draws nothing.
        """
        self.arc(Arc(position, r, start_angle, sweep_angle))

    def arc(
        mut self,
        position: Point2D,
        r: Int,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        self.arc(position, Float64(r), start_angle, sweep_angle)

    def arc(mut self, a: Arc):
        if not self._style.outline_enabled:
            return
        # Converted here, in local space: the transform maps Béziers
        # exactly, so a non-uniform scale draws the arc of an ellipse.
        self._bezier_chain(a.beziers())

    def _bezier_chain(mut self, curves: List[Bezier]):
        """Record `curves`, each starting where the last ends, as one
        stroke. Nothing is recorded for no curves."""
        if len(curves) == 0:
            return
        var points = List[Point2D](capacity=3 * len(curves) + 1)
        points.append(curves[0].start)
        for c in curves:
            points.append(c.control1)
            points.append(c.control2)
            points.append(c.end)
        self._state.backend.record(
            bezier_chain_command(self._transform, self._style, points^)
        )

    def triangle(mut self, a: Point2D, b: Point2D, c: Point2D):
        self._state.backend.record(
            triangle_command(
                self._transform, self._style, a.x, a.y, b.x, b.y, c.x, c.y
            )
        )

    def triangle(mut self, t: Triangle):
        self.triangle(t.a, t.b, t.c)

    def sprite(mut self, s: Sprite, position: Point2D):
        """Render `s` at its own pixel size.

        The same command as the sized overload: at a pixel scale of 1 the two
        agree exactly, and the one-sprite-pixel-per-framebuffer-pixel shortcut
        they used to differ by now lives inside `blit_sprite`, where the replay
        can take it without the record site having to know.
        """
        self.sprite(s, position, s.width, s.height)

    def sprite(mut self, s: Sprite, position: Point2D, w: Int, h: Int):
        # Rotation and shear are not resampled — only position and scale apply.
        #
        # The image is interned *now*, not at replay: the command then carries
        # an id rather than a borrow of the program's pixels, which is what
        # keeps caller-owned memory out of a buffer that outlives the call.
        var image = self._state.backend.intern_image(
            s._id, s._version, s._pixels.unsafe_ptr(), s.width, s.height
        )
        self._state.backend.record(
            sprite_command(
                self._transform,
                self._style,
                position.x,
                position.y,
                Float64(w),
                Float64(h),
                image,
                s.width,
                s.height,
            )
        )

    def sprite(mut self, a: SpriteAnimator, position: Point2D):
        """Render the animator's current frame, centred at `position`.

        The frame is indexed here rather than handed back by an accessor on
        `SpriteAnimator`: a `List` element's origin is not spellable from user
        code, so a reference to it cannot cross a function boundary. That is
        also why the sized overload below indexes it inline too.
        """
        self.sprite(a.animation[].frames[a.frame_index], position)

    def sprite(mut self, a: SpriteAnimator, position: Point2D, w: Int, h: Int):
        self.sprite(a.animation[].frames[a.frame_index], position, w, h)

    def corner_radius(mut self, radius: Int):
        """Round the corners of rectangles and triangles, in world units,
        scaled by autoscale like every other coordinate. A radius wider than
        a shape permits is clamped down at render time so corners never
        self-intersect."""
        self._style.corner_radius = radius

    def text_color(mut self, color: Color):
        """Paint glyphs in `color`. Separate from `fill`, so a shape colour and
        a label colour do not have to be set in turn; a fully transparent one
        skips the text entirely."""
        self._style.text_color = color

    def font_size(mut self, size: Int):
        """Text height in world units, scaled by autoscale like a coordinate."""
        self._style.font_size = size

    def font_weight(mut self, weight: Int):
        """Stroke weight of the face, named by `FontWeight`. The packaged Noto
        faces are variable, so this interpolates rather than swapping files."""
        self._style.font_weight = weight

    def opacity(mut self, value: Float64):
        """Multiply the alpha of fill, outline and text color for whatever is
        rendered next. `1.0` (the default) leaves colors untouched; `0.0` renders
        nothing visible. Resolved into the color at record time, like every
        other style setting — it cannot reach back and fade what was already
        rendered."""
        self._style.opacity = value

    def blend_mode(mut self, mode: BlendMode):
        """Combine whatever is rendered next with what is already there by
        `mode` — `BlendMode.ADD` for glows, `MULTIPLY` for shadows — instead
        of painting over it. `BlendMode.NORMAL` (the default) paints over.

        Applies to shapes, text and sprites, never to `background`.
        """
        self._style.blend_mode = mode

    def shadow(
        mut self,
        color: Optional[Color] = None,
        offset: Optional[Vector2D] = None,
        blur: Float64 = _KEEP,
        spread: Float64 = _KEEP,
        inset: Optional[Bool] = None,
    ):
        """Cast a shadow behind what is rendered next, switching shadows on.
        Parts left unset keep their current values, so `shadow()` alone
        brings back the last shadow, and `shadow(blur=12)` changes only the
        blur; a fresh frame starts at a translucent black, an offset of
        `(4, -4)` (down and right, since y is up), a blur of 8 and no spread.

        Works like CSS `drop-shadow`: the shadow is the shape's whole
        silhouette, fill and outline together, cast once — a translucent
        fill shows its own shadow through it. Lines cast their stroke, text
        its glyphs and sprites their alpha. `blur` is the CSS blur radius,
        twice the Gaussian's standard deviation; `spread` grows the
        silhouette before blurring. Both are world units, scaled like a
        coordinate.

        `inset=True` paints the shadow inside the shape instead, over its
        fill and within its outline, as if the shape were a hole cut in a
        surface: the band shows on the side the offset points away from.
        Only rectangles, circles and triangles take an inset shadow; lines,
        text and sprites cast none while it is set.

        The offset is fixed to the screen, so a rotated shape's shadow still
        falls the same way; see `shadow_follows_transform`. The shadow
        combines with what is beneath it by the style's `blend_mode`, like
        the shape itself.

        ```mojo
        canvas.shadow(Color(0, 0, 0, 96), offset=Vector2D(6, -6), blur=12)
        canvas.rectangle((0, 0), 120, 80)
        ```
        """
        if color:
            self._style.shadow_color = color.value()
        if offset:
            self._style.shadow_offset = offset.value()
        if not isnan(blur):
            self._style.shadow_blur = blur
        if not isnan(spread):
            self._style.shadow_spread = spread
        if inset:
            self._style.shadow_inset = inset.value()
        self._style.shadow_enabled = True

    def shadow_enabled(mut self, enabled: Bool):
        """Switch shadows off or back on. Colour, offset, blur, spread and
        inset are kept while off, so `shadow_enabled(True)` brings back the
        same shadow; `shadow(color)` switches it on too. Off by default."""
        self._style.shadow_enabled = enabled

    def shadow_follows_transform(mut self, follows: Bool):
        """Whether the shadow's offset turns with the transform.

        `False` (the default) keeps it fixed to the screen, as a light
        overhead would: a rotating shape's shadow always falls the same way.
        Camera zoom and autoscale still scale it, so it stays in proportion.
        `True` applies the offset in the shape's own frame, before the
        transform, so it rotates and shears with the shape, as a CSS
        shadow does under a CSS transform.
        """
        self._style.shadow_follows_transform = follows

    def text_align(mut self, align: Align):
        """Anchor the next text at one of the nine points of its box.

        One argument covers both axes: `Align.CENTER` (the default) centres
        the text on the position, like every other shape, and
        `Align.TOP_LEFT` hangs it below and to the right of it. The one-word constants name an edge's
        midpoint — `Align.TOP` is top-centre. These are edges of the text box,
        not typographic baselines.
        """
        self._style.text_align = align

    def font(mut self, var f: Font):
        """Swap the face. Lives in `PersistentCanvasState`, so unlike the style
        settings a font outlives the frame that set it."""
        self._state.backend.text.set_font(f^)

    def text_width(mut self, s: String) raises -> Float64:
        """How wide `text(s, ...)` would render under the current font, size
        and weight, in the units the next render call is positioned in.

        Exact for any prefix too, since glyphs sit advance to advance with no
        kerning, so a caret after a string's first few characters goes at the
        text's left edge plus the width of those characters. With the default
        `Align.CENTER`, that left edge is `position.x - text_width(s) / 2`.

        Raises only if the default font has to be loaded and cannot be.
        """
        var scale = pixel_scale(self._transform, self.scale)
        var pixels = self._state.backend.text.width(s, self._style, scale)
        return Float64(pixels) / scale

    def text(mut self, s: String, position: Point2D):
        if self._style.text_color.a == 0:
            return
        # Deferred whole. Nothing about the layout is decided here: the
        # advances, the alignment and the baseline all come out of the font,
        # which the backend owns, so they are resolved at replay.
        self._state.backend.record(
            text_command(
                self._transform, self._style, position.x, position.y, s.copy()
            )
        )
