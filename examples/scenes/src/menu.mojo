from create import *


@fieldwise_init
struct Menu:
    """Not a `Program` — a plain struct in the same shape (`update`).

    `App` reads `start_pressed` after calling `update`, the same way it
    would read any other field; that's the whole transition mechanism.
    """

    var start_pressed: Bool

    def update(mut self, mut frame: Frame) raises:
        self.start_pressed = frame.input.mouse_just_pressed()

        frame.background(Color(24, 24, 28))
        with frame.style():
            frame.text_color(Color.WHITE)
            frame.font_size(48)
            frame.text_align(Align.TOP)
            frame.text("Scenes", 0, 40)

            frame.text_color(Color(180, 180, 190))
            frame.font_size(20)
            frame.text("click to start drawing", 0, -20)
