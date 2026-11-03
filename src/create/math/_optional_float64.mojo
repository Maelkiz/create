from std.collections import Optional


struct _OptionalFloat64(Boolable, Copyable, ImplicitlyCopyable, Movable):
    """An optional `Float64` keyword (a thickness, a size, a shadow part, an
    opacity, a corner radius): `None` when left unset, like every other
    optional keyword.

    Not `Optional[Float64]`, which a bare `blur=12` cannot reach — an integer
    literal converts to `Float64` or to an `Optional`, not through both. This
    takes each in one step, so `blur=12`, `blur=1.5`, `blur=n` and
    `blur=None` all work and a program never names the type. Read it like an
    `Optional`: truth for "given", `value()`, `or_else(default)`.

    Also the type of a keyword that has a default rather than "unset" (a
    shape's `corner_radius=`), where it is how an `Int` variable reaches a
    `Float64` without an overload per keyword.
    """

    var _value: Optional[Float64]

    @implicit
    def __init__(out self, value: Float64):
        self._value = value

    @implicit
    def __init__(out self, value: Int):
        self._value = Float64(value)

    @implicit
    def __init__(out self, value: IntLiteral):
        self._value = Float64(value)

    @implicit
    def __init__(out self, value: Optional[Float64]):
        self._value = value

    @implicit
    def __init__(out self, none: NoneType._mlir_type):
        self._value = None

    def __bool__(self) -> Bool:
        return Bool(self._value)

    def value(self) -> Float64:
        return self._value.value()

    def or_else(self, default: Float64) -> Float64:
        return self._value.or_else(default)
