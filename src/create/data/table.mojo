from std.memory import ArcPointer


@fieldwise_init
struct _Header(Copyable, Movable):
    """A table's column names, shared by the table and every row.

    `named` is False for a table loaded with `header=False`: its columns are
    reached by index only, and `names` holds one empty string per column.
    """

    var names: List[String]
    var named: Bool


struct TableRow(Copyable, Movable):
    """One row of a `Table`, its cells reached by column name or index.

    Cells are kept as the text the file held and parsed on read, so a row
    loads and saves without losing anything. A row shorter than the table
    reads its missing cells as empty.

    ```mojo
    for ref row in scores.rows():
        canvas.text(row.string("name"), (0, y))
        var points = row.float("score")
    ```
    """

    var _cells: List[String]
    var _header: ArcPointer[_Header]

    def __init__(
        out self, var cells: List[String], header: ArcPointer[_Header]
    ):
        self._cells = cells^
        self._header = header

    def string(self, column: String) raises -> String:
        """The cell in the named column, as written."""
        return self._cell(self._column_index(column))

    def string(self, column: Int) raises -> String:
        """The cell in column `column`, from 0, as written."""
        return self._cell(self._checked_index(column))

    def float(self, column: String) raises -> Float64:
        """The cell in the named column, parsed as a number."""
        return self._float(self._column_index(column), column)

    def float(self, column: Int) raises -> Float64:
        """The cell in column `column`, from 0, parsed as a number."""
        return self._float(self._checked_index(column), String(column))

    def int(self, column: String) raises -> Int:
        """The cell in the named column, parsed as a whole number."""
        return self._int(self._column_index(column), column)

    def int(self, column: Int) raises -> Int:
        """The cell in column `column`, from 0, parsed as a whole number."""
        return self._int(self._checked_index(column), String(column))

    def _cell(self, index: Int) -> String:
        if index < len(self._cells):
            return self._cells[index]
        return ""

    def _column_index(self, column: String) raises -> Int:
        ref header = self._header[]
        if not header.named:
            raise Error(
                'no column "'
                + column
                + '": the table has no header, reach columns by index'
            )
        for i in range(len(header.names)):
            if header.names[i] == column:
                return i
        raise Error('no column "' + column + '"')

    def _checked_index(self, column: Int) raises -> Int:
        var count = max(len(self._header[].names), len(self._cells))
        if column < 0 or column >= count:
            raise Error(
                "no column "
                + String(column)
                + ": the table has "
                + String(count)
            )
        return column

    def _float(self, index: Int, column: String) raises -> Float64:
        var text = self._cell(index)
        try:
            return atof(text.strip())
        except:
            raise Error(
                'column "' + column + '" holds "' + text + '", not a number'
            )

    def _int(self, index: Int, column: String) raises -> Int:
        var text = self._cell(index)
        try:
            return Int(String(text.strip()))
        except:
            raise Error(
                'column "'
                + column
                + '" holds "'
                + text
                + '", not a whole number'
            )


struct Table(Copyable, Movable):
    """Rows of text cells read from CSV or TSV, like Processing's `Table`.

    The first line names the columns unless loaded with `header=False`.
    Rows are handed out by reference, so reading a cell copies nothing:

    ```mojo
    var scores = Table.load(source_path("scores.csv"))
    var best = scores.row(0).string("name")
    for ref row in scores.rows():
        total += row.int("score")
    ```
    """

    var _header: ArcPointer[_Header]
    var _rows: List[TableRow]

    def __init__(out self, *, var _records: List[List[String]], header: Bool):
        var records = _records^
        var names: List[String]
        var start = 0
        if header and len(records) > 0:
            names = records[0].copy()
            start = 1
        else:
            var width = 0
            for record in records:
                width = max(width, len(record))
            names = List[String](length=width, fill="")
        self._header = ArcPointer(_Header(names^, header))
        self._rows = List[TableRow](capacity=len(records) - start)
        for i in range(start, len(records)):
            self._rows.append(TableRow(records[i].copy(), self._header))

    @staticmethod
    def load(
        path: String, header: Bool = True, separator: String = ""
    ) raises -> Table:
        """Load a CSV or TSV file.

        The separator is a tab for a `.tsv` file and a comma otherwise,
        unless `separator` names one. Quoted fields may hold separators,
        newlines and doubled quotes, as RFC 4180 has it.
        """
        var text: String
        with open(path, "r") as f:
            text = f.read()
        var chosen = separator
        if chosen == "":
            chosen = "\t" if _is_tsv(path) else ","
        return Table(
            _records=_parse_delimited(text, chosen, path), header=header
        )

    @staticmethod
    def parse(
        text: String, header: Bool = True, separator: String = ","
    ) raises -> Table:
        """Parse CSV or TSV text already in memory."""
        return Table(
            _records=_parse_delimited(text, separator, "<input>"),
            header=header,
        )

    def row_count(self) -> Int:
        """The number of rows, the header line not counted."""
        return len(self._rows)

    def column_count(self) -> Int:
        """The number of columns: the header's, or the widest row's."""
        return len(self._header[].names)

    def columns(self) -> List[String]:
        """The column names, or an empty list for a table with no header."""
        if not self._header[].named:
            return []
        return self._header[].names.copy()

    def has_column(self, name: String) -> Bool:
        """Whether a column has this name."""
        return self._header[].named and name in self._header[].names

    def row(ref self, index: Int) -> ref[self._rows[0]] TableRow:
        """Row `index`, from 0 to `row_count() - 1`, by reference."""
        return self._rows[index]

    def rows(ref self) -> ref[self._rows] List[TableRow]:
        """Every row, in order, by reference: `for ref row in t.rows()`."""
        return self._rows


