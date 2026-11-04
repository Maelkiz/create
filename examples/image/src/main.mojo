"""Images: loaded from a file, built pixel by pixel, read back and tinted.

Along the top, one picture saved as JPEG, PNG and BMP, each loaded with
`Image.load`; hover one to read the pixel under the mouse with
`image.pixel`. Pixels are cells of the image, counted from its top-left
corner with y down, so the mouse's position is converted first.

Below, a sprite built cell by cell in a `PixelBuffer`, then made an `Image`.
W, A, S and D move it; T cycles the `tint` that recolours it, a multiply of
every pixel, so white keeps each colour and darker tints shade it.
"""

from create import *

comptime _BACKGROUND = Color(40, 42, 56)
comptime _TEXT = Color(200, 200, 212)
comptime _HINT = Color(150, 160, 180)
comptime _SIZE = 220.0
"""How big each loaded picture is drawn, in design units."""
comptime _ROW_Y = 120.0
comptime _SPRITE_CELLS = 16
comptime _SPRITE_SIZE = 128.0
comptime _SPEED = 400.0
"""How fast the sprite moves, in design units per second."""


def _formats() -> List[String]:
    return ["jpeg", "png", "bmp"]


def _tints() -> List[Color]:
    return [
        Color.WHITE,
        Color(150, 255, 180),
        Color(150, 200, 255),
        Color(160, 160, 160),
    ]


def _sprite() raises -> Image:
    """A ring of colours, set one cell at a time. A buffer starts
    transparent, so the corners outside the ring stay see-through."""
    var buffer = PixelBuffer(_SPRITE_CELLS, _SPRITE_CELLS)
    var middle = Float64(_SPRITE_CELLS - 1) / 2.0
    for y in range(_SPRITE_CELLS):
        for x in range(_SPRITE_CELLS):
            var offset = Vector2D(Float64(x) - middle, middle - Float64(y))
            var distance = offset.magnitude()
            if distance <= middle + 0.5:
                var hue = (offset.angle() / TAU) * 360.0
                var value = 0.55 if distance < middle / 2.0 else 1.0
                buffer.set(x, y, Color.hsv(hue, 0.7, value))
    # The buffer is handed over, not copied: it can't be used after this.
    return Image(buffer^)


@fieldwise_init
struct Images(Program):
    var pictures: List[Image]
    """The same picture from each format in `_formats()`."""
    var sprite: Image
    var position: Point2D
    var tint: Int
    """Which of `_tints()` the sprite is drawn with."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Images:
        var pictures = List[Image]()
        for format in _formats():
            pictures.append(
                Image.load(source_path("../assets/image." + format))
            )
        return Images(
            pictures=pictures^,
            sprite=_sprite(),
            position=Point2D(0, -170),
            tint=0,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        ref input = context.input
        var step = _SPEED * context.time.delta
        var x = self.position.x
        var y = self.position.y
        if input.key_down(Key.W):
            y += step
        if input.key_down(Key.S):
            y -= step
        if input.key_down(Key.A):
            x -= step
        if input.key_down(Key.D):
            x += step
        # Kept on screen, measured from the edges since the origin is the
        # middle of the screen.
        var half = _SPRITE_SIZE / 2.0
        self.position = Point2D(
            clamp(x, canvas.left() + half, canvas.right() - half),
            clamp(y, canvas.bottom() + half, canvas.top() - half),
        )
        if input.key_pressed(Key.T):
            self.tint = (self.tint + 1) % len(_tints())

        canvas.background(_BACKGROUND)

        var formats = _formats()
        var reading = String("Hover a picture to read its pixels")
        for i in range(len(self.pictures)):
            ref picture = self.pictures[i]
            var center = Point2D(Float64(i - 1) * 300.0, _ROW_Y)
            canvas.image(picture, center, _SIZE, _SIZE)
            with canvas.style(text_color=_HINT, font_size=18):
                canvas.text(
                    "image." + formats[i], (center.x, _ROW_Y - _SIZE / 2 - 24)
                )

            # From the mouse to a cell: measured from the top-left corner,
            # y down, and scaled from the drawn size to the image's own.
            var left = center.x - _SIZE / 2.0
            var top = center.y + _SIZE / 2.0
            var column = Int(
                (input.mouse.x - left) / _SIZE * Float64(picture.width())
            )
            var row = Int(
                (top - input.mouse.y) / _SIZE * Float64(picture.height())
            )
            if (
                column >= 0
                and column < picture.width()
                and row >= 0
                and row < picture.height()
            ):
                var color = picture.pixel(column, row)
                reading = String(
                    "image.",
                    formats[i],
                    ".pixel(",
                    column,
                    ", ",
                    row,
                    ") is ",
                    color,
                )
                with canvas.style(
                    fill=color, outline=_TEXT, outline_thickness=2
                ):
                    canvas.rectangle(input.mouse + Vector2D(30, 30), 36, 36)

        with canvas.style(text_color=_TEXT, font_size=18):
            canvas.text(reading, (0.0, _ROW_Y + _SIZE / 2 + 30))

        var tint = _tints()[self.tint]
        with canvas.style(tint=tint):
            canvas.image(self.sprite, self.position, _SPRITE_SIZE, _SPRITE_SIZE)
        with canvas.style(text_color=_HINT, font_size=18):
            canvas.text(
                "W, A, S and D move the sprite; T tints it: " + String(tint),
                (0.0, canvas.bottom() + 30),
            )


def main() raises:
    run[Images]("Image", width=1280, height=720)
