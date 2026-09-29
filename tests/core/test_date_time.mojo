from std.testing import TestSuite, assert_equal, assert_true
from create.core.date_time import DateTime


def test_now_reads_a_plausible_calendar() raises -> None:
    # A wrong struct tm offset or a missing 1900/1 correction lands outside
    # these ranges, so they catch layout bugs without pinning the date.
    var now = DateTime.now()
    assert_true(now.year >= 2026)
    assert_true(1 <= now.month <= 12)
    assert_true(1 <= now.day <= 31)
    assert_true(0 <= now.hour <= 23)
    assert_true(0 <= now.minute <= 59)
    assert_true(0 <= now.second <= 60)
    assert_true(0 <= now.millisecond <= 999)


def test_prints_in_keyword_form() raises -> None:
    var d = DateTime(
        year=2026,
        month=9,
        day=29,
        hour=14,
        minute=5,
        second=30,
        millisecond=250,
    )
    assert_equal(
        String(d),
        (
            "DateTime(year=2026, month=9, day=29, hour=14, minute=5,"
            " second=30, millisecond=250)"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
