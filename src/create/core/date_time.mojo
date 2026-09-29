"""Wall-clock date and time, read from libc: the Mojo standard library has no
calendar API, only monotonic counters.

`clock_gettime(CLOCK_REALTIME)` fills a `timespec`
`{ time_t tv_sec; long tv_nsec; }` (two 8-byte fields on 64-bit Linux and
macOS), and `localtime_r` breaks `tv_sec` into a `struct tm`, whose first six
fields are 4-byte `int`s: `tm_sec`, `tm_min`, `tm_hour`, `tm_mday`, `tm_mon`
(0-based), `tm_year` (years since 1900). The rest of `struct tm` differs by
platform but is never larger than 64 bytes, so a 16-int buffer covers it.
"""

from std.ffi import external_call

comptime _CLOCK_REALTIME: Int32 = 0
comptime _TM_INTS = 16
comptime _TM_SECOND = 0
comptime _TM_MINUTE = 1
comptime _TM_HOUR = 2
comptime _TM_DAY = 3
comptime _TM_MONTH = 4
comptime _TM_YEAR = 5


@fieldwise_init
struct DateTime(Copyable, ImplicitlyCopyable, Movable, Writable):
    """A calendar date and local time of day, read all at once.

    `DateTime.now()` takes one reading, so its fields always agree with each
    other: reading hour and minute from separate clock calls can straddle a
    rollover and report 13:59 at 12:59:59.999. Unlike `context.time`, this is
    the computer's clock, not the run's — it doesn't start at zero, and a
    headless run sees the real date.
    """

    var year: Int
    """The full year, such as 2026."""

    var month: Int
    """1 (January) to 12 (December)."""

    var day: Int
    """Day of the month, from 1."""

    var hour: Int
    """0 to 23."""

    var minute: Int
    """0 to 59."""

    var second: Int
    """0 to 59, or 60 during a leap second."""

    var millisecond: Int
    """0 to 999, for motion smoother than whole seconds."""

    @staticmethod
    def now() -> DateTime:
        """The current local date and time, in the system's time zone."""
        var timespec = Array[Int64, 2](fill=0)
        _ = external_call["clock_gettime", Int32](
            _CLOCK_REALTIME, timespec.unsafe_ptr()
        )
        var tm = Array[Int32, _TM_INTS](fill=0)
        _ = external_call["localtime_r", Int](
            timespec.unsafe_ptr(), tm.unsafe_ptr()
        )
        return DateTime(
            year=Int(tm[_TM_YEAR]) + 1900,
            month=Int(tm[_TM_MONTH]) + 1,
            day=Int(tm[_TM_DAY]),
            hour=Int(tm[_TM_HOUR]),
            minute=Int(tm[_TM_MINUTE]),
            second=Int(tm[_TM_SECOND]),
            millisecond=Int(timespec[1]) // 1_000_000,
        )

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "DateTime(year=",
            self.year,
            ", month=",
            self.month,
            ", day=",
            self.day,
            ", hour=",
            self.hour,
            ", minute=",
            self.minute,
            ", second=",
            self.second,
            ", millisecond=",
            self.millisecond,
            ")",
        )
