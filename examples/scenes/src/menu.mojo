from create import *


@fieldwise_init
struct Menu:
    """Not a `Program` — a plain struct in the same shape (`update`).

    `App` reads `start_pressed` after calling `update`, the same way it
    would read any other field; that's the whole transition mechanism.
    """

    var start_pressed: Bool

    def update(mut self, context: Context, mut canvas: Canvas) raises:
        self.start_pressed = context.input.mouse_just_pressed()

        canvas.background(Color(24, 24, 28))
        with canvas.style():
            canvas.text_color(Color.WHITE)
            canvas.font_size(48)
            canvas.text_align(Align.TOP)
            canvas.text("Scenes", (0, 40))

            canvas.text_color(Color(180, 180, 190))
            canvas.font_size(20)
            canvas.text("click to start painting", (0, -20))
