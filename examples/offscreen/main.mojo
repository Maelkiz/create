"""Drawing offscreen: a `Canvas(width, height)` of the program's own, read
back as an `Image` with `snapshot`.

Two uses. A badge drawn once in `create` and kept as an image, stamped
where the mouse is. And a paint layer kept as a field: drag to paint into
it, and the strokes stay while the frame under them is redrawn every frame.
Press `c` to clear the layer.
"""

from create import *


comptime _BADGE_SIZE = 80


def _badge() raises -> Image:
    """A badge drawn offscreen, at twice the design density so it stays
    crisp on a window scaled up to 2x."""
    var badge = Canvas(_BADGE_SIZE, _BADGE_SIZE, scale=2.0)
    badge.shadow(blur=6)
    badge.fill(Gradient.radial(Color(236, 196, 202), Color(170, 90, 104)))
    badge.outline(Color(90, 40, 50), thickness=3)
    badge.circle((0, 0), 32)
    badge.shadow_enabled(False)
    badge.text_color(Color(60, 20, 30))
    badge.font_size(28)
    badge.text("1st", (0, 0))
    return badge.snapshot(scale=badge.scale())


@fieldwise_init
struct Offscreen(Program):
    var badge: Image
    var layer: Canvas
    """The paint layer: the size of the design, transparent but for the
    strokes painted into it."""
    var strokes: Image
    """The layer as last read, redrawn every frame."""
    var last_mouse: Point2D

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Offscreen:
        var layer = Canvas(canvas.width(), canvas.height())
        var strokes = layer.snapshot()
        return Offscreen(_badge(), layer^, strokes^, Point2D(0, 0))

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        ref input = context.input
        if input.key_pressed(Key.C):
            self.layer.clear()
            self.strokes = self.layer.snapshot()
        if input.mouse_down():
            # From where the mouse was, so a fast drag paints a line, not dots.
            var start = (
                input.mouse if input.mouse_pressed() else self.last_mouse
            )
            with self.layer.style(
                outline=Color(98, 104, 168).lerp(
                    Color(201, 140, 150),
                    0.5 + 0.5 * sin(context.time.elapsed * 2.0),
                ),
                outline_thickness=12,
            ):
                self.layer.line(start, input.mouse)
                self.layer.circle(input.mouse, 6)
            # Read only when something was painted: a read copies the layer.
            self.strokes = self.layer.snapshot()
        self.last_mouse = input.mouse

        # The frame under the layer, redrawn and cleared every frame.
        canvas.background(Color(40, 40, 44))
        var t = context.time.elapsed
        with canvas.style(fill=Color(62, 62, 68), outline_enabled=False):
            canvas.circle((cos(t) * 200, sin(t * 1.3) * 120), 40)

        canvas.image(self.strokes, (0, 0), canvas.width(), canvas.height())
        canvas.image(self.badge, input.mouse, _BADGE_SIZE, _BADGE_SIZE)

        with canvas.style(text_color=Color(176, 172, 162), font_size=18):
            canvas.text("Drag to paint, C to clear", (0, canvas.bottom() + 30))


def main() raises:
    run[Offscreen](
        "Offscreen",
        width=800,
        height=600,
        backend=RenderBackend.from_arguments(),
    )