def _is_tsv(path: String) -> Bool:
    var lowered = path.lower()
    return lowered.endswith(".tsv") or lowered.endswith(".tab")


def _parse_delimited(
    text: String, separator: String, source: String
) raises -> List[List[String]]:
    """Split delimited text into records of fields.

    Blank lines are skipped. A field opening with a quote runs to the
    matching quote, taking separators and newlines literally and `""` as
    one quote; a quote anywhere else is an ordinary character. Errors name
    `source:line:column`.
    """
    if separator.byte_length() != 1:
        raise Error(
            'separator must be a single character, not "' + separator + '"'
        )
    var sep = separator.as_bytes()[0]
    comptime QUOTE = UInt8(ord('"'))
    comptime NEWLINE = UInt8(ord("\n"))
    comptime RETURN = UInt8(ord("\r"))

    var bytes = text.as_bytes()
    var n = len(bytes)
    var i = 0
    if n >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
        i = 3

    var records = List[List[String]]()
    var record = List[String]()
    var field = List[UInt8]()
    var line = 1
    var line_start = i

    while i < n:
        var at_field_start = len(field) == 0
        var c = bytes[i]
        if c == QUOTE and at_field_start:
            var open_line = line
            var open_column = i - line_start + 1
            i += 1
            while True:
                if i >= n:
                    raise Error(
                        source
                        + ":"
                        + String(open_line)
                        + ":"
                        + String(open_column)
                        + ": unterminated quote"
                    )
                var q = bytes[i]
                if q == QUOTE:
                    if i + 1 < n and bytes[i + 1] == QUOTE:
                        field.append(QUOTE)
                        i += 2
                        continue
                    i += 1
                    break
                if q == NEWLINE:
                    line += 1
                    line_start = i + 1
                field.append(q)
                i += 1
            if (
                i < n
                and bytes[i] != sep
                and bytes[i] != NEWLINE
                and bytes[i] != RETURN
            ):
                raise Error(
                    source
                    + ":"
                    + String(line)
                    + ":"
                    + String(i - line_start + 1)
                    + ": expected a separator after the closing quote"
                )
            # A quoted empty field must still count as a field.
            record.append(String(unsafe_from_utf8=field))
            field.clear()
            if i < n and bytes[i] == sep:
                i += 1
                if i >= n or bytes[i] == NEWLINE or bytes[i] == RETURN:
                    record.append("")
            continue
        if c == sep:
            record.append(String(unsafe_from_utf8=field))
            field.clear()
            i += 1
            if i >= n or bytes[i] == NEWLINE or bytes[i] == RETURN:
                record.append("")
            continue
        if c == NEWLINE or c == RETURN:
            if len(field) > 0:
                record.append(String(unsafe_from_utf8=field))
                field.clear()
            if len(record) > 0:
                records.append(record^)
                record = List[String]()
            i += 1
            if c == RETURN and i < n and bytes[i] == NEWLINE:
                i += 1
            line += 1
            line_start = i
            continue
        field.append(c)
        i += 1

    if len(field) > 0:
        record.append(String(unsafe_from_utf8=field))
    if len(record) > 0:
        records.append(record^)
    return records^
