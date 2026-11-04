"""A side-scroller: a player that runs and double-jumps under gravity across
platforms, and a camera that follows it through a world wider than the
screen.

A and D move, W jumps (again in the air); hold W to jump higher.
"""

from create import *

from player import Player

# The level, in world units. y is up, so the ground's top is below the middle
# of the screen, and a platform higher up has a larger y.
comptime _WORLD_LEFT = -2400.0
comptime _WORLD_RIGHT = 2400.0
comptime _GROUND_TOP = -240.0
comptime _PLATFORM_THICKNESS = 24.0
comptime _CAMERA_LEAD = 150.0
"""How far above the camera's centre the player climbs before it follows."""

comptime _SKY = Color(24, 26, 34)
comptime _GROUND = Color(38, 42, 54)
comptime _PLATFORM = Color(70, 76, 98)
comptime _WALL = Color(52, 56, 72)
comptime _PLAYER = Color(235, 120, 70)
comptime _HINT = Color(150, 160, 180)


def _platforms() -> List[Rectangle]:
    """The ground, then the platforms, left to right. Every shape is placed
    by its middle, so each top is half a thickness above its position."""
    var ground_depth = 1000.0
    var level: List[Rectangle] = [
        Rectangle(
            (0.0, _GROUND_TOP - ground_depth / 2.0),
            _WORLD_RIGHT - _WORLD_LEFT,
            ground_depth,
        )
    ]
    # (middle x, top, width): each top within a jump of the one before.
    var layout: List[Tuple[Float64, Float64, Float64]] = [
        (-1900.0, -110.0, 220.0),
        (-1550.0, 30.0, 200.0),
        (-1150.0, -60.0, 260.0),
        (-700.0, 60.0, 200.0),
        (-300.0, -110.0, 240.0),
        (100.0, 20.0, 200.0),
        (450.0, 160.0, 180.0),
        (850.0, 20.0, 220.0),
        (1250.0, -100.0, 260.0),
        (1650.0, 40.0, 200.0),
        (2000.0, 180.0, 180.0),
    ]
    for platform in layout:
        level.append(
            Rectangle(
                (platform[0], platform[1] - _PLATFORM_THICKNESS / 2.0),
                platform[2],
                _PLATFORM_THICKNESS,
                corner_radius=6,
            )
        )
    return level^


@fieldwise_init
struct Game(Program):
    var player: Player
    var platforms: List[Rectangle]
    """The ground first, then the platforms."""
    var camera: Camera

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Game:
        return Game(
            player=Player(
                position=Point2D(0.0, _GROUND_TOP + Player.HEIGHT / 2.0),
                velocity=Vector2D.ZERO,
                jumps_left=Player.JUMPS,
            ),
            platforms=_platforms(),
            camera=Camera(),
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.player.update(context, self.platforms)

        # The world's edges are the game's to enforce, not the player's.
        var half_w = Player.WIDTH / 2.0
        var position = self.player.position
        self.player.position = Point2D(
            clamp(position.x, _WORLD_LEFT + half_w, _WORLD_RIGHT - half_w),
            position.y,
        )

        # Follow the player sideways, and upwards only once it climbs past
        # the lead, so a jump from the ground leaves the view still.
        self.camera.position = Point2D(
            self.player.position.x,
            max(0.0, self.player.position.y - _CAMERA_LEAD),
        )

        canvas.background(_SKY)
        canvas.camera(self.camera)

        with canvas.style(outline_enabled=False):
            canvas.fill(_GROUND)
            canvas.draw(self.platforms[0])
            canvas.fill(_PLATFORM)
            for i in range(1, len(self.platforms)):
                canvas.draw(self.platforms[i])

            # Walls past either edge, wide enough to fill the view there.
            canvas.fill(_WALL)
            canvas.rectangle((_WORLD_LEFT - 500.0, 0.0), 1000.0, 4000.0)
            canvas.rectangle((_WORLD_RIGHT + 500.0, 0.0), 1000.0, 4000.0)

            canvas.fill(_PLAYER)
            canvas.draw(self.player)

        with canvas.overlay():
            with canvas.style(
                text_color=_HINT, font_size=20, text_align=Align.TOP_LEFT
            ):
                canvas.text(
                    "A/D move, W jump (again in the air)",
                    (canvas.left() + 20.0, canvas.top() - 20.0),
                )


def main() raises:
    run[Game]("Sidescroller")
