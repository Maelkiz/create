from create import *


@fieldwise_init
struct Player:
    # All rates are per second, integrated with context.time.delta so the feel is
    # the same at any frame rate. y grows upward, so gravity is negative and a
    # jump is positive.
    comptime GRAVITY: Float64 = -5400.0  # units/s^2
    comptime JUMP_FORCE: Float64 = 1400.0  # units/s
    comptime JUMP_HOLD_FORCE: Float64 = 1080.0  # units/s^2
    comptime SPEED: Float64 = 540.0  # units/s

    var x: Float64
    var y: Float64
    var width: Float64
    var height: Float64
    var vel_y: Float64
    var on_ground: Bool
    var jumps_left: Int

    def update(mut self, context: Context, canvas: Canvas):
        var dt = context.time.delta

        if context.input.is_key_down("a"):
            self.x -= self.SPEED * dt
        if context.input.is_key_down("d"):
            self.x += self.SPEED * dt

        if context.input.just_pressed("w") and self.jumps_left > 0:
            self.vel_y = self.JUMP_FORCE
            self.jumps_left -= 1

        if context.input.is_key_down("w") and self.vel_y > 0:
            self.vel_y += self.JUMP_HOLD_FORCE * dt

        self.vel_y += self.GRAVITY * dt
        self.y += self.vel_y * dt

        var half_h = self.height / 2

        # Ceiling: moving up and past the top edge.
        if self.y + half_h > canvas.top():
            self.y = canvas.top() - half_h
            if self.vel_y > 0:
                self.vel_y = 0.0

        if self.y - half_h <= canvas.bottom():
            self.y = canvas.bottom() + half_h
            self.vel_y = 0.0
            self.on_ground = True
            self.jumps_left = 2
        else:
            self.on_ground = False

    def render(self, mut canvas: Canvas) raises:
        # Scoped, because this is a callee: without the guard the caller's
        # next render would silently inherit this fill and outline(enabled=False).
        with canvas.style():
            canvas.fill(Color(220, 80, 80))
            canvas.outline(enabled=False)
            canvas.rectangle(self.x, self.y, self.width, self.height)
