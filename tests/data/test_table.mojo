from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from create.data import Table
from create.data.table import _parse_delimited

comptime FIXTURES = "tests/fixtures/data/"


def test_load_reads_header_and_rows() raises -> None:
    var t = Table.load(FIXTURES + "scores.csv")
    assert_equal(t.row_count(), 3)
    assert_equal(t.column_count(), 3)
    assert_equal(t.columns(), ["name", "score", "level"])
    assert_equal(t.row(0).string("name"), "Ada")
    assert_equal(t.row(2).string("level"), "4")


def test_typed_reads_parse_the_cell() raises -> None:
    var t = Table.load(FIXTURES + "scores.csv")
    assert_equal(t.row(0).int("score"), 120)
    assert_equal(t.row(1).float("score"), 95.0)
    assert_equal(t.row(1).int(2), 2)
    assert_equal(t.row(0).string(0), "Ada")


def test_rows_iterate_by_reference() raises -> None:
    var t = Table.load(FIXTURES + "scores.csv")
    var total = 0
    for ref row in t.rows():
        total += row.int("score")
    assert_equal(total, 310)


def test_tsv_separator_comes_from_the_extension() raises -> None:
    var t = Table.load(FIXTURES + "scores.tsv")
    assert_equal(t.column_count(), 3)
    assert_equal(t.row(1).string("name"), "Bob")


def test_separator_can_be_named() raises -> None:
    var t = Table.parse("a;b\n1;2\n", separator=";")
    assert_equal(t.row(0).int("b"), 2)


def test_quoted_fields_keep_separators_quotes_and_newlines() raises -> None:
    var t = Table.load(FIXTURES + "quoted.csv")
    assert_equal(t.columns(), ["name", "quote", "note"])  # BOM stripped
    assert_equal(t.row_count(), 3)  # blank line skipped
    assert_equal(t.row(0).string("name"), "Smith, Jo")
    assert_equal(t.row(0).string("quote"), 'She said "hi"')
    assert_equal(t.row(0).string("note"), "line one\nline two")


def test_empty_fields_are_kept() raises -> None:
    var t = Table.load(FIXTURES + "quoted.csv")
    assert_equal(t.row(1).string("name"), "Plain")
    assert_equal(t.row(1).string("quote"), "")
    assert_equal(t.row(1).string("note"), "")
    assert_equal(t.row(2).string("name"), "")
    assert_equal(t.row(2).string("quote"), "x")
    assert_equal(t.row(2).string("note"), "")


def test_trailing_separator_is_an_empty_last_field() raises -> None:
    var records = _parse_delimited("a,b,\n,x\n", ",", "<test>")
    assert_equal(len(records), 2)
    assert_equal(records[0], ["a", "b", ""])
    assert_equal(records[1], ["", "x"])


def test_quote_inside_an_unquoted_field_is_literal() raises -> None:
    var t = Table.parse('size\n5" screen\n')
    assert_equal(t.row(0).string("size"), '5" screen')


def test_short_row_reads_missing_cells_as_empty() raises -> None:
    var t = Table.parse("a,b,c\n1\n")
    assert_equal(t.row(0).string("c"), "")


def test_no_header_reads_every_line_as_a_row() raises -> None:
    var t = Table.load(FIXTURES + "scores.csv", header=False)
    assert_equal(t.row_count(), 4)
    assert_equal(t.column_count(), 3)
    assert_equal(len(t.columns()), 0)
    assert_false(t.has_column("name"))
    assert_equal(t.row(0).string(0), "name")
    with assert_raises(contains="no header"):
        _ = t.row(0).string("name")


def test_has_column() raises -> None:
    var t = Table.load(FIXTURES + "scores.csv")
    assert_true(t.has_column("score"))
    assert_false(t.has_column("time"))


def test_unterminated_quote_names_where_it_opened() raises -> None:
    with assert_raises(contains="bad_quote.csv:2:5: unterminated quote"):
        _ = Table.load(FIXTURES + "bad_quote.csv")


def test_text_after_a_closing_quote_raises() raises -> None:
    with assert_raises(contains="<input>:2:4: expected a separator"):
        _ = Table.parse('a\n"x"y\n')


def test_missing_column_raises_naming_it() raises -> None:
    var t = Table.load(FIXTURES + "scores.csv")
    with assert_raises(contains='no column "time"'):
        _ = t.row(0).string("time")
    with assert_raises(contains="no column 3"):
        _ = t.row(0).string(3)


def test_non_number_raises_with_the_cell() raises -> None:
    var t = Table.load(FIXTURES + "scores.csv")
    with assert_raises(contains='holds "Ada", not a number'):
        _ = t.row(0).float("name")
    with assert_raises(contains="not a whole number"):
        _ = Table.parse("x\n1.5\n").row(0).int("x")


def test_separator_must_be_one_character() raises -> None:
    with assert_raises(contains="single character"):
        _ = Table.parse("a\n", separator="::")


def test_root_preamble_reaches_table() raises -> None:
    from create import Table as RootTable

    assert_equal(RootTable.parse("a\n1\n").row_count(), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
