from create import *


@fieldwise_init
struct Game(Program):
    var sprite: Sprite
    var x: Int
    var y: Int

    @staticmethod
    def create(mut ctx: Context) raises -> Game:
        var sprite = Sprite.load(
            script_dir() + "/../assets/sprite.jpeg", 120, 120
        )
        return Game(sprite^, 0, 0)

    def update(mut self, mut ctx: Context, input: Input) raises:
        var speed = 15
        if input.is_key_down("w"):
            self.y += speed
        if input.is_key_down("s"):
            self.y -= speed
        if input.is_key_down("a"):
            self.x -= speed
        if input.is_key_down("d"):
            self.x += speed

        var hw = (self.sprite.width) // 2
        var hh = (self.sprite.height) // 2
        self.x = clamp(self.x, Int(ctx.left()) + hw, Int(ctx.right()) - hw)
        self.y = clamp(self.y, Int(ctx.bottom()) + hh, Int(ctx.top()) - hh)

    def render(self, mut frame: Frame) raises:
        frame.background(Color(30, 30, 30))
        frame.sprite(self.sprite, self.x, self.y)


def main() raises:
    run[Game]("Sprite Example", mode=WindowMode.FULLSCREEN)
