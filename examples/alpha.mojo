from create import *


@fieldwise_init
struct App(Program):
    var t: Float64

    @staticmethod
    def create(mut context: Context) raises -> App:
        # The trails below are rendered by fading the *previous* frame, so the
        # per-frame clear has to be off — it would wipe what they fade.
        context.autoclear = False
        return App(0.0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.t = canvas.time.elapsed

        # A translucent background fades the previous frame instead of
        # clearing it, leaving motion trails.
        canvas.background(Color(0x11, 0x11, 0x11, 24))

        canvas.outline(enabled=False)

        # Overlapping translucent fills mix where they cross. The origin is the
        # middle of the screen, so these are absolute world coordinates.
        canvas.fill(Color(255, 0, 0, 128))
        canvas.circle((-60.0, 0.0), 90.0)
        canvas.fill(Color(0, 255, 0, 128))
        canvas.circle((60.0, 0.0), 90.0)
        canvas.fill(Color(0, 0, 255, 128))
        canvas.circle((0.0, 90.0), 90.0)

        # An orbiting dot renders the trail the faded background preserves.
        var r = 220.0
        canvas.fill(Color.ORANGE)
        canvas.circle((r * cos(self.t), r * sin(self.t) * 0.5), 14.0)

        canvas.text_color(Color(255, 255, 255, 160))
        canvas.font_size(28)
        canvas.text_align(Align.TOP)
        canvas.text("alpha", 0.0, -150.0)


def main() raises:
    run[App]("Alpha", width=800, height=600)
