"""A program's own type drawn with `canvas.draw`, and the style's corner
radius.

Each `Button` is a rounded plate with a round icon: `Drawable`, so the canvas
draws it as its parts in the current style. It lights up while the mouse is
inside its plate, and because the plate carries its own `corner_radius`, a
pointer in a cut-away corner leaves it dark: what is drawn is what
`contains` tests.

Below, plain `canvas.rectangle` calls are rounded by `canvas.corner_radius`,
the style's radius for shapes built from numbers; the last names its own.
"""

from create import *


@fieldwise_init
struct Button(Copyable, Drawable, Movable):
    var plate: Rectangle
    var icon: Circle

    def draw_to[T: DrawTarget](self, mut target: T):
        target.draw(self.plate)
        target.draw(self.icon)


def button(position: Point2D) -> Button:
    return Button(
        Rectangle(position, 220, 90, corner_radius=36),
        Circle(position - Vector2D(65, 0), 22),
    )


@fieldwise_init
struct App(Program):
    var buttons: List[Button]

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        return App([button((-260, 110)), button((0, 110)), button((260, 110))])

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(0xF4, 0xF5, 0xF8))
        canvas.outline(Color(0x30, 0x38, 0x48), thickness=3)

        for b in self.buttons:
            var hovered = b.plate.contains(context.input.mouse)
            canvas.fill(Color(0xFF, 0xB0, 0x40) if hovered else Color.WHITE)
            canvas.draw(b)

        with canvas.style(fill=Color(0x60, 0x90, 0xE0)):
            canvas.corner_radius(8)
            canvas.rectangle((-300, -110), 120, 80)
            canvas.rectangle((-150, -110), 120, 80)
            canvas.corner_radius(30)
            canvas.rectangle((0, -110), 120, 80)
            canvas.rectangle((150, -110), 120, 80)
            canvas.rectangle((300, -110), 120, 80, corner_radius=0)

        with canvas.style(text_color=Color(0x50, 0x58, 0x68), font_size=18):
            canvas.text("canvas.draw(button)", (0, 200))
            canvas.text(
                "canvas.corner_radius(8), then (30); the last names 0",
                (0, -190),
            )


def main() raises:
    run[App]("Drawables", width=900, height=500)
