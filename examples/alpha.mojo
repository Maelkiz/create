from create import *


@fieldwise_init
struct App(Program):
    var t: Float64

    @staticmethod
    def create(mut frame: Frame) raises -> App:
        return App(0.0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.t = frame.time.elapsed

        # A translucent background fades the previous frame instead of
        # clearing it, leaving motion trails.
        frame.background(Color(0x11, 0x11, 0x11, 24))

        frame.outline(enabled=False)

        # Overlapping translucent fills mix where they cross. The origin is the
        # middle of the screen, so these are absolute world coordinates.
        frame.fill(Color(255, 0, 0, 128))
        frame.circle((-60.0, 0.0), 90.0)
        frame.fill(Color(0, 255, 0, 128))
        frame.circle((60.0, 0.0), 90.0)
        frame.fill(Color(0, 0, 255, 128))
        frame.circle((0.0, 90.0), 90.0)

        # An orbiting dot draws the trail the faded background preserves.
        var r = 220.0
        frame.fill(Color.ORANGE)
        frame.circle((r * cos(self.t), r * sin(self.t) * 0.5), 14.0)

        frame.text_color(Color(255, 255, 255, 160))
        frame.font_size(28)
        frame.text_align(Align.TOP)
        frame.text("alpha", 0.0, -150.0)


def main() raises:
    run[App]("Alpha", 800, 600)
