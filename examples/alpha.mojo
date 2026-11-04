"""Translucency, three ways.

On the left, three circles whose colours are half transparent mix where
they cross: alpha belongs to each colour. On the right, a card of fill,
outline, text and image fades in and out by one `opacity`, which reaches
every part of a render call at once. And a translucent background, drawn
over the last frame instead of clearing it, leaves the orbiting dot a
fading trail.
"""

from create import *

comptime _BACKGROUND = Color(18, 18, 24)
comptime _PANEL = Color(30, 32, 42)
comptime _TEXT = Color(200, 200, 212)
comptime _HINT = Color(150, 160, 180)
comptime _CARD = Point2D(200.0, 20.0)


@fieldwise_init
struct App(Program):
    var logo: Image

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        # The trails below are rendered by fading the *previous* frame, so the
        # per-frame clear has to be off — it would wipe what they fade.
        canvas.autoclear(False)
        # With no clear, the first frame is painted the colour the trails
        # fade towards, once.
        canvas.background(_BACKGROUND)
        return App(
            Image.load(source_path("../assets/logo/png/logo-cutout.png"))
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var t = context.time.elapsed

        # A translucent background fades the previous frame instead of
        # clearing it, leaving motion trails.
        canvas.background(_BACKGROUND.with_alpha(24))

        canvas.outline_enabled(False)

        # Each demonstration sits on an opaque panel, redrawn every frame:
        # without the clear, anything translucent drawn straight onto the
        # last frame would pile up on itself until it was solid.
        canvas.fill(_PANEL)
        canvas.rectangle((-185.0, 20.0), 300.0, 240.0, corner_radius=16)
        canvas.rectangle(_CARD, 300.0, 240.0, corner_radius=16)

        # Overlapping translucent colours mix where they cross.
        canvas.fill(Color(255, 0, 0, 128))
        canvas.circle((-225.0, -5.0), 60.0)
        canvas.fill(Color(0, 255, 0, 128))
        canvas.circle((-145.0, -5.0), 60.0)
        canvas.fill(Color(0, 0, 255, 128))
        canvas.circle((-185.0, 65.0), 60.0)

        # One value fades fill, outline, text and image alike. Each shape
        # still composites once, so the outline never shows through the fill.
        var opacity = 0.5 + 0.5 * sin(t * 1.5)
        with canvas.style(opacity=opacity):
            with canvas.style(
                fill=Color(235, 120, 70),
                outline=Color.WHITE,
                outline_thickness=6,
            ):
                canvas.rectangle(_CARD, 220.0, 170.0, corner_radius=18)
            canvas.image(self.logo, _CARD + Vector2D(0, 20), 100, 100)
            with canvas.style(text_color=Color.WHITE, font_size=22):
                canvas.text(
                    String("opacity ", round(opacity, 2)),
                    _CARD - Vector2D(0, 55),
                )

        # An orbiting dot renders the trail the faded background preserves.
        canvas.fill(Color.ORANGE)
        canvas.circle((330 * cos(t * 0.8), 230 * sin(t * 0.8)), 14.0)

        with canvas.style(text_color=_HINT, font_size=18):
            canvas.text("alpha: each colour its own", (-185.0, -120.0))
            canvas.text("opacity: one value for every part", (200.0, -130.0))


def main() raises:
    run[App]("Alpha", width=800, height=600)
