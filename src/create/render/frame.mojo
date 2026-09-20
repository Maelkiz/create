from std.collections import Optional

from .color import Color
from .align import Align
from .autoscale import AutoScale
from .font import Font
from .viewport import Viewport
from .time import Time
from .camera import Camera
from create.math.geometry import Rectangle, Circle, Line, Triangle
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D
from create.math.matrix import (
    Matrix,
    identity,
    inverse,
    apply as mat_apply,
)
from create.sprite.sprite import Sprite
from create.sprite.animator import SpriteAnimator
from ._backend import Backend, _ImageRequest
from .render_backend import RenderBackend
from ._command import (
    circle_command,
    clear_command,
    letterbox_command,
    line_command,
    rect_command,
    sprite_command,
    text_command,
    triangle_command,
)
from ._style import Style


struct PersistentFrameState(Movable):
    """The part of a `Frame` that outlives the frame it was drawn in.

    A `Frame` is built fresh each frame, so anything it must remember between
    frames — the backend, and through it the loaded fonts, the glyph cache and
    the interned sprite images — is moved out at the end of one frame and into
    the next. The transform stack and the style are deliberately absent: both
    start fresh every frame by construction, so a missing pop or a forgotten
    `outline(enabled=False)` cannot leak into the next frame.

    It also owns what the run loop needs *before* a `Frame` exists. Event
    processing maps pointer positions through `view`, and reads
    `quit_on_escape`, both of which happen before the frame is built; the
    dimension wait reads `view.width`/`height` before the first frame exists at
    all. Those cannot live only on `Frame` for that reason, so the state is the
    authority and each frame takes a view of it.
    """

    var backend: Backend
    var letterbox: Color
    var view: Viewport
    """The authoritative design-to-pixel mapping, re-derived by the loop every
    frame. A `Frame` copies it; `Frame._release` deliberately does not write it
    back, which would undo the loop's own resize handling."""
    var time: Time
    """The frame clock. The loop is its only writer — a `Frame` carries a
    read-only snapshot taken at construction."""
    var autoscale: Int
    var quit_on_escape: Bool
    var autoclear: Bool
    """Whether each frame opens with a clear to `clear_color`."""
    var clear_color: Color
    var _fps_cap: Int
    var _quit: Bool

    def __init__(out self, kind: RenderBackend = RenderBackend.CPU) raises:
        """`kind` picks the backend that will present the frames — a GPU one
        builds its GL resources now, so a context must already be current."""
        self.backend = Backend(kind)
        self.letterbox = Color(0x22)
        self.view = Viewport()
        self.time = Time()
        self.autoscale = AutoScale.OFF
        self.quit_on_escape = True
        self.autoclear = True
        self.clear_color = Color(200)
        self._fps_cap = 0
        self._quit = False

    def _set_viewport(mut self, pixel_w: Int, pixel_h: Int):
        """Remap onto a framebuffer of this size.

        `autoscale` may have been written by the frame that just ended, so it
        is pushed into the viewport before remapping. The reported size and
        scale are then read straight off `view` — there is no second copy to
        keep in sync, which is what the old `Context` spent its `_set_viewport`
        doing.
        """
        self.view.autoscale = self.autoscale
        self.view.set_size(pixel_w, pixel_h)

    def to_screen(self, x: Float64, y: Float64) -> Tuple[Float64, Float64]:
        """Map a window pixel position into screen space.

        Here as well as on `Frame` because the event arms run before the
        frame is built.
        """
        return self.view.to_screen(x, y)


struct TransformGuard[origin: Origin[mut=True]](Movable):
    """Pops the matrix `frame.transform` pushed, on scope exit."""

    var _frame: Pointer[Frame, Self.origin]

    def __init__(out self, ref[Self.origin] frame: Frame):
        self._frame = Pointer(to=frame)

    def __enter__(mut self):
        pass

    def __exit__(mut self):
        self._frame[]._pop_transform()


