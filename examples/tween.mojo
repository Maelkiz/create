from create import *

# The gallery, top to bottom. LINEAR first so every other row reads as a
# departure from it.
comptime _HERO = 6  # OUT_BACK — the row the hero box starts on


def _curves() -> List[Easing]:
    return [
        Easing.LINEAR,
        Easing.IN_OUT_QUAD,
        Easing.OUT_CUBIC,
        Easing.IN_OUT_CUBIC,
        Easing.OUT_SINE,
        Easing.OUT_EXPO,
        Easing.OUT_BACK,
        Easing.OUT_ELASTIC,
        Easing.OUT_BOUNCE,
    ]


def _names() -> List[String]:
    return [
        "LINEAR",
        "IN_OUT_QUAD",
        "OUT_CUBIC",
        "IN_OUT_CUBIC",
        "OUT_SINE",
        "OUT_EXPO",
        "OUT_BACK",
        "OUT_ELASTIC",
        "OUT_BOUNCE",
    ]


@fieldwise_init
struct App(Program):
    var clock: Tween
    """One ping-ponging tween driving every gallery row.

    The rows differ only in which curve they bend `clock.progress` with, so a
    single playhead shows all nine curves against the same clock -- which is
    the comparison worth seeing. `ease` needs no state of its own, so nothing
    else has to be ticked.
    """

    var slide: Tween
    """The hero box's run, played once per keypress."""

    var curves: List[Easing]
    var names: List[String]
    var pick: Int

    @staticmethod
    def create(mut context: Context) raises -> App:
        # Authored against the 1280x800 passed to run(): x runs -640..640 and
        # y runs -400..400, with y growing *upward*, so the gallery counts
        # down from +170.
        var curves = _curves()

        # ping_pong rather than loop: progress runs back down on the return
        # leg, so each row travels its curve backwards instead of snapping to
        # the start.
        var clock = Tween(1.6)
        clock.ping_pong()

        # The 0-to-1 form. The hero's position comes from Point2D.lerp, which
        # takes exactly that fraction -- one scalar tween moves a point.
        var slide = Tween(0.9, curves[_HERO])
        slide.play()

        return App(
            clock=clock,
            slide=slide,
            curves=curves^,
            names=_names(),
            pick=_HERO,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # Nothing else advances a tween. A tween never updated sits at its
        # start forever, exactly like an un-ticked SpriteAnimator.
        self.clock.update(context.time.delta)
        self.slide.update(context.time.delta)

        if canvas.input.just_pressed("space"):
            self.pick = (self.pick + 1) % len(self.curves)
            self.slide.curve = self.curves[self.pick]
            self.slide.play()

        canvas.background(Color(18, 18, 24))

        # Tracks first, while outline is still enabled — the dots below turn it
        # off and a line rendered after that would not appear.
        canvas.outline(Color(44, 44, 58), thickness=3)
        canvas.line((-420.0, 300.0), (420.0, 300.0))
        for i in range(len(self.curves)):
            canvas.line((-360.0, self._row_y(i)), (580.0, self._row_y(i)))

        canvas.outline(enabled=False)

        # The hero: a point moved by lerping between two positions with the
        # tween's eased value. OUT_BACK and OUT_ELASTIC leave 0..1 mid-run, so
        # the box visibly overshoots both ends of its track.
        var pos = Point2D(-420.0, 300.0).lerp(
            Point2D(420.0, 300.0), self.slide.value
        )
        canvas.fill(Color(235, 120, 70))
        canvas.rectangle(pos, 44, 44)

        # One dot per curve, all reading the same progress.
        canvas.fill(Color(90, 170, 255))
        for i in range(len(self.curves)):
            var t = ease(self.curves[i], self.clock.progress)
            canvas.circle((lerp(-360.0, 580.0, t), self._row_y(i)), 11)

        canvas.text_color(Color(200, 200, 212))
        canvas.font_size(30)
        canvas.text_align(Align.TOP)
        canvas.text("Easing and Tweens", 0, 362)
        canvas.font_size(18)
        canvas.text(
            "space  cycles the hero curve: " + self.names[self.pick], 0, 238
        )

        canvas.font_size(18)
        canvas.text_align(Align.LEFT)
        for i in range(len(self.curves)):
            if i == self.pick:
                canvas.text_color(Color(235, 120, 70))
            else:
                canvas.text_color(Color(140, 140, 155))
            canvas.text(self.names[i], -614.0, self._row_y(i))

    def _row_y(self, i: Int) -> Float64:
        return 170.0 - Float64(i) * 66.0


def main() raises:
    run[App]("Easing and Tweens", width=1280, height=800)
