from std.math import isinf, isnan
from std.memory import ArcPointer


struct JSONKind(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """Which of JSON's six kinds of value a `JSON` holds."""

    var value: Int

    comptime NULL = JSONKind(0)
    comptime BOOL = JSONKind(1)
    comptime NUMBER = JSONKind(2)
    comptime STRING = JSONKind(3)
    comptime ARRAY = JSONKind(4)
    comptime OBJECT = JSONKind(5)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: JSONKind) -> Bool:
        return self.value == other.value

    def __ne__(self, other: JSONKind) -> Bool:
        return self.value != other.value

    def write_to[W: Writer](self, mut writer: W):
        if self == JSONKind.NULL:
            writer.write("JSONKind.NULL")
        elif self == JSONKind.BOOL:
            writer.write("JSONKind.BOOL")
        elif self == JSONKind.NUMBER:
            writer.write("JSONKind.NUMBER")
        elif self == JSONKind.STRING:
            writer.write("JSONKind.STRING")
        elif self == JSONKind.ARRAY:
            writer.write("JSONKind.ARRAY")
        elif self == JSONKind.OBJECT:
            writer.write("JSONKind.OBJECT")
        else:
            writer.write("JSONKind(", self.value, ")")

    def _name(self) -> String:
        """The kind as a sentence names it: "a number", "an object"."""
        if self == JSONKind.NULL:
            return "null"
        if self == JSONKind.BOOL:
            return "a bool"
        if self == JSONKind.NUMBER:
            return "a number"
        if self == JSONKind.STRING:
            return "a string"
        if self == JSONKind.ARRAY:
            return "an array"
        return "an object"


@fieldwise_init
struct _Node(Copyable, Movable):
    """One value in a document. Children are indices into the same document.

    A number keeps `integer` exact when it was written without a fraction
    or exponent and fits an `Int`; `number` always holds it as a float.
    `flag` is a bool's value; `text` a string's.
    """

    var kind: JSONKind
    var flag: Bool
    var number: Float64
    var integer: Int
    var integral: Bool
    var text: String
    var keys: List[String]
    var children: List[Int]

    @staticmethod
    def scalar(kind: JSONKind) -> _Node:
        return _Node(kind, False, 0.0, 0, False, "", [], [])


struct _Document(Movable):
    """Every node of one JSON document, in one list.

    Mojo can't nest a struct in itself, so a value's children are indices
    into this list rather than values it holds.
    """

    var nodes: List[_Node]

    def __init__(out self, var nodes: List[_Node]):
        self.nodes = nodes^


