from create import *


@fieldwise_init
struct Draw:
    """The drawing scene. Left-drag paints, right-click returns to the menu.

    Deliberately never calls `frame.background()` per frame — `App.create`
    turns `frame.autoclear` off, so skipping the clear here is what lets ink
    accumulate frame to frame. `enter()` is the one exception: it's a plain method, not
    part of `Program`, that `App` calls the frame it switches in, so this
    scene gets a one-shot clear instead of showing the menu bleeding through
    the first stroke.
    """

    var back_pressed: Bool
    var _entering: Bool
    var drawing: Bool
    var pen: Point2D

    def enter(mut self):
        self._entering = True

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.back_pressed = input.mouse_just_pressed(MouseButton.RIGHT)
        self.drawing = input.is_mouse_down(MouseButton.LEFT)
        self.pen = input.mouse

        if self._entering:
            frame.background(Color(24, 24, 28))
            self._entering = False

        if self.drawing:
            with frame.style():
                frame.outline(enabled=False)
                frame.fill(Color(240, 200, 90))
                frame.circle(self.pen, 14.0)

        with frame.style():
            frame.text_color(Color(180, 180, 190))
            frame.font_size(18)
            # Align.BOTTOM anchors the text box's bottom edge at y, so it
            # grows upward from the margin instead of downward past it — the
            # default Align.TOP_LEFT would run this line's descenders straight
            # through frame.bottom() and into the letterbox clip.
            frame.text_align(Align.BOTTOM)
            frame.text(
                "left-drag to paint    right-click for menu",
                0,
                frame.bottom() + 14.0,
            )
