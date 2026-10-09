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

    def set(mut self, column: String, var value: String) raises:
        """Set the cell in the named column."""
        self._set(self._column_index(column), value^)

    def set(mut self, column: Int, var value: String) raises:
        """Set the cell in column `column`, from 0."""
        self._set(self._settable_index(column), value^)

    def set(mut self, column: String, value: Float64) raises:
        """Set the cell in the named column to a number."""
        self._set(self._column_index(column), String(value))

    def set(mut self, column: Int, value: Float64) raises:
        """Set the cell in column `column`, from 0, to a number."""
        self._set(self._settable_index(column), String(value))

    def set(mut self, column: String, value: Int) raises:
        """Set the cell in the named column to a whole number."""
        self._set(self._column_index(column), String(value))

    def set(mut self, column: Int, value: Int) raises:
        """Set the cell in column `column`, from 0, to a whole number."""
        self._set(self._settable_index(column), String(value))

    def _set(mut self, index: Int, var value: String):
        while len(self._cells) <= index:
            self._cells.append("")
        self._cells[index] = value^

    def _settable_index(self, column: Int) raises -> Int:
        var count = len(self._header[].names)
        if column < 0 or column >= count:
            raise Error(
                "no column "
                + String(column)
                + ": the table has "
                + String(count)
            )
        return column

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

    def __init__(out self, var columns: List[String]):
        """An empty table with these column names, to fill with `add_row`."""
        self._header = ArcPointer(_Header(columns^, True))
        self._rows = []

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

    def rows(ref self) -> Span[TableRow, origin_of(self._rows)]:
        """Every row, in order, by reference: `for ref row in t.rows()`.

        Rows can be edited through it but not added or removed; that is
        `add_row` and `remove_row`.
        """
        return Span(self._rows)

    def add_row(mut self) -> ref[self._rows[0]] TableRow:
        """Append an empty row and return it, to fill with `set`.

        ```mojo
        ref row = scores.add_row()
        row.set("name", "Ada")
        row.set("score", 120)
        ```
        """
        self._rows.append(TableRow([], self._header))
        return self._rows[len(self._rows) - 1]

    def add_row(mut self, var cells: List[String]) raises:
        """Append a row of cells, one per column in order.

        A table with a header takes exactly one cell per column; one without
        grows to fit a longer row.
        """
        var header = self._header[].copy()
        if header.named and len(cells) != len(header.names):
            raise Error(
                "a row of "
                + String(len(cells))
                + " cells for "
                + String(len(header.names))
                + " columns"
            )
        if len(cells) > len(header.names):
            header.names.resize(len(cells), "")
            self._replace_header(header^)
        self._rows.append(TableRow(cells^, self._header))

    def add_column(mut self, name: String) raises:
        """Append a column, empty in every row."""
        var header = self._header[].copy()
        if not header.named:
            raise Error(
                'cannot add column "'
                + name
                + '": the table has no header to name it in'
            )
        if name in header.names:
            raise Error('column "' + name + '" already exists')
        header.names.append(name)
        self._replace_header(header^)

    def remove_row(mut self, index: Int) raises:
        """Remove row `index`; the rows after it move up by one."""
        if index < 0 or index >= len(self._rows):
            raise Error(
                "no row "
                + String(index)
                + ": the table has "
                + String(len(self._rows))
            )
        _ = self._rows.pop(index)

    def save(self, path: String, separator: String = "") raises:
        """Write the table as CSV or TSV, the header line first.

        The separator follows `load`'s rule. A field is quoted only when it
        holds the separator, a quote or a line break, so a file `load` read
        is written back as it was.
        """
        var chosen = separator
        if chosen == "":
            chosen = "\t" if _is_tsv(path) else ","
        var text = self._format(chosen)
        with open(path, "w") as f:
            f.write(text)

    def _format(self, separator: String) raises -> String:
        if separator.byte_length() != 1:
            raise Error(
                'separator must be a single character, not "' + separator + '"'
            )
        var out = String()
        var width = len(self._header[].names)
        if self._header[].named:
            _write_record(out, self._header[].names, width, separator)
        for ref row in self._rows:
            _write_record(out, row._cells, width, separator)
        return out^

    def _replace_header(mut self, var header: _Header):
        """Point the table and every row at a new header.

        A header is never edited in place: a copied table shares it.
        """
        self._header = ArcPointer(header^)
        for ref row in self._rows:
            row._header = self._header


def _write_record(
    mut out: String, cells: List[String], width: Int, separator: String
):
    """Append one record, padded to `width` cells, and a line break.

    A lone empty field is quoted, or the line would read back as blank and
    be skipped.
    """
    var count = max(width, len(cells))
    if count == 1 and (len(cells) == 0 or cells[0] == ""):
        out += '""\n'
        return
    for i in range(count):
        if i > 0:
            out += separator
        if i < len(cells):
            out += _quoted_if_needed(cells[i], separator)
    out += "\n"


def _quoted_if_needed(field: String, separator: String) -> String:
    if separator in field or '"' in field or "\n" in field or "\r" in field:
        return '"' + field.replace('"', '""') + '"'
    return field


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
