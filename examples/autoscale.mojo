from create import *


def _mode_name(mode: AutoScale) -> String:
    if mode == AutoScale.FIT:
        return "FIT"
    if mode == AutoScale.EXTEND:
        return "EXTEND"
    return "OFF"


@fieldwise_init
struct App(Program):
    var x: Float64
    var dir: Float64

    @staticmethod
    def create(mut context: Context) raises -> App:
        # Everything below is authored against the 1280x720 passed to run().
        # Space cycles the three modes:
        #   FIT     resize and the whole scene scales, letterboxed
        #   EXTEND  same scale, no bars — the leftover becomes extra world, so
        #           the circle turns at the new window edge
        #   OFF     no scaling at all — the world is the window in pixels, so
        #           the scene stays put while the space around it grows
        # The origin is the middle of the design area and y grows upward, so
        # the labels below centre sit at negative y.
        context.autoscale = AutoScale.FIT
        return App(100.0, 1.0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        if canvas.input.just_pressed("space"):
            if context.autoscale == AutoScale.FIT:
                context.autoscale = AutoScale.EXTEND
            elif context.autoscale == AutoScale.EXTEND:
                context.autoscale = AutoScale.OFF
            else:
                context.autoscale = AutoScale.FIT
        self.x += self.dir * 200.0 * context.time.delta
        # Set the sign rather than flip it: under EXTEND/OFF a shrinking
        # window can move canvas.right()/left() past the ball between frames,
        # and a flip on an already-true condition alternates forever instead
        # of turning the ball back inward.
        if self.x > canvas.right() - 40.0:
            self.dir = -1.0
        elif self.x < canvas.left() + 40.0:
            self.dir = 1.0

        canvas.background(Color(0x99))

        canvas.fill(Color.RED)
        canvas.circle((self.x, 150), 40)

        canvas.fill(Color.BLUE)
        canvas.rectangle((0, 0), 200, 120)

        canvas.text_color(Color.BLACK)
        canvas.font_size(28)
        canvas.text_align(Align.TOP)
        canvas.text("Autoscale Mode: " + _mode_name(context.autoscale), 0, -140)
        canvas.font_size(20)
        canvas.text("(space to cycle)", 0, -180)
        canvas.font_size(28)
        canvas.text("Current scale: " + String(canvas.scale), 0, -220)


def main() raises:
    run[App]("Autoscale", WindowMode.FULLSCREEN, width=800, height=600)