struct JSON(Copyable, Movable, Sized, Writable):
    """A JSON value: an object, array, string, number, bool or null.

    Loaded or parsed, a document is read through `[]` by key or index, and
    each step hands back a handle into the same document, so reading a
    nested value copies nothing:

    ```mojo
    var config = JSON.load(source_path("config.json"))
    var speed = config["player"]["speed"].float()
    for enemy in config["enemies"].items():
        canvas.text(enemy["name"].string(), (0, y))
    ```

    A handle edits the document it points into, nested assignment and
    loops included, so a value read from a document **aliases** it, as in
    Processing, JavaScript and Python. `copy()` gives an independent one:

    ```mojo
    config["player"]["speed"] = 3.0
    for enemy in config["enemies"].items():
        enemy["hp"] = enemy["hp"].int() - 1
    var player = config["player"]          # still part of config
    var snapshot = config.copy()           # a document of its own
    ```

    Assigning a value copies it in, so a value set under two keys is two
    values. Prints as compact JSON text.
    """

    var _document: ArcPointer[_Document]
    var _index: Int

    def __init__(out self, *, _document: ArcPointer[_Document], _index: Int):
        self._document = _document
        self._index = _index

    def __init__(out self, *, var _node: _Node):
        self._document = ArcPointer(_Document([_node^]))
        self._index = 0

    @implicit
    def __init__(out self, value: Float64):
        """A number."""
        var node = _Node.scalar(JSONKind.NUMBER)
        node.number = value
        self = JSON(_node=node^)

    @implicit
    def __init__(out self, value: Int):
        """A whole number, kept exact."""
        var node = _Node.scalar(JSONKind.NUMBER)
        node.number = Float64(value)
        node.integer = value
        node.integral = True
        self = JSON(_node=node^)

    @implicit
    def __init__(out self, value: String):
        """A string."""
        var node = _Node.scalar(JSONKind.STRING)
        node.text = value
        self = JSON(_node=node^)

    @implicit
    def __init__(out self, value: Bool):
        """A bool."""
        var node = _Node.scalar(JSONKind.BOOL)
        node.flag = value
        self = JSON(_node=node^)

    def __init__(out self, *, copy: Self):
        """A deep copy: a document of its own holding only this value."""
        var nodes = List[_Node]()
        _ = _extract(copy._document[].nodes, copy._index, nodes)
        self._document = ArcPointer(_Document(nodes^))
        self._index = 0

    @staticmethod
    def object() -> JSON:
        """An empty object, to fill with `json[key] = value`."""
        return JSON(_node=_Node.scalar(JSONKind.OBJECT))

    @staticmethod
    def array() -> JSON:
        """An empty array, to fill with `append`."""
        return JSON(_node=_Node.scalar(JSONKind.ARRAY))

    @staticmethod
    def null() -> JSON:
        """`null`."""
        return JSON(_node=_Node.scalar(JSONKind.NULL))

    @staticmethod
    def load(path: String) raises -> JSON:
        """Load a JSON file. Errors name `path:line:column`."""
        var text: String
        with open(path, "r") as f:
            text = f.read()
        return _parse(text, path)

    @staticmethod
    def parse(text: String) raises -> JSON:
        """Parse JSON text already in memory."""
        return _parse(text, "<input>")

    def kind(self) -> JSONKind:
        """Which kind of value this is."""
        return self._node().kind

    def is_null(self) -> Bool:
        """Whether this is `null`."""
        return self.kind() == JSONKind.NULL

    def __len__(self) -> Int:
        """The number of an object's keys or an array's items; 0 otherwise."""
        return len(self._node().children)

    def __contains__(self, key: String) -> Bool:
        """Whether this is an object with `key`."""
        return key in self._node().keys

    def __getitem__(self, key: String) raises -> JSON:
        """The value under `key` in an object; raises if there is none."""
        ref node = self._expect(JSONKind.OBJECT, '["' + key + '"]')
        for i in range(len(node.keys)):
            if node.keys[i] == key:
                return self._at(node.children[i])
        raise Error('no key "' + key + '"')

    def __getitem__(self, index: Int) raises -> JSON:
        """Item `index` of an array, from 0; raises if out of range."""
        ref node = self._expect(JSONKind.ARRAY, "[" + String(index) + "]")
        if index < 0 or index >= len(node.children):
            raise Error(
                "no item "
                + String(index)
                + ": the array has "
                + String(len(node.children))
            )
        return self._at(node.children[index])

    def __setitem__(self, key: String, value: JSON) raises:
        """Set `key` in an object to a copy of `value`, adding the key last
        if it is new."""
        ref node = self._expect(JSONKind.OBJECT, '["' + key + '"] =')
        var slot = -1
        for i in range(len(node.keys)):
            if node.keys[i] == key:
                slot = i
        if slot >= 0 and self._is_node(value, node.children[slot]):
            return  # the write-back of a nested assignment
        var child = self._graft(value)
        ref target = self._node()  # the graft may have moved the nodes
        if slot >= 0:
            target.children[slot] = child
        else:
            target.keys.append(key)
            target.children.append(child)

    def __setitem__(self, index: Int, value: JSON) raises:
        """Set item `index` of an array to a copy of `value`."""
        ref node = self._expect(JSONKind.ARRAY, "[" + String(index) + "] =")
        if index < 0 or index >= len(node.children):
            raise Error(
                "no item "
                + String(index)
                + ": the array has "
                + String(len(node.children))
            )
        if self._is_node(value, node.children[index]):
            return  # the write-back of a nested assignment
        var child = self._graft(value)
        self._node().children[index] = child

    def get(self, key: String, default: JSON) raises -> JSON:
        """The value under `key` in an object, or `default` if it has none."""
        ref node = self._expect(JSONKind.OBJECT, ".get()")
        for i in range(len(node.keys)):
            if node.keys[i] == key:
                return self._at(node.children[i])
        return default.copy()

    def append(self, value: JSON) raises:
        """Add a copy of `value` to the end of an array."""
        _ = self._expect(JSONKind.ARRAY, ".append()")
        var child = self._graft(value)
        self._node().children.append(child)

    def remove(self, key: String) raises:
        """Remove `key` from an object; raises if it has none."""
        ref node = self._expect(JSONKind.OBJECT, ".remove()")
        for i in range(len(node.keys)):
            if node.keys[i] == key:
                _ = node.keys.pop(i)
                _ = node.children.pop(i)
                return
        raise Error('no key "' + key + '"')

    def remove(self, index: Int) raises:
        """Remove item `index` from an array; later items move up by one."""
        ref node = self._expect(JSONKind.ARRAY, ".remove()")
        if index < 0 or index >= len(node.children):
            raise Error(
                "no item "
                + String(index)
                + ": the array has "
                + String(len(node.children))
            )
        _ = node.children.pop(index)

    def keys(self) raises -> List[String]:
        """An object's keys, in the order the document has them."""
        return self._expect(JSONKind.OBJECT, ".keys()").keys.copy()

    def items(self) raises -> List[JSON]:
        """An array's items, or an object's values, in order.

        Each is a handle into this document, like `[]`'s.
        """
        ref node = self._node()
        if node.kind != JSONKind.ARRAY and node.kind != JSONKind.OBJECT:
            raise Error(
                ".items() needs an array or an object, not " + node.kind._name()
            )
        var items = List[JSON](capacity=len(node.children))
        for child in node.children:
            items.append(self._at(child))
        return items^

    def float(self) raises -> Float64:
        """A number, as a float."""
        return self._expect(JSONKind.NUMBER, ".float()").number

    def int(self) raises -> Int:
        """A whole number. Raises for one with a fraction, like `1.5`.

        A number written without a fraction or exponent is read exactly,
        all 64 bits; `3.0` and `3e2` are whole too.
        """
        ref node = self._expect(JSONKind.NUMBER, ".int()")
        if node.integral:
            return node.integer
        var number = node.number
        # 2^63 is exactly representable; every whole float below it fits.
        if (
            number == number.__floor__()
            and abs(number) < 9.223372036854775808e18
        ):
            return Int(number)
        raise Error(String(".int() on ", number, ", not a whole number"))

    def string(self) raises -> String:
        """A string's text."""
        return self._expect(JSONKind.STRING, ".string()").text

    def bool(self) raises -> Bool:
        """A bool's value."""
        return self._expect(JSONKind.BOOL, ".bool()").flag

    def write_to[W: Writer](self, mut writer: W):
        _write_value(writer, self._document[].nodes, self._index)

    def _node(self) -> ref[self._document[].nodes[0]] _Node:
        return self._document[].nodes[self._index]

    def _is_node(self, value: JSON, index: Int) -> Bool:
        """Whether `value` is the node at `index` of this document."""
        return value._document is self._document and value._index == index

    def _graft(self, value: JSON) -> Int:
        """Copy `value`'s subtree onto the end of this document; return the
        index of its root.

        Extracted first, so a value from this same document is read whole
        before the list it lives in grows.
        """
        var subtree = List[_Node]()
        _ = _extract(value._document[].nodes, value._index, subtree)
        ref nodes = self._document[].nodes
        var offset = len(nodes)
        for ref node in subtree:
            for ref child in node.children:
                child += offset
        nodes.extend(subtree^)
        return offset

    def _at(self, index: Int) -> JSON:
        return JSON(_document=self._document, _index=index)

    def _expect(
        self, kind: JSONKind, access: String
    ) raises -> ref[self._document[].nodes[0]] _Node:
        ref node = self._node()
        if node.kind != kind:
            raise Error(
                access + " needs " + kind._name() + ", not " + node.kind._name()
            )
        return node


