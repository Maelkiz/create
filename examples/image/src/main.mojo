from create import *


@fieldwise_init
struct Game(Program):
    var image: Image
    var position: Point2D

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Game:
        var image = Image.load(source_path("../assets/image.jpeg")).resize(
            120, 120
        )
        return Game(image^, Point2D(0, 0))

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # Units per second, so the speed is the same at any frame rate.
        var step = 900.0 * context.time.delta
        var x = self.position.x
        var y = self.position.y
        if context.input.key_down(Key.W):
            y += step
        if context.input.key_down(Key.S):
            y -= step
        if context.input.key_down(Key.A):
            x -= step
        if context.input.key_down(Key.D):
            x += step

        # Kept on screen, measured from the edges since the origin is the
        # middle of the screen.
        var half_w = Float64(self.image.width()) / 2.0
        var half_h = Float64(self.image.height()) / 2.0
        self.position = Point2D(
            clamp(x, canvas.left() + half_w, canvas.right() - half_w),
            clamp(y, canvas.bottom() + half_h, canvas.top() - half_h),
        )

        canvas.background(Color(30, 30, 30))
        canvas.image(self.image, self.position)


def main() raises:
    run[Game]("Image")