struct OverlayGuard[origin: Origin[mut=True]](Movable):
    """Restores the camera and transform `frame.overlay` suspended, on scope
    exit."""

    var _frame: Pointer[Frame, Self.origin]
    var _saved_camera: Camera
    var _saved_user: Matrix[3, 3]
    var _saved_user_inv: Matrix[3, 3]
    var _saved_transform: Matrix[3, 3]
    var _saved_transform_inv: Matrix[3, 3]

    def __init__(out self, ref[Self.origin] frame: Frame):
        self._saved_camera = frame._camera.copy()
        self._saved_user = frame._user.copy()
        self._saved_user_inv = frame._user_inv.copy()
        self._saved_transform = frame._transform.copy()
        self._saved_transform_inv = frame._transform_inv.copy()
        frame._camera = Camera()
        frame._user = identity[3]()
        frame._user_inv = identity[3]()
        frame._transform = frame._base.copy()
        frame._transform_inv = frame._base_inv.copy()
        self._frame = Pointer(to=frame)

    def __enter__(mut self):
        pass

    def __exit__(mut self):
        self._frame[]._camera = self._saved_camera.copy()
        self._frame[]._user = self._saved_user
        self._frame[]._user_inv = self._saved_user_inv
        self._frame[]._transform = self._saved_transform
        self._frame[]._transform_inv = self._saved_transform_inv


struct StyleGuard[origin: Origin[mut=True]](Movable):
    """Restores the style the frame had when the scope was entered.

    `Style` is a plain value, so the guard carries its own snapshot and no
    stack is needed — nesting works because each guard restores what it saw.
    """

    var _frame: Pointer[Frame, Self.origin]
    var _saved: Style

    def __init__(out self, ref[Self.origin] frame: Frame):
        self._saved = frame._style.copy()
        self._frame = Pointer(to=frame)

    def __enter__(mut self):
        pass

    def __exit__(mut self):
        self._frame[]._style = self._saved.copy()


