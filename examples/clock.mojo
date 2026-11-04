"""A clock: the computer's time, as hands and as text.

`DateTime.now()` is read once a frame, so every hand and digit shows the
same instant. The face is made of `Line`s, and the seconds sweep round it as
an `Arc`. Beside it, the time in a bold weight and the date in italic;
digits are narrower and wider in the packaged font, so each is centred in a
cell as wide as the widest, measured with `text_width`, and the time does
not shift as it ticks.
"""

from create import *

comptime _BACKGROUND = Color(40, 42, 56)
comptime _FACE = Color(30, 32, 42)
comptime _TRACK = Color(62, 64, 82)
comptime _HAND = Color(200, 200, 212)
comptime _SECONDS = Color(235, 120, 70)
comptime _HINT = Color(150, 160, 180)

comptime _CENTER = Point2D(-230.0, 0.0)
comptime _RADIUS = 200.0
comptime _TEXT_X = 260.0


def _day_names() -> List[String]:
    return [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
    ]


def _month_names() -> List[String]:
    return [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December",
    ]


def _weekday(year: Int, month: Int, day: Int) -> Int:
    """0 for Sunday to 6 for Saturday (Sakamoto's method)."""
    var offsets: List[Int] = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    var y = year - 1 if month < 3 else year
    return (y + y // 4 - y // 100 + y // 400 + offsets[month - 1] + day) % 7


def _clock_angle(fraction: Float64) -> Float64:
    """How far round the face `fraction` of a turn is, as an angle: from
    the top, clockwise. Angles count counter-clockwise from +x, y up."""
    return PI / 2.0 - TAU * fraction


def _hand(fraction: Float64, length: Float64) -> Line:
    var angle = _clock_angle(fraction)
    return Line(_CENTER, _CENTER + Vector2D.from_angle(angle, length))


def _two_digits(value: Int) -> String:
    return String("0", value) if value < 10 else String(value)


@fieldwise_init
struct Clock(Program):
    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Clock:
        return Clock()

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var now = DateTime.now()
        var seconds = Float64(now.second) + Float64(now.millisecond) / 1000.0
        var minutes = Float64(now.minute) + seconds / 60.0
        var hours = Float64(now.hour % 12) + minutes / 60.0

        canvas.background(_BACKGROUND)

        with canvas.style(fill=_FACE, outline_enabled=False):
            canvas.circle(_CENTER, _RADIUS)

        # The seconds ring: a full track, and an arc swept clockwise (a
        # negative sweep, since y is up) from the top.
        with canvas.style(outline=_TRACK, outline_thickness=8):
            canvas.arc(_CENTER, _RADIUS + 16.0, 0.0, TAU)
        with canvas.style(outline=_SECONDS, outline_thickness=8):
            canvas.arc(_CENTER, _RADIUS + 16.0, PI / 2.0, -TAU * seconds / 60.0)

        # Sixty ticks, every fifth longer and heavier: the hours.
        for i in range(60):
            var hour_mark = i % 5 == 0
            var direction = Vector2D.from_angle(_clock_angle(Float64(i) / 60))
            var inner = _RADIUS * (0.82 if hour_mark else 0.9)
            with canvas.style(
                outline=_HAND if hour_mark else _TRACK,
                outline_thickness=6 if hour_mark else 2,
            ):
                canvas.draw(
                    Line(
                        _CENTER + direction * inner,
                        _CENTER + direction * (_RADIUS * 0.95),
                    )
                )

        with canvas.style(outline=_HAND, outline_thickness=10):
            canvas.draw(_hand(hours / 12.0, _RADIUS * 0.5))
        with canvas.style(outline=_HAND, outline_thickness=6):
            canvas.draw(_hand(minutes / 60.0, _RADIUS * 0.75))
        with canvas.style(outline=_SECONDS, outline_thickness=2):
            canvas.draw(_hand(seconds / 60.0, _RADIUS * 0.85))
        with canvas.style(fill=_SECONDS, outline_enabled=False):
            canvas.circle(_CENTER, 8)

        # The time, bold, in cells as wide as the widest digit.
        var time = String(
            _two_digits(now.hour),
            ":",
            _two_digits(now.minute),
            ":",
            _two_digits(now.second),
        )
        with canvas.style(
            text_color=_HAND, font_size=84, font_weight=FontWeight.BOLD
        ):
            var cell = 0.0
            for digit in range(10):
                cell = max(cell, canvas.text_width(String(digit)))
            var colon = canvas.text_width(":")
            var widths = List[Float64]()
            var total = 0.0
            for character in time.codepoint_slices():
                var width = colon if character == ":" else cell
                widths.append(width)
                total += width
            var x = _TEXT_X - total / 2.0
            var i = 0
            for character in time.codepoint_slices():
                canvas.text(String(character), (x + widths[i] / 2.0, 40.0))
                x += widths[i]
                i += 1

        var date = String(
            _day_names()[_weekday(now.year, now.month, now.day)],
            " ",
            now.day,
            " ",
            _month_names()[now.month - 1],
            " ",
            now.year,
        )
        with canvas.style(text_color=_HAND, font_size=28, font_italic=True):
            canvas.text(date, (_TEXT_X, -30.0))
        with canvas.style(
            text_color=_HINT, font_size=18, font_weight=FontWeight.LIGHT
        ):
            canvas.text("DateTime.now(), read once a frame", (_TEXT_X, -80.0))


def main() raises:
    run[Clock]("Clock", width=1000, height=600)
