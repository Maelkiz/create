from create import *


def _mode_name(mode: Int) -> String:
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
    def create(mut frame: Frame) raises -> App:
        # Everything below is authored against the 1280x720 passed to run().
        # Space cycles the three modes:
        #   FIT     resize and the whole scene scales, letterboxed
        #   EXTEND  same scale, no bars — the leftover becomes extra world, so
        #           the circle turns at the new window edge
        #   OFF     no scaling at all — the world is the window in pixels, so
        #           the scene stays put while the space around it grows
        # The origin is the middle of the design area and y grows upward, so
        # the labels below centre sit at negative y.
        frame.autoscale = AutoScale.FIT
        return App(100.0, 1.0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        if input.just_pressed("space"):
            if frame.autoscale == AutoScale.FIT:
                frame.autoscale = AutoScale.EXTEND
            elif frame.autoscale == AutoScale.EXTEND:
                frame.autoscale = AutoScale.OFF
            else:
                frame.autoscale = AutoScale.FIT
        self.x += self.dir * 200.0 * frame.time.delta
        # Set the sign rather than flip it: under EXTEND/OFF a shrinking
        # window can move frame.right()/left() past the ball between frames,
        # and a flip on an already-true condition alternates forever instead
        # of turning the ball back inward.
        if self.x > frame.right() - 40.0:
            self.dir = -1.0
        elif self.x < frame.left() + 40.0:
            self.dir = 1.0

    def render(self, mut frame: Frame) raises:
        frame.background(Color(0x99))

        frame.fill(Color.RED)
        frame.circle((self.x, 150), 40)

        frame.fill(Color.BLUE)
        frame.rectangle((0, 0), 200, 120)

        frame.text_color(Color.BLACK)
        frame.font_size(28)
        frame.text_align(Align.TOP)
        frame.text("Autoscale Mode: " + _mode_name(frame.autoscale), 0, -140)
        frame.font_size(20)
        frame.text("(space to cycle)", 0, -180)
        frame.font_size(28)
        frame.text("Current scale: " + String(frame.scale), 0, -220)


def main() raises:
    run[App]("Autoscale", 800, 600, WindowMode.FULLSCREEN)