struct Frame:
    """One frame: the geometry, the clock, the loop dials and the drawing API.

    This is the single object a program is handed per frame. `width`/`height`
    are the screen extent and `left`/`right`/`bottom`/`top` its edges — use
    those rather than width arithmetic, since the origin is centred and two of
    them are negative. `time` is the frame clock, `scale` the autoscale factor,
    `view` the mapping they all come from. Screen space is camera-independent:
    these and `Input` don't know a `Camera` exists, since a program sets one on
    the frame's transform, not on the geometry it reports.

    Written from both sides, which is why it is a `mut` parameter: the loop
    fills in the geometry and the clock, and the program sets `autoscale` or
    `quit_on_escape`, calls `design_resolution`, `frame_cap` and `quit`, and draws.

    Built fresh each frame and dropped before the frame is presented. State
    that must survive the frame goes in and out through
    `PersistentFrameState`.

    **It takes no parameters, and holds no `Surface`.** It used to need one
    origin parameter for the framebuffer it borrowed, which constrained the
    whole API: a second parameter would have broken every
    `Program.update(self, mut frame: Frame, input: Input)` signature at
    once, and pointing
    an existing `Frame` at a new framebuffer could not compile at all. Both
    limits are gone because a `Frame` no longer touches pixels — it records,
    and the backend replays onto a `Surface` the frame never sees. Don't
    reintroduce a `Surface` field or a parameter to hold one.

    Its extent comes from the `Viewport` rather than from a framebuffer. The
    two can disagree for one frame after a resize, which is harmless here: the
    extent is only used for coordinate arithmetic, and the replay clips against
    the real surface it is handed.

    A draw call touches no pixels: it appends a `DrawCommand` to the backend's
    recording, and the backend replays the whole frame afterwards. So a
    `Frame` is a recorder, and the geometry it records is *local* — the shape
    as the program asked for it, paired with the current transform — never
    device pixels. A style is resolved at record time, so a later `fill()`
    cannot reach back and change what an earlier command paints.

    Every pixel write blends source-over, so a fill, outline, sprite, glyph or
    `background` with `a < 255` composites with what is already there.
    """

    var width: Int
    var height: Int
    var autoscale: Int
    var scale: Float64
    var letterbox: Color
    var view: Viewport
    var time: Time
    """This frame's clock, a snapshot taken at construction.

    A copy rather than a reference because the run loop owns the real one and
    is its only writer — the program reads `delta` and `frame_count` here and
    cannot desynchronise the loop by touching them.
    """
    var quit_on_escape: Bool
    var autoclear: Bool
    """Whether each frame opens with a clear to `clear_color`.

    **Deferred**, like `design_resolution`: this frame's clear is already recorded by the
    time `update` runs, so turning it off takes effect on the next frame. Set
    it in `create` to keep frame one unclear.
    """
    var clear_color: Color
    """What `autoclear` clears to. Persistent, like `letterbox` — set once in
    `create` rather than every frame."""
    var _quit: Bool
    var _fps_cap: Int
    var _state: PersistentFrameState
    # Style is per-frame, not carried in `_state`: `Frame` is only reachable
    # from `render`, so nothing can seed a style outside a frame and carrying
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
    # world to screen. Drawing uses the full product; `to_world`/`to_local`
    # use `_user` alone, so a program never sees the mapping below world space
    # it did not ask for.
    var _user: Matrix[3, 3]
    var _user_inv: Matrix[3, 3]
    var _transform: Matrix[3, 3]
    var _transform_inv: Matrix[3, 3]
    var _transform_stack: List[Matrix[3, 3]]

    def __init__(out self, var state: PersistentFrameState):
        """Adopt the carried-over state and this frame's mapping from it.

        Every dial the program can turn is copied out of the state here and
        written back by `_release`, so a program sets them on the frame it was
        handed and the loop picks them up at the frame boundary.
        """
        self.view = state.view.copy()
        self.width = state.view.width
        self.height = state.view.height
        self.autoscale = state.view.autoscale
        self.scale = state.view.scale
        self.letterbox = state.letterbox
        self.time = state.time.copy()
        self.quit_on_escape = state.quit_on_escape
        self.autoclear = state.autoclear
        self.clear_color = state.clear_color
        self._quit = state._quit
        self._fps_cap = state._fps_cap
        self._state = state^
        self._style = Style()
        self._base = self.view.base_matrix()
        self._base_inv = inverse(self._base)
        self._camera = Camera()
        # The stack starts empty, so the base mapping is the current transform;
        # user transforms compose on top of it.
        self._user = identity[3]()
        self._user_inv = identity[3]()
        self._transform = self._base
        self._transform_inv = self._base_inv
        self._transform_stack = List[Matrix[3, 3]]()
        # Recorded here rather than by the loop so both loops and the
        # never-presented `create` frame get it from one place, and so a
        # program's own `background()` can coalesce with it.
        if self.autoclear:
            self._state.backend.record_clear(clear_command(self.clear_color))

    def _release(deinit self) -> PersistentFrameState:
        """Hand back the state the next frame's `Frame` should start from.

        Consumes the frame, so the borrow on the framebuffer ends here — the
        run loop cannot present while a `Frame` is still alive.

        Writes back exactly the dials the program may have turned. `view` and
        `time` are deliberately *not* among them: `self.view` is this frame's
        mapping, while `_state.view` is the authority the loop re-derives each
        frame, so writing it back would silently undo the loop's own resize
        handling — and the loop is the only writer of the clock.
        """
        var state = self._state^
        state.letterbox = self.letterbox
        state.autoscale = self.autoscale
        state.quit_on_escape = self.quit_on_escape
        state.autoclear = self.autoclear
        state.clear_color = self.clear_color
        state._fps_cap = self._fps_cap
        state._quit = self._quit
        return state^

    def design_resolution(
        mut self, width: Int, height: Int, mode: Int = AutoScale.FIT
    ):
        """Author this program in a fixed world size, scaled to any window.

        Overrides the size passed to `run`, so a program can pin its own
        coordinate space no matter how it is launched — including fullscreen,
        where the window size is the display's rather than the caller's.

        **Deferred**: it writes the persistent viewport and takes effect on the
        next frame, leaving this frame's already-recorded commands and reported
        geometry alone — one frame cannot record under two different mappings.
        From `create` there is no current frame, so it still applies to frame
        one. This is also what `autoscale` has always done, so the two dials
        now agree.
        """
        self._state.view.set_design(width, height)
        self.autoscale = mode

    def to_screen(self, x: Float64, y: Float64) -> Tuple[Float64, Float64]:
        """Map a window pixel position into screen space."""
        return self.view.to_screen(x, y)

    def framerate(self) -> Float64:
        """Current frames per second, derived from the last frame's delta.

        `0.0` on the first frame, where `delta` is still `0.0` and there is
        no prior frame to measure against.
        """
        if self.time.delta == 0.0:
            return 0.0
        return 1.0 / self.time.delta

    def frame_cap(mut self, fps: Int) raises:
        """Limit the loop to at most `fps` frames per second.

        A cap tighter than the display's own pacing (vsync, or the CPU
        backend's always-on vsync) slows the loop by sleeping at the end of
        each frame; a cap looser than it does nothing, since presentation is
        already waiting on the display. Not enforced by `run_headless`,
        which has no wall clock to cap against.
        """
        if fps <= 0:
            raise Error("frame_cap fps must be positive, got " + String(fps))
        self._fps_cap = fps

    def quit(mut self):
        """Ask the run loop to stop after the current frame.

        Unwinds normally, so the window tears down cleanly and program
        destructors run — unlike `std.sys.exit`, which aborts the process.
        """
        self._quit = True

    def left(self) -> Float64:
        """Screen x of the left edge — negative, since the origin is centred."""
        return self.view.left()

    def right(self) -> Float64:
        return self.view.right()

    def bottom(self) -> Float64:
        """Screen y of the bottom edge — negative, since y grows upward."""
        return self.view.bottom()

    def top(self) -> Float64:
        return self.view.top()

    def _draw_letterbox(mut self):
        """Record the window area outside the design bounds.

        Runs after render, so it doubles as the clip for anything drawn past
        the edges of the design area. Nothing to do under `AutoScale.EXTEND`:
        the design covers the whole frame, so there is neither a bar to paint
        nor an out-of-bounds region to clip — and rounding the extended size
        could otherwise leave a one-pixel seam along an edge.

        The one command whose geometry is already in device pixels: it is the
        frame's clip rather than something the program drew, so no transform
        applies to it.
        """
        if not self.view.scaled() or self.autoscale == AutoScale.EXTEND:
            return
        var cx0 = Float64(Int(self.view.offset_x))
        var cy0 = Float64(Int(self.view.offset_y))
        var cx1 = Float64(
            Int(self.view.offset_x + Float64(self.width) * self.scale + 0.5)
        )
        var cy1 = Float64(
            Int(self.view.offset_y + Float64(self.height) * self.scale + 0.5)
        )
        self._state.backend.record(
            letterbox_command(self.letterbox, cx0, cy0, cx1, cy1)
        )

    # `_uniform`, `_pixel_scale`, `_device_bounds` and `_outline_thickness_px`
    # used to live here. They are properties of a matrix, not of a frame, and only
    # the replay needs them now — see `_backend.mojo`.

    def transform(mut self, m: Matrix[3, 3]) -> TransformGuard[origin_of(self)]:
        """Apply `m` to everything drawn inside a `with` block.

        ```mojo
        with frame.transform(translate(50.0, 50.0)):
            frame.rectangle((0, 0), 100, 100)
        ```

        The matrix pops on exit, including on an early return or a raise.
        `_push_transform` is the same push without that guarantee -- a missed
        pop shifts every later draw in the frame, so go through here.
        """
        self._push_transform(m)
        return TransformGuard[origin_of(self)](self)

    def style(mut self) -> StyleGuard[origin_of(self)]:
        """Scope the fill, outline and font settings to a `with` block.

        For helpers that set style before drawing: without this, a callee's
        `outline(enabled=False)` silently applies to whatever the caller
        draws next.
        """
        return StyleGuard[origin_of(self)](self)

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

    def to_world(self, x: Float64, y: Float64) -> Tuple[Float64, Float64]:
        """Map a point from the current transform's frame into world space."""
        return mat_apply(self._user, x, y)

    def to_local(self, x: Float64, y: Float64) -> Tuple[Float64, Float64]:
        """Map a world-space point — a mouse position already converted
        through `Camera.to_world`, say — into the current transform's frame.
        """
        return mat_apply(self._user_inv, x, y)

    def camera(mut self, cam: Camera):
        """Set the active camera. Applies to every draw call and every nested
        `transform()` from here on, until changed again or `frame.overlay()`
        suspends it — and resets to identity next frame, like the rest of the
        transform state.

        ```mojo
        frame.camera(self.cam)
        frame.sprite(self.player.pos, ...)  # world-space coordinates
        with frame.overlay():
            frame.text("Score: " + str(self.score), (0, frame.top() - 20))
        ```
        """
        self._camera = cam.copy()
        self._sync_transform()

    def overlay(mut self) -> OverlayGuard[origin_of(self)]:
        """Suspend the camera and any active transform for a `with` block, so
        what's drawn inside lands in screen space regardless of where the
        camera looks — for a HUD or other UI that must stay put.

        Pops back to whatever camera and transform were active on exit,
        including on an early return or a raise.
        """
        return OverlayGuard[origin_of(self)](self)

    def fill(mut self, color: Optional[Color] = None, enabled: Bool = True):
        """Paint the inside of shapes. `color` left unset keeps the current
        fill color — a plain `fill()` only re-enables it.

        Holds until changed or until the frame ends — every frame starts from
        the `Style` defaults, so nothing set here leaks into the next one.
        """
        if color:
            self._style.fill_color = color.value()
        self._style.fill_enabled = enabled

    def outline(
        mut self,
        color: Optional[Color] = None,
        thickness: Optional[Int] = None,
        enabled: Bool = True,
    ):
        """Outline shapes. `color`/`thickness` left unset keep their current
        values — a plain `outline()` only re-enables it. Worth knowing outline
        is *on* by default, in black, 1 unit thick — a `rectangle` drawn
        without `outline(enabled=False)` gets one nobody asked for.

        Thickness is in world units, scaled by autoscale like every other
        coordinate, and never rendered thinner than one pixel.
        """
        if color:
            self._style.outline_color = color.value()
        if thickness:
            self._style.outline_thickness = thickness.value()
        self._style.outline_enabled = enabled

    def background(mut self, color: Color):
        """Paint the whole framebuffer — the usual first call in `update`.

        A translucent color blends instead of clearing, which is how motion
        trails are drawn: `frame.background(Color(0x11, 0x11, 0x11, 24))`
        fades the previous frame a little further each time. Trails need
        `autoclear = False` set in `create`, or the frame's own clear wipes
        what they were fading.

        An opaque color replaces `autoclear`'s clear rather than stacking on
        it, so opening `update` with this costs one clear, not two. It does
        not change `clear_color`: this paints now, at the point it is called,
        while `clear_color` is what every frame starts from.
        """
        self._state.backend.record_clear(clear_command(color))

    def save_image(
        mut self,
        path: String,
        scale: Float64 = 1.0,
        transparent: Bool = False,
    ) raises:
        """Save this frame as a PNG at the design resolution, times `scale`.

        Window-independent by construction: the size of the file is the space
        the program draws in, never the size of the window, and the letterbox
        bars are absent because they belong to a window this image is not of.
        The same call under either backend produces the same image — the
        capture is rasterised on the CPU from the recorded commands, so the
        GPU path needs no readback. That is what makes this the export to use
        for artwork, posters and golden-image tests; use `save_screenshot` for
        what the user actually saw.

        `transparent` drops the frame's `background`, leaving alpha 0 wherever
        nothing was drawn. `scale` multiplies the output resolution, so
        `scale=2.0` gives a 2x export of the identical layout.

        Deferred, not immediate: the file is written when the frame is
        presented, so it holds the whole frame however early in `render` this
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

    def save_screenshot(mut self, path: String) raises:
        """Save this frame as a PNG at the framebuffer's own resolution.

        The complement of `save_image`: this answers what the user *saw*, so
        it is the size of the drawable, letterbox bars included, drawn by
        whichever rasteriser actually drew the frame. That makes it
        deliberately machine-dependent — window size, HiDPI scaling and any
        driver antialiasing are all in it, and two machines will not produce
        the same file. Right for a bug report or for sharing a running sketch;
        use `save_image` for anything that has to be reproducible.

        Deferred and raising in the same way as `save_image`: the file is
        written when the frame is presented, and a failure raises from there.
        """
        self._state.backend.request_screenshot(path)

    def rectangle(mut self, x: Float64, y: Float64, w: Float64, h: Float64):
        self._state.backend.record(
            rect_command(self._transform, self._style, x, y, w, h)
        )

    def circle(mut self, cx: Float64, cy: Float64, r: Float64):
        self._state.backend.record(
            circle_command(self._transform, self._style, cx, cy, r)
        )

    def line(mut self, x0: Float64, y0: Float64, x1: Float64, y1: Float64):
        # Recorded only when it would draw: an outline-less line is the one
        # shape with nothing left to paint, so the command would be pure
        # overhead.
        if not self._style.outline_enabled:
            return
        self._state.backend.record(
            line_command(self._transform, self._style, x0, y0, x1, y1)
        )

    def triangle(
        mut self,
        x1: Float64,
        y1: Float64,
        x2: Float64,
        y2: Float64,
        x3: Float64,
        y3: Float64,
    ):
        self._state.backend.record(
            triangle_command(
                self._transform, self._style, x1, y1, x2, y2, x3, y3
            )
        )

    def rectangle(mut self, x: Int, y: Int, w: Int, h: Int):
        self.rectangle(Float64(x), Float64(y), Float64(w), Float64(h))

    def circle(mut self, cx: Int, cy: Int, r: Int):
        self.circle(Float64(cx), Float64(cy), Float64(r))

    def line(mut self, x0: Int, y0: Int, x1: Int, y1: Int):
        self.line(Float64(x0), Float64(y0), Float64(x1), Float64(y1))

    def triangle(
        mut self, x1: Int, y1: Int, x2: Int, y2: Int, x3: Int, y3: Int
    ):
        self.triangle(
            Float64(x1),
            Float64(y1),
            Float64(x2),
            Float64(y2),
            Float64(x3),
            Float64(y3),
        )

    def rectangle(mut self, r: Rectangle):
        self.rectangle(r.x, r.y, r.w, r.h)

    def rectangle(mut self, pos: Point2D, w: Float64, h: Float64):
        self.rectangle(pos.x, pos.y, w, h)

    def rectangle(mut self, pos: Point2D, size: Vector2D):
        self.rectangle(pos.x, pos.y, size.x, size.y)

    def circle(mut self, c: Circle):
        self.circle(c.x, c.y, c.r)

    def circle(mut self, pos: Point2D, r: Float64):
        self.circle(pos.x, pos.y, r)

    def circle(mut self, pos: Point2D, r: Int):
        self.circle(pos.x, pos.y, Float64(r))

    def line(mut self, l: Line):
        self.line(l.x0, l.y0, l.x1, l.y1)

    def line(mut self, start: Point2D, end: Point2D):
        self.line(start.x, start.y, end.x, end.y)

    def triangle(mut self, t: Triangle):
        self.triangle(t.x1, t.y1, t.x2, t.y2, t.x3, t.y3)

    def triangle(mut self, a: Point2D, b: Point2D, c: Point2D):
        self.triangle(a.x, a.y, b.x, b.y, c.x, c.y)

    def sprite(mut self, s: Sprite, cx: Int, cy: Int):
        self.sprite(s, Float64(cx), Float64(cy))

    def sprite(mut self, s: Sprite, cx: Float64, cy: Float64):
        """Draw `s` at its own pixel size.

        The same command as the sized overload: at a pixel scale of 1 the two
        agree exactly, and the one-sprite-pixel-per-framebuffer-pixel shortcut
        they used to differ by now lives inside `blit_sprite`, where the replay
        can take it without the record site having to know.
        """
        self.sprite(s, cx, cy, s.width, s.height)

    def sprite(mut self, s: Sprite, pos: Point2D):
        self.sprite(s, pos.x, pos.y)

    def sprite(mut self, s: Sprite, cx: Float64, cy: Float64, w: Int, h: Int):
        # Rotation and shear are not resampled — only position and scale apply.
        #
        # The image is interned *now*, not at replay: the command then carries
        # an id rather than a borrow of the program's pixels, which is what
        # keeps caller-owned memory out of a buffer that outlives the call.
        var image = self._state.backend.intern_image(
            s._id, s.pixels.unsafe_ptr(), s.width, s.height
        )
        self._state.backend.record(
            sprite_command(
                self._transform,
                self._style,
                cx,
                cy,
                Float64(w),
                Float64(h),
                image,
                s.width,
                s.height,
            )
        )

    def sprite(mut self, s: Sprite, cx: Int, cy: Int, w: Int, h: Int):
        self.sprite(s, Float64(cx), Float64(cy), w, h)

    def sprite(mut self, s: Sprite, pos: Point2D, w: Int, h: Int):
        self.sprite(s, pos.x, pos.y, w, h)

    def sprite(mut self, a: SpriteAnimator, cx: Float64, cy: Float64):
        """Draw the animator's current frame, centred at (cx, cy).

        The frame is indexed here rather than handed back by an accessor on
        `SpriteAnimator`: a `List` element's origin is not spellable from user
        code, so a reference to it cannot cross a function boundary. That is
        also why only this overload and the sized one below index it — the
        rest delegate here, so the inline indexing lives in two places rather
        than six.
        """
        self.sprite(a.animation[].frames[a.frame_index], cx, cy)

    def sprite(mut self, a: SpriteAnimator, cx: Int, cy: Int):
        self.sprite(a, Float64(cx), Float64(cy))

    def sprite(mut self, a: SpriteAnimator, pos: Point2D):
        self.sprite(a, pos.x, pos.y)

    def sprite(
        mut self, a: SpriteAnimator, cx: Float64, cy: Float64, w: Int, h: Int
    ):
        self.sprite(a.animation[].frames[a.frame_index], cx, cy, w, h)

    def sprite(mut self, a: SpriteAnimator, cx: Int, cy: Int, w: Int, h: Int):
        self.sprite(a, Float64(cx), Float64(cy), w, h)

    def sprite(mut self, a: SpriteAnimator, pos: Point2D, w: Int, h: Int):
        self.sprite(a, pos.x, pos.y, w, h)

    def corner_radius(mut self, radius: Int):
        """Round the corners of rectangles and triangles, in world units,
        scaled by autoscale like every other coordinate. A radius wider than
        a shape permits is clamped down at draw time so corners never
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
        drawn next. `1.0` (the default) leaves colors untouched; `0.0` draws
        nothing visible. Resolved into the color at record time, like every
        other style setting — it cannot reach back and fade what was already
        drawn."""
        self._style.opacity = value

    def text_align(mut self, align: Align):
        """Anchor the next text at one of the nine points of its box.

        One argument covers both axes: `text_align(Align.CENTER)` centres the
        text on the position, `Align.TOP_LEFT` (the default) hangs it below
        and to the right of it. The one-word constants name an edge's
        midpoint — `Align.TOP` is top-centre. These are edges of the text box,
        not typographic baselines.
        """
        self._style.text_align = align

    def text(mut self, s: String, x: Int, y: Int) raises:
        self.text(s, Float64(x), Float64(y))

    def text(mut self, s: String, pos: Point2D) raises:
        self.text(s, pos.x, pos.y)

    def font(mut self, var f: Font):
        """Swap the face. Lives in `PersistentFrameState`, so unlike the style
        settings a font outlives the frame that set it."""
        self._state.backend.text.set_font(f^)

    def text(mut self, s: String, x: Float64, y: Float64) raises:
        if self._style.text_color.a == 0:
            return
        # Deferred whole. Nothing about the layout is decided here: the
        # advances, the alignment and the baseline all come out of the font,
        # which the backend owns, so they are resolved at replay.
        self._state.backend.record(
            text_command(self._transform, self._style, x, y, s.copy())
        )
