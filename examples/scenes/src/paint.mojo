from create import *


@fieldwise_init
struct Paint:
    """The painting scene. Left-drag paints, right-click returns to the menu.

    Deliberately never calls `canvas.background()` per frame — `App.create`
    turns `context.autoclear` off, so skipping the clear here is what lets ink
    accumulate frame to frame. `enter()` is the one exception: it's a plain method, not
    part of `Program`, that `App` calls the frame it switches in, so this
    scene gets a one-shot clear instead of showing the menu bleeding through
    the first stroke.
    """

    var back_pressed: Bool
    var _entering: Bool
    var painting: Bool
    var pen: Point2D

    def enter(mut self):
        self._entering = True

    def update(mut self, context: Context, mut canvas: Canvas) raises:
        self.back_pressed = context.input.mouse_just_pressed(MouseButton.RIGHT)
        self.painting = context.input.is_mouse_down(MouseButton.LEFT)
        self.pen = context.input.mouse

        if self._entering:
            canvas.background(Color(24, 24, 28))
            self._entering = False

        if self.painting:
            with canvas.style():
                canvas.outline(enabled=False)
                canvas.fill(Color(240, 200, 90))
                canvas.circle(self.pen, 14.0)

        with canvas.style():
            canvas.text_color(Color(180, 180, 190))
            canvas.font_size(18)
            # Align.BOTTOM anchors the text box's bottom edge at y, so it
            # grows upward from the margin instead of straddling it — the
            # default Align.CENTER would hang half the line below the margin,
            # its descenders against canvas.bottom() and the letterbox clip.
            canvas.text_align(Align.BOTTOM)
            canvas.text(
                "left-drag to paint    right-click for menu",
                0,
                canvas.bottom() + 14.0,
            )
