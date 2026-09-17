from create import *


@fieldwise_init
struct Menu:
    """Not a `Program` — a plain struct in the same shape (`update`/`render`).

    `App` reads `start_pressed` after calling `update`, the same way it
    would read any other field; that's the whole transition mechanism.
    """

    var start_pressed: Bool

    def update(mut self, mut ctx: Context, input: Input) raises:
        self.start_pressed = input.mouse_just_pressed()

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color(24, 24, 28))
        with canvas.style():
            canvas.fill(Color.WHITE)
            canvas.font_size(48)
            canvas.text_align(Align.TOP)
            canvas.text("Scenes", 0, 40)

            canvas.fill(Color(180, 180, 190))
            canvas.font_size(20)
            canvas.text("click to start drawing", 0, -20)
