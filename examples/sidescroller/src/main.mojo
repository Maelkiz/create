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
    def create(mut frame: Frame) raises -> Game:
        frame.autoscale = AutoScale.FIT
        var w: Float64 = 60
        var h: Float64 = 80
        return Game(Player(0.0, 0.0, w, h, 0.0, False, 2), Camera())

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.player.update(frame, input)

        var half_w = self.player.width / 2
        if self.player.x - half_w < self.WORLD_LEFT:
            self.player.x = self.WORLD_LEFT + half_w
        if self.player.x + half_w > self.WORLD_RIGHT:
            self.player.x = self.WORLD_RIGHT - half_w

        # Follow the player horizontally; the ground stays screen-fixed so
        # jumping doesn't move the camera vertically too.
        self.cam.position = Point2D(self.player.x, 0.0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color(30, 30, 30))
        frame.camera(self.cam)

        # Ground markers every 200 world units, so panning past the edge of
        # any one screen is visible rather than looking like an empty void.
        with frame.style():
            frame.outline(enabled=False)
            frame.fill(Color(70, 70, 70))
            var first = Int((self.cam.position.x - 1000.0) / 200.0) * 200
            var last = first + 2200
            for i in range(
                max(first, Int(self.WORLD_LEFT)),
                min(last, Int(self.WORLD_RIGHT) + 1),
                200,
            ):
                frame.circle(i, 0, 5)

        self.player.draw(frame)

        # Walls at the world edges; only the one in view actually renders.
        with frame.style():
            frame.outline(enabled=False)
            frame.fill(Color(150, 60, 60))
            var wall_h = frame.top() - frame.bottom()
            frame.rectangle(self.WORLD_LEFT, 0.0, 30.0, wall_h)
            frame.rectangle(self.WORLD_RIGHT, 0.0, 30.0, wall_h)

        with frame.overlay():
            frame.text_color(Color(220, 220, 220))
            frame.text(
                "A/D move, W jump (double-jump in air)",
                (frame.left() + 20.0, frame.top() - 20.0),
            )


def main() raises:
    run[Game]("Sidescroller", WindowMode.FULLSCREEN)
