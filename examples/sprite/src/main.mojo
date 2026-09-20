from create import *


@fieldwise_init
struct Game(Program):
    var sprite: Sprite
    var x: Int
    var y: Int

    @staticmethod
    def create(mut options: Options) raises -> Game:
        var sprite = Sprite.load(
            script_dir() + "/../assets/sprite.jpeg", 120, 120
        )
        return Game(sprite^, 0, 0)

    def update(
        mut self, mut options: Options, mut frame: Frame, input: Input
    ) raises:
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
        self.x = clamp(self.x, Int(frame.left()) + hw, Int(frame.right()) - hw)
        self.y = clamp(self.y, Int(frame.bottom()) + hh, Int(frame.top()) - hh)

        frame.background(Color(30, 30, 30))
        frame.sprite(self.sprite, self.x, self.y)


def main() raises:
    run[Game]("Sprite Example", WindowMode.FULLSCREEN)
