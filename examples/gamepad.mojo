from create import *

comptime PLAYERS = 4
comptime SPEED = 300.0
comptime MESSAGE_SECONDS = 3.0


@fieldwise_init
struct Gamepads(Program):
    """Up to four players, one per gamepad: the left stick moves, the right
    trigger boosts, SOUTH (Xbox A, PlayStation Cross) swaps colour with a
    buzz and START returns home. A pad thumps as it joins, and the screen
    says who joined or left."""

    var positions: List[Point2D]
    var colors: List[Int]
    var message: String
    var message_until: Float64

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Gamepads:
        var positions = List[Point2D]()
        var colors = List[Int]()
        for i in range(PLAYERS):
            positions.append(Point2D(Float64(i) * 120 - 180, 0))
            colors.append(i)
        return Gamepads(positions^, colors^, "", 0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(30, 30, 40))
        var palette = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]

        for i in range(PLAYERS):
            var pad = context.input.gamepad(i)
            var player = "Player " + String(i + 1)
            if pad.connected_this_frame:
                self.say(context, player + " joined: " + pad.name)
                context.rumble(0.3, low_frequency=1, high_frequency=0, player=i)
            if pad.disconnected_this_frame:
                self.say(context, player + " left: " + pad.name)
            if not pad.connected:
                continue
            var speed = SPEED * (1.0 + pad.right_trigger)
            self.positions[i] = (
                self.positions[i] + pad.left_stick * speed * context.time.delta
            )
            if pad.button_pressed(GamepadButton.SOUTH):
                self.colors[i] = (self.colors[i] + 1) % len(palette)
                context.rumble(0.1, low_frequency=0, high_frequency=1, player=i)
            if pad.button_pressed(GamepadButton.START):
                self.positions[i] = Point2D(Float64(i) * 120 - 180, 0)

            canvas.fill(palette[self.colors[i]])
            canvas.circle(self.positions[i], 30 + 20 * pad.left_trigger)
            canvas.text_color(Color.WHITE)
            canvas.text(String(i + 1), self.positions[i] + Vector2D(-6, 45))

        canvas.text_color(Color.WHITE)
        var connected = 0
        for i in range(PLAYERS):
            if context.input.gamepad(i).connected:
                connected += 1
        canvas.text(
            String(connected) + " of " + String(PLAYERS) + " gamepads",
            (canvas.left() + 20, canvas.top() - 30),
        )
        if context.time.elapsed < self.message_until:
            canvas.text(
                self.message, (canvas.left() + 20, canvas.bottom() + 20)
            )
        if connected == 0:
            canvas.text("Plug in a gamepad", (-90, 0))

    def say(mut self, context: Context, message: String):
        self.message = message
        self.message_until = context.time.elapsed + MESSAGE_SECONDS


def main() raises:
    run[Gamepads]("Gamepads", width=800, height=600)