comptime _MAX_DEPTH = 512
"""Deepest nesting `parse` takes, so hostile input raises, not overflows."""


struct _Parser:
    var bytes: List[UInt8]
    var position: Int
    var source: String
    var nodes: List[_Node]

    def __init__(out self, text: String, source: String):
        self.bytes = List[UInt8](text.as_bytes())
        self.position = 0
        self.source = source
        self.nodes = []
        if (
            len(self.bytes) >= 3
            and self.bytes[0] == 0xEF
            and self.bytes[1] == 0xBB
            and self.bytes[2] == 0xBF
        ):
            self.position = 3

    def fail(self, message: String) -> Error:
        """An error naming where the parser stands, as `source:line:column`."""
        var line = 1
        var line_start = 0
        for i in range(min(self.position, len(self.bytes))):
            if self.bytes[i] == UInt8(ord("\n")):
                line += 1
                line_start = i + 1
        return Error(
            self.source
            + ":"
            + String(line)
            + ":"
            + String(self.position - line_start + 1)
            + ": "
            + message
        )

    def at_end(self) -> Bool:
        return self.position >= len(self.bytes)

    def peek(self) -> UInt8:
        return self.bytes[self.position]

    def skip_whitespace(mut self):
        while not self.at_end():
            var c = self.peek()
            if (
                c != UInt8(ord(" "))
                and c != UInt8(ord("\n"))
                and c != UInt8(ord("\r"))
                and c != UInt8(ord("\t"))
            ):
                return
            self.position += 1

    def expect_word(mut self, word: StaticString) raises:
        var expected = word.as_bytes()
        for i in range(len(expected)):
            if self.at_end() or self.peek() != expected[i]:
                raise self.fail("expected " + String(word))
            self.position += 1

    def value(mut self, depth: Int) raises -> Int:
        """Parse one value and its children; return its node's index."""
        self.skip_whitespace()
        if self.at_end():
            raise self.fail("expected a value, found the end")
        var c = self.peek()
        if c == UInt8(ord("{")):
            return self.object(depth + 1)
        if c == UInt8(ord("[")):
            return self.array(depth + 1)
        if c == UInt8(ord('"')):
            var node = _Node.scalar(JSONKind.STRING)
            node.text = self.string()
            return self.add(node^)
        if c == UInt8(ord("t")):
            self.expect_word("true")
            var node = _Node.scalar(JSONKind.BOOL)
            node.flag = True
            return self.add(node^)
        if c == UInt8(ord("f")):
            self.expect_word("false")
            return self.add(_Node.scalar(JSONKind.BOOL))
        if c == UInt8(ord("n")):
            self.expect_word("null")
            return self.add(_Node.scalar(JSONKind.NULL))
        if c == UInt8(ord("-")) or (
            c >= UInt8(ord("0")) and c <= UInt8(ord("9"))
        ):
            return self.add(self.number())
        raise self.fail("expected a value, found '" + String(chr(Int(c))) + "'")

    def add(mut self, var node: _Node) -> Int:
        self.nodes.append(node^)
        return len(self.nodes) - 1

    def nest(self, depth: Int) raises:
        if depth > _MAX_DEPTH:
            raise self.fail(
                "nested deeper than " + String(_MAX_DEPTH) + " levels"
            )

    def object(mut self, depth: Int) raises -> Int:
        self.nest(depth)
        self.position += 1  # {
        var index = self.add(_Node.scalar(JSONKind.OBJECT))
        var keys = List[String]()
        var children = List[Int]()
        self.skip_whitespace()
        if not self.at_end() and self.peek() == UInt8(ord("}")):
            self.position += 1
        else:
            while True:
                self.skip_whitespace()
                if self.at_end() or self.peek() != UInt8(ord('"')):
                    raise self.fail("expected a key in quotes")
                var key = self.string()
                self.skip_whitespace()
                if self.at_end() or self.peek() != UInt8(ord(":")):
                    raise self.fail("expected ':' after a key")
                self.position += 1
                var child = self.value(depth)
                var existing = -1
                for i in range(len(keys)):
                    if keys[i] == key:
                        existing = i
                if existing >= 0:
                    children[existing] = child  # the last of a repeated key
                else:
                    keys.append(key^)
                    children.append(child)
                self.skip_whitespace()
                if self.at_end():
                    raise self.fail("unterminated object")
                if self.peek() == UInt8(ord(",")):
                    self.position += 1
                    continue
                if self.peek() == UInt8(ord("}")):
                    self.position += 1
                    break
                raise self.fail("expected ',' or '}'")
        self.nodes[index].keys = keys^
        self.nodes[index].children = children^
        return index

    def array(mut self, depth: Int) raises -> Int:
        self.nest(depth)
        self.position += 1  # [
        var index = self.add(_Node.scalar(JSONKind.ARRAY))
        var children = List[Int]()
        self.skip_whitespace()
        if not self.at_end() and self.peek() == UInt8(ord("]")):
            self.position += 1
        else:
            while True:
                children.append(self.value(depth))
                self.skip_whitespace()
                if self.at_end():
                    raise self.fail("unterminated array")
                if self.peek() == UInt8(ord(",")):
                    self.position += 1
                    continue
                if self.peek() == UInt8(ord("]")):
                    self.position += 1
                    break
                raise self.fail("expected ',' or ']'")
        self.nodes[index].children = children^
        return index

    def string(mut self) raises -> String:
        """Parse a quoted string, escapes decoded, to UTF-8."""
        var start = self.position
        self.position += 1  # "
        var out = List[UInt8]()
        while True:
            if self.at_end():
                self.position = start
                raise self.fail("unterminated string")
            var c = self.peek()
            if c == UInt8(ord('"')):
                self.position += 1
                return String(unsafe_from_utf8=out)
            if c < 0x20:
                raise self.fail("control character in a string")
            if c != UInt8(ord("\\")):
                out.append(c)
                self.position += 1
                continue
            self.position += 1
            if self.at_end():
                continue  # reported as unterminated above
            var escape = self.peek()
            self.position += 1
            if escape == UInt8(ord('"')):
                out.append(UInt8(ord('"')))
            elif escape == UInt8(ord("\\")):
                out.append(UInt8(ord("\\")))
            elif escape == UInt8(ord("/")):
                out.append(UInt8(ord("/")))
            elif escape == UInt8(ord("b")):
                out.append(0x08)
            elif escape == UInt8(ord("f")):
                out.append(0x0C)
            elif escape == UInt8(ord("n")):
                out.append(UInt8(ord("\n")))
            elif escape == UInt8(ord("r")):
                out.append(UInt8(ord("\r")))
            elif escape == UInt8(ord("t")):
                out.append(UInt8(ord("\t")))
            elif escape == UInt8(ord("u")):
                _append_utf8(out, self.codepoint())
            else:
                self.position -= 2
                raise self.fail("unknown escape")

    def codepoint(mut self) raises -> Int:
        """The codepoint of a `\\uXXXX` escape, joining a surrogate pair."""
        var high = self.hex4()
        if high >= 0xDC00 and high <= 0xDFFF:
            raise self.fail("unpaired low surrogate")
        if high < 0xD800 or high > 0xDBFF:
            return high
        if (
            self.position + 1 >= len(self.bytes)
            or self.bytes[self.position] != UInt8(ord("\\"))
            or self.bytes[self.position + 1] != UInt8(ord("u"))
        ):
            raise self.fail("unpaired high surrogate")
        self.position += 2
        var low = self.hex4()
        if low < 0xDC00 or low > 0xDFFF:
            raise self.fail("unpaired high surrogate")
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)

    def hex4(mut self) raises -> Int:
        var result = 0
        for _ in range(4):
            if self.at_end():
                raise self.fail("expected four hex digits")
            var c = Int(self.peek())
            var digit: Int
            if c >= ord("0") and c <= ord("9"):
                digit = c - ord("0")
            elif c >= ord("a") and c <= ord("f"):
                digit = c - ord("a") + 10
            elif c >= ord("A") and c <= ord("F"):
                digit = c - ord("A") + 10
            else:
                raise self.fail("expected four hex digits")
            result = result * 16 + digit
            self.position += 1
        return result

    def number(mut self) raises -> _Node:
        """Parse a number as JSON's grammar has it, no `+`, no leading 0."""
        var start = self.position
        var integral = True
        if self.peek() == UInt8(ord("-")):
            self.position += 1
        if self.at_end() or not _is_digit(self.peek()):
            raise self.fail("expected a digit")
        if self.peek() == UInt8(ord("0")):
            self.position += 1
        else:
            self.digits()
        if not self.at_end() and self.peek() == UInt8(ord(".")):
            integral = False
            self.position += 1
            if self.at_end() or not _is_digit(self.peek()):
                raise self.fail("expected a digit after '.'")
            self.digits()
        if not self.at_end() and (
            self.peek() == UInt8(ord("e")) or self.peek() == UInt8(ord("E"))
        ):
            integral = False
            self.position += 1
            if not self.at_end() and (
                self.peek() == UInt8(ord("+")) or self.peek() == UInt8(ord("-"))
            ):
                self.position += 1
            if self.at_end() or not _is_digit(self.peek()):
                raise self.fail("expected a digit in the exponent")
            self.digits()
        var text = String(
            unsafe_from_utf8=Span(self.bytes)[start : self.position]
        )
        var node = _Node.scalar(JSONKind.NUMBER)
        node.number = _to_float(text)
        if integral:
            try:
                node.integer = Int(text)
                node.integral = True
            except:
                pass  # beyond 64 bits: kept as a float
        return node^

    def digits(mut self):
        while not self.at_end() and _is_digit(self.peek()):
            self.position += 1


