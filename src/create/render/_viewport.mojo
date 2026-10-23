from std.math import min
from create.math.matrix import (
    Matrix,
    scale as mat_scale,
    translate as mat_translate,
)
from create.math.point2d import Point2D
from .autoscale import AutoScale


struct Viewport(Copyable, ImplicitlyCopyable, Movable):
    """The design-space mapping: how world coordinates land on the framebuffer.

    One home for the geometry `Canvas` reports and renders through, so the two
    cannot drift. Owns no window and no pixels — it is pure arithmetic over a
    framebuffer size, which is what makes it unit-testable on its own.
    """

    var width: Float64
    var height: Float64
    var autoscale: AutoScale
    var scale: Float64
    var pixel_w: Int
    var pixel_h: Int
    var offset_x: Float64
    var offset_y: Float64
    var _design_w: Float64
    var _design_h: Float64

    def __init__(out self):
        self.width = 0.0
        self.height = 0.0
        self.autoscale = AutoScale.OFF
        self.scale = 1.0
        self.pixel_w = 0
        self.pixel_h = 0
        self.offset_x = 0.0
        self.offset_y = 0.0
        self._design_w = 0.0
        self._design_h = 0.0

    def set_design(mut self, width: Float64, height: Float64):
        """Set the design size, the space the program is authored in.

        Stores only — the caller recomputes the mapping with `set_size`, so a
        design change and a resize go through the same path.
        """
        self._design_w = width
        self._design_h = height

    def set_size(mut self, pixel_w: Int, pixel_h: Int):
        """Recompute the design-space mapping for a framebuffer of this size.

        With autoscale on, the program keeps the size it was authored
        in and the content is scaled to fit inside the window — so a
        sketch built for 1280x720 looks the same on any screen. Both modes
        derive the same uniform factor and differ only in what happens to the
        window area the design does not cover: `FIT` centres the design and
        leaves letterbox bars, `EXTEND` anchors it at the origin and grows the
        design size to fill the frame, so the leftover becomes extra world.
        """
        self.pixel_w = pixel_w
        self.pixel_h = pixel_h
        if (
            self.autoscale != AutoScale.OFF
            and self._design_w > 1.0
            and self._design_h > 1.0
        ):
            self.scale = min(
                Float64(pixel_w) / self._design_w,
                Float64(pixel_h) / self._design_h,
            )
            if self.autoscale == AutoScale.EXTEND:
                # The axis that constrained the scale divides back out to its
                # design size; the other one gains the slack as world space.
                # Not rounded: the extent is the window's, which a whole
                # number of units would miss by up to half of one.
                self.width = Float64(pixel_w) / self.scale
                self.height = Float64(pixel_h) / self.scale
                self.offset_x = 0.0
                self.offset_y = 0.0
            else:
                self.width = self._design_w
                self.height = self._design_h
                self.offset_x = (
                    Float64(pixel_w) - self._design_w * self.scale
                ) / 2.0
                self.offset_y = (
                    Float64(pixel_h) - self._design_h * self.scale
                ) / 2.0
        else:
            self.width = Float64(pixel_w)
            self.height = Float64(pixel_h)
            self.scale = 1.0
            self.offset_x = 0.0
            self.offset_y = 0.0

    def scaled(self) -> Bool:
        """Whether the design maps onto the framebuffer as anything but 1:1."""
        return self.scale != 1.0 or self.offset_x != 0.0 or self.offset_y != 0.0

    def left(self) -> Float64:
        """Screen x of the left edge — negative, since the origin is centred."""
        return -self.width / 2.0

    def right(self) -> Float64:
        return self.width / 2.0

    def bottom(self) -> Float64:
        """Screen y of the bottom edge — negative, since y grows upward."""
        return -self.height / 2.0

    def top(self) -> Float64:
        return self.height / 2.0

    def base_matrix(self) -> Matrix[3, 3]:
        """The screen-to-pixel mapping: origin centred, y up.

        Anchoring on the framebuffer centre covers all three autoscale modes
        at once — `offset_x + scale * width / 2` equals `pixel_w / 2` for
        `OFF`, `FIT` and `EXTEND` alike.

        Screen space, not world space: this knows nothing of `Camera`, which
        sits between the two and is `Canvas`'s concern, not `Viewport`'s.
        """
        return mat_translate(
            Float64(self.pixel_w) / 2.0, Float64(self.pixel_h) / 2.0
        ) @ mat_scale(self.scale, -self.scale)

    def pixel_to_screen(self, pixel: Point2D) -> Point2D:
        """Map a window pixel position into screen space.

        The inverse of `base_matrix`, done in arithmetic: pointer positions
        reach the program in the same space
        `canvas.left`/`right`/`bottom`/`top` describe. Camera-independent, like
        the rest of `Viewport` — a program using a `Camera` converts on top
        with `Camera.to_world`.
        """
        return Point2D(
            (pixel.x - Float64(self.pixel_w) / 2.0) / self.scale,
            (Float64(self.pixel_h) / 2.0 - pixel.y) / self.scale,
        )
