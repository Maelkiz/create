from create import *


@fieldwise_init
struct Menu:
    """Not a `Program` — a plain struct in the same shape (`update`).

    `App` reads `start_pressed` after calling `update`, the same way it
    would read any other field; that's the whole transition mechanism.
    """

    var start_pressed: Bool

    def update(mut self, context: Context, mut canvas: Canvas) raises:
        self.start_pressed = context.input.mouse_pressed()

        canvas.background(Color(24, 24, 28))
        with canvas.style(
            text_color=Color.WHITE, font_size=48, text_align=Align.TOP
        ):
            canvas.text("Scenes", (0, 40))
        with canvas.style(
            text_color=Color(180, 180, 190), font_size=20, text_align=Align.TOP
        ):
            canvas.text("Click to start painting", (0, -20))