def _to_float(text: String) raises -> Float64:
    """A number's text as a float, however many digits it has.

    `atof` refuses a long mantissa, so past 19 significant digits the rest
    are dropped into the exponent: more than a float holds anyway.
    """
    try:
        return atof(text)
    except:
        pass
    var negative = text.startswith("-")
    var digits = String()
    var exponent = 0
    var in_fraction = False
    var parts = text.lower().split("e")
    if len(parts) == 2:
        exponent = Int(String(parts[1]))
    for byte in parts[0].as_bytes():
        if byte == UInt8(ord(".")):
            in_fraction = True
        elif _is_digit(byte):
            if digits.byte_length() == 0 and byte == UInt8(ord("0")):
                if in_fraction:
                    exponent -= 1
                continue
            if digits.byte_length() < 19:
                digits += String(chr(Int(byte)))
                if in_fraction:
                    exponent -= 1
            elif not in_fraction:
                exponent += 1
    if digits.byte_length() == 0:
        return -0.0 if negative else 0.0
    return atof(("-" if negative else "") + digits + "e" + String(exponent))


def _extract(nodes: List[_Node], index: Int, mut out: List[_Node]) -> Int:
    """Copy the subtree under `index` onto the end of `out`, children
    renumbered; return the index of its root there.

    Only what the subtree reaches is copied, so the nodes an edit left
    behind are dropped. A worklist rather than recursion, so a document
    nested by code, deeper than `parse` allows, copies too.
    """
    var root = len(out)
    out.append(nodes[index].copy())
    var sources: List[Int] = [index]
    var targets: List[Int] = [root]
    while len(sources) > 0:
        var source = sources.pop()
        var target = targets.pop()
        var children = List[Int](capacity=len(nodes[source].children))
        for child in nodes[source].children:
            children.append(len(out))
            sources.append(child)
            targets.append(len(out))
            out.append(nodes[child].copy())
        out[target].children = children^
    return root


