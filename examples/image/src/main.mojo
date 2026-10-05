from create import *


@fieldwise_init
struct Game(Program):
    var image: Image
    var x: Int
    var y: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Game:
        var image = Image.load(source_path("../assets/image.jpeg"), 120, 120)
        return Game(image^, 0, 0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var speed = 15
        if context.input.key_down("w"):
            self.y += speed
        if context.input.key_down("s"):
            self.y -= speed
        if context.input.key_down("a"):
            self.x -= speed
        if context.input.key_down("d"):
            self.x += speed

        var hw = (self.image.width) // 2
        var hh = (self.image.height) // 2
        self.x = clamp(
            self.x, Int(canvas.left()) + hw, Int(canvas.right()) - hw
        )
        self.y = clamp(
            self.y, Int(canvas.bottom()) + hh, Int(canvas.top()) - hh
        )

        canvas.background(Color(30, 30, 30))
        canvas.image(self.image, (self.x, self.y))


def main() raises:
    run[Game]("Image Example", WindowMode.FULLSCREEN)
