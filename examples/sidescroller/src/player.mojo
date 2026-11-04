from create import *


@fieldwise_init
struct Player(Copyable, Drawable, Movable):
    """A box that runs, jumps and double-jumps under gravity, and lands on
    whichever platform it falls onto.

    `Drawable`, so the game draws it with `canvas.draw(player)`, in the
    game's style.
    """

    # All rates are per second, integrated with context.time.delta so the feel
    # is the same at any frame rate. y grows upward, so gravity is negative and
    # a jump is positive.
    comptime WIDTH = 60.0
    comptime HEIGHT = 80.0
    comptime SPEED = 540.0  # units/s
    comptime GRAVITY = -5400.0  # units/s^2
    comptime JUMP_SPEED = 1400.0  # units/s
    comptime JUMP_HOLD = 1080.0  # units/s^2, against gravity while W is held
    comptime JUMPS = 2  # one from the ground, one in the air

    var position: Point2D
    """The middle of the body, as every shape is placed."""
    var velocity: Vector2D
    var jumps_left: Int

    def feet(self) -> Float64:
        return self.position.y - Self.HEIGHT / 2.0

    def body(self) -> Rectangle:
        return Rectangle(
            self.position, Self.WIDTH, Self.HEIGHT, corner_radius=10
        )

    def update(mut self, context: Context, platforms: List[Rectangle]):
        var dt = context.time.delta

        var run = 0.0
        if context.input.key_down(Key.A):
            run -= Self.SPEED
        if context.input.key_down(Key.D):
            run += Self.SPEED

        var rise = self.velocity.y
        if context.input.key_pressed(Key.W) and self.jumps_left > 0:
            rise = Self.JUMP_SPEED
            self.jumps_left -= 1
        var gravity = Self.GRAVITY
        if context.input.key_down(Key.W) and rise > 0:
            gravity += Self.JUMP_HOLD
        self.velocity = Vector2D(run, rise + gravity * dt)

        var feet_before = self.feet()
        self.position = self.position + self.velocity * dt

        # Platforms are one-way, as in most platformers: jumped through from
        # below, landed on from above.
        if self.velocity.y <= 0 and self.land(feet_before, platforms):
            return
        # In the air without having jumped, walked off a ledge: the jump from
        # the ground is gone, and only the double jump is left.
        self.jumps_left = min(self.jumps_left, Self.JUMPS - 1)

    def land(
        mut self, feet_before: Float64, platforms: List[Rectangle]
    ) -> Bool:
        """Stand on the platform whose top the feet crossed this frame, if
        any. Tested as a crossing, so a fast fall can't skip one."""
        for platform in platforms:
            var top = platform.position.y + platform.h / 2.0
            var reach = (platform.w + Self.WIDTH) / 2.0
            if (
                feet_before >= top
                and self.feet() <= top
                and abs(self.position.x - platform.position.x) < reach
            ):
                self.position = Point2D(
                    self.position.x, top + Self.HEIGHT / 2.0
                )
                self.velocity = Vector2D(self.velocity.x, 0.0)
                self.jumps_left = Self.JUMPS
                return True
        return False

    def draw_to[T: DrawTarget](self, mut target: T):
        target.draw(self.body())
