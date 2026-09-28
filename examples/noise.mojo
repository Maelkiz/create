from create import *

comptime _COLUMNS = 80
comptime _ROWS = 60


@fieldwise_init
struct App(Program):
    var terrain: Noise
    """The animated field behind everything, one sample per grid cell.

    Its feature size is in world units, so hills stay about 150 across however
    finely the grid samples them; the time passed to `at` is scaled at the
    call instead, which sets how fast the field evolves.
    """

    var wobble: Noise
    """A 1D field read with the elapsed time: the circle's x position. Its
    feature size is in seconds, so the circle changes course about every
    two."""

    @staticmethod
    def create(mut context: Context) raises -> App:
        return App(
            terrain=Noise(7, feature_size=150),
            wobble=Noise(3, feature_size=2),
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(18, 18, 24))
        var t = context.time.elapsed

        # A grid of cells shaded from deep water to pale grass. Anchored to the
        # edge methods, so the field fills whatever the canvas reports.
        var cell_w = (canvas.right() - canvas.left()) / Float64(_COLUMNS)
        var cell_h = (canvas.top() - canvas.bottom()) / Float64(_ROWS)
        var low = Color(20, 40, 110)
        var high = Color(200, 230, 150)
        canvas.outline_enabled(False)
        for column in range(_COLUMNS):
            for row in range(_ROWS):
                var center = Point2D(
                    canvas.left() + (Float64(column) + 0.5) * cell_w,
                    canvas.bottom() + (Float64(row) + 0.5) * cell_h,
                )
                var height = self.terrain.at(center, time=t * 0.3)
                # Layered octaves average towards 0.5, so stretch the middle
                # of the range across the whole gradient.
                canvas.fill(Color.lerp(low, high, smoothstep(0.3, 0.7, height)))
                canvas.rectangle(center, cell_w, cell_h)

        # The same range as Random.float(), so lerp turns it into a position.
        var x = lerp(canvas.left() + 40, canvas.right() - 40, self.wobble.at(t))
        canvas.fill(Color(235, 120, 70))
        canvas.outline(Color.WHITE, thickness=3)
        canvas.circle((x, 0), 24)

        canvas.text_color(Color.WHITE)
        canvas.font_size(16)
        canvas.text_align(Align.BOTTOM_LEFT)
        canvas.text(
            String(self.terrain), (canvas.left() + 12, canvas.bottom() + 12)
        )


def main() raises:
    run[App]("Noise", width=800, height=600)
