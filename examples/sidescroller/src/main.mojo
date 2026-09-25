from create import *
from player import Player


@fieldwise_init
struct Game(Program):
    # World bounds live here, not on Player: they're level geometry the game
    # enforces, not something the player needs to know about itself.
    comptime WORLD_LEFT: Float64 = -4000.0
    comptime WORLD_RIGHT: Float64 = 4000.0

    var player: Player
    var cam: Camera

    @staticmethod
    def create(mut context: Context) raises -> Game:
        context.autoscale = AutoScale.FIT
        var w: Float64 = 60
        var h: Float64 = 80
        return Game(Player(0.0, 0.0, w, h, 0.0, False, 2), Camera())

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.player.update(context, canvas)

        var half_w = self.player.width / 2
        if self.player.x - half_w < self.WORLD_LEFT:
            self.player.x = self.WORLD_LEFT + half_w
        if self.player.x + half_w > self.WORLD_RIGHT:
            self.player.x = self.WORLD_RIGHT - half_w

        # Follow the player horizontally; the ground stays screen-fixed so
        # jumping doesn't move the camera vertically too.
        self.cam.position = Point2D(self.player.x, 0.0)

        canvas.background(Color(30, 30, 30))
        canvas.camera(self.cam)

        # Ground markers every 200 world units, so panning past the edge of
        # any one screen is visible rather than looking like an empty void.
        with canvas.style():
            canvas.outline_enabled(False)
            canvas.fill(Color(70, 70, 70))
            var first = Int((self.cam.position.x - 1000.0) / 200.0) * 200
            var last = first + 2200
            for i in range(
                max(first, Int(self.WORLD_LEFT)),
                min(last, Int(self.WORLD_RIGHT) + 1),
                200,
            ):
                canvas.circle(i, 0, 5)

        self.player.render(canvas)

        # Walls at the world edges; only the one in view actually renders.
        with canvas.style():
            canvas.outline_enabled(False)
            canvas.fill(Color(150, 60, 60))
            var wall_h = canvas.top() - canvas.bottom()
            canvas.rectangle(self.WORLD_LEFT, 0.0, 30.0, wall_h)
            canvas.rectangle(self.WORLD_RIGHT, 0.0, 30.0, wall_h)

        with canvas.overlay():
            canvas.text_color(Color(220, 220, 220))
            canvas.text_align(Align.TOP_LEFT)
            canvas.text(
                "A/D move, W jump (double-jump in air)",
                (canvas.left() + 20.0, canvas.top() - 20.0),
            )


def main() raises:
    run[Game]("Sidescroller", WindowMode.FULLSCREEN)
