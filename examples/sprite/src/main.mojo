from create import *


@fieldwise_init
struct Game(Program):
    var sprite: Sprite
    var x: Int
    var y: Int

    @staticmethod
    def create(mut context: Context) raises -> Game:
        var sprite = Sprite.load(source_path("../assets/sprite.jpeg"), 120, 120)
        return Game(sprite^, 0, 0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var speed = 15
        if context.input.is_key_down("w"):
            self.y += speed
        if context.input.is_key_down("s"):
            self.y -= speed
        if context.input.is_key_down("a"):
            self.x -= speed
        if context.input.is_key_down("d"):
            self.x += speed

        var hw = (self.sprite.width) // 2
        var hh = (self.sprite.height) // 2
        self.x = clamp(
            self.x, Int(canvas.left()) + hw, Int(canvas.right()) - hw
        )
        self.y = clamp(
            self.y, Int(canvas.bottom()) + hh, Int(canvas.top()) - hh
        )

        canvas.background(Color(30, 30, 30))
        canvas.sprite(self.sprite, (self.x, self.y))


def main() raises:
    run[Game]("Sprite Example", WindowMode.FULLSCREEN)