def _is_digit(c: UInt8) -> Bool:
    return c >= UInt8(ord("0")) and c <= UInt8(ord("9"))


def _append_utf8(mut out: List[UInt8], codepoint: Int):
    if codepoint < 0x80:
        out.append(UInt8(codepoint))
    elif codepoint < 0x800:
        out.append(UInt8(0xC0 | (codepoint >> 6)))
        out.append(UInt8(0x80 | (codepoint & 0x3F)))
    elif codepoint < 0x10000:
        out.append(UInt8(0xE0 | (codepoint >> 12)))
        out.append(UInt8(0x80 | ((codepoint >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (codepoint & 0x3F)))
    else:
        out.append(UInt8(0xF0 | (codepoint >> 18)))
        out.append(UInt8(0x80 | ((codepoint >> 12) & 0x3F)))
        out.append(UInt8(0x80 | ((codepoint >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (codepoint & 0x3F)))


def _parse(text: String, source: String) raises -> JSON:
    var parser = _Parser(text, source)
    var root = parser.value(0)
    parser.skip_whitespace()
    if not parser.at_end():
        raise parser.fail("unexpected text after the value")
    var nodes = List[_Node]()
    swap(nodes, parser.nodes)
    return JSON(_document=ArcPointer(_Document(nodes^)), _index=root)


def _write_value[W: Writer](mut writer: W, nodes: List[_Node], index: Int):
    """Write a value as compact JSON text.

    A number with no JSON form (infinite or NaN) is written as `null`.
    """
    ref node = nodes[index]
    if node.kind == JSONKind.NULL:
        writer.write("null")
    elif node.kind == JSONKind.BOOL:
        writer.write("true" if node.flag else "false")
    elif node.kind == JSONKind.NUMBER:
        if node.integral:
            writer.write(node.integer)
        elif isnan(node.number) or isinf(node.number):
            writer.write("null")
        else:
            writer.write(node.number)
    elif node.kind == JSONKind.STRING:
        _write_string(writer, node.text)
    elif node.kind == JSONKind.ARRAY:
        writer.write("[")
        for i in range(len(node.children)):
            if i > 0:
                writer.write(",")
            _write_value(writer, nodes, node.children[i])
        writer.write("]")
    else:
        writer.write("{")
        for i in range(len(node.children)):
            if i > 0:
                writer.write(",")
            _write_string(writer, node.keys[i])
            writer.write(":")
            _write_value(writer, nodes, node.children[i])
        writer.write("}")


def _write_string[W: Writer](mut writer: W, text: String):
    """Write `text` quoted, escaping what JSON requires."""
    comptime HEX = "0123456789abcdef"
    var hex = HEX.as_bytes()
    var out = List[UInt8](capacity=text.byte_length() + 2)
    out.append(UInt8(ord('"')))
    for byte in text.as_bytes():
        var escape: UInt8 = 0
        if byte == UInt8(ord('"')):
            escape = UInt8(ord('"'))
        elif byte == UInt8(ord("\\")):
            escape = UInt8(ord("\\"))
        elif byte == UInt8(ord("\n")):
            escape = UInt8(ord("n"))
        elif byte == UInt8(ord("\r")):
            escape = UInt8(ord("r"))
        elif byte == UInt8(ord("\t")):
            escape = UInt8(ord("t"))
        elif byte < 0x20:
            out.append(UInt8(ord("\\")))
            out.append(UInt8(ord("u")))
            out.append(UInt8(ord("0")))
            out.append(UInt8(ord("0")))
            out.append(hex[Int(byte >> 4)])
            out.append(hex[Int(byte & 0xF)])
            continue
        if escape != 0:
            out.append(UInt8(ord("\\")))
            out.append(escape)
        else:
            out.append(byte)
    out.append(UInt8(ord('"')))
    writer.write(String(unsafe_from_utf8=out))
