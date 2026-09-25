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
    def create(mut options: Options) raises -> App:
        # Everything below is authored against the 1280x720 passed to run().
        # Space cycles the three modes:
        #   FIT     resize and the whole scene scales, letterboxed
        #   EXTEND  same scale, no bars — the leftover becomes extra world, so
        #           the circle turns at the new window edge
        #   OFF     no scaling at all — the world is the window in pixels, so
        #           the scene stays put while the space around it grows
        # The origin is the middle of the design area and y grows upward, so
        # the labels below centre sit at negative y.
        options.autoscale = AutoScale.FIT
        return App(100.0, 1.0)

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        if frame.input.just_pressed("space"):
            if options.autoscale == AutoScale.FIT:
                options.autoscale = AutoScale.EXTEND
            elif options.autoscale == AutoScale.EXTEND:
                options.autoscale = AutoScale.OFF
            else:
                options.autoscale = AutoScale.FIT
        self.x += self.dir * 200.0 * frame.time.delta
        # Set the sign rather than flip it: under EXTEND/OFF a shrinking
        # window can move frame.right()/left() past the ball between frames,
        # and a flip on an already-true condition alternates forever instead
        # of turning the ball back inward.
        if self.x > frame.right() - 40.0:
            self.dir = -1.0
        elif self.x < frame.left() + 40.0:
            self.dir = 1.0

        frame.background(Color(0x99))

        frame.fill(Color.RED)
        frame.circle((self.x, 150), 40)

        frame.fill(Color.BLUE)
        frame.rectangle((0, 0), 200, 120)

        frame.text_color(Color.BLACK)
        frame.font_size(28)
        frame.text_align(Align.TOP)
        frame.text("Autoscale Mode: " + _mode_name(options.autoscale), 0, -140)
        frame.font_size(20)
        frame.text("(space to cycle)", 0, -180)
        frame.font_size(28)
        frame.text("Current scale: " + String(frame.scale), 0, -220)


def main() raises:
    run[App]("Autoscale", WindowMode.FULLSCREEN, width=800, height=600)
