from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from create.data import JSON, JSONKind

comptime FIXTURES = "tests/fixtures/data/"


def _round_trips(text: String) raises -> None:
    """Printing a parsed document gives text that parses to the same print."""
    var once = String(JSON.parse(text))
    assert_equal(String(JSON.parse(once)), once)


def test_reads_nested_values() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    assert_equal(config["title"].string(), "Bouncing")
    assert_false(config["debug"].bool())
    assert_equal(config["volume"].float(), 0.8)
    assert_equal(config["player"]["speed"].float(), 2.5)
    assert_equal(config["player"]["lives"].int(), 3)
    assert_true(config["player"]["name"].is_null())
    assert_equal(config["enemies"][1]["name"].string(), "bat")


def test_kind_len_and_contains() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    assert_equal(config.kind(), JSONKind.OBJECT)
    assert_equal(config["enemies"].kind(), JSONKind.ARRAY)
    assert_equal(config["volume"].kind(), JSONKind.NUMBER)
    assert_equal(len(config["enemies"]), 2)
    assert_equal(len(config["player"]), 3)
    assert_equal(len(config["title"]), 0)
    assert_true("player" in config)
    assert_false("score" in config)
    assert_false("x" in config["enemies"])


def test_keys_keep_document_order() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    assert_equal(
        config.keys(),
        ["title", "debug", "volume", "player", "enemies", "seed"],
    )


def test_items_of_an_array_and_an_object() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    var total = 0
    for enemy in config["enemies"].items():
        total += enemy["hp"].int()
    assert_equal(total, 6)
    var values = config["player"].items()
    assert_equal(len(values), 3)
    assert_equal(values[0].float(), 2.5)
    with assert_raises(contains=".items() needs an array or an object"):
        _ = config["title"].items()


def test_int_is_exact_and_strict() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    assert_equal(config["seed"].int(), 9007199254740993)  # beyond a float's
    assert_equal(JSON.parse("-0").int(), 0)
    assert_equal(JSON.parse("3.0").int(), 3)
    assert_equal(JSON.parse("3e2").int(), 300)
    with assert_raises(contains="not a whole number"):
        _ = JSON.parse("1.5").int()
    with assert_raises(contains="not a whole number"):
        _ = JSON.parse("1e30").int()


def test_integers_beyond_64_bits_read_as_floats() raises -> None:
    var big = JSON.parse("123456789012345678901234567890")
    assert_equal(big.float(), 1.2345678901234568e29)
    assert_equal(
        JSON.parse("0.000000000000000000001234567890123456789012").float(),
        1.234567890123456789e-21,
    )
    assert_equal(
        JSON.parse("-1234567890123456789012.5e-3").float(),
        -1.2345678901234568e18,
    )


def test_numbers_follow_the_grammar() raises -> None:
    assert_equal(JSON.parse("-12.5e-1").float(), -1.25)
    assert_equal(JSON.parse("0.5").float(), 0.5)
    for bad in ["01", "+1", ".5", "1.", "1e", "-", "0x10"]:
        with assert_raises():
            _ = JSON.parse(bad)


def test_strings_decode_escapes_to_utf8() raises -> None:
    var doc = JSON.load(FIXTURES + "unicode.json")
    assert_equal(doc["plain"].string(), "café")
    assert_equal(doc["raw"].string(), "café")
    assert_equal(doc["pair"].string(), "😀")
    assert_equal(doc["escapes"].string(), 'a"b\\c/d\n\t')
    assert_equal(len(doc["empty"]), 0)
    assert_equal(len(doc["none"]), 0)


def test_bad_surrogates_raise() raises -> None:
    with assert_raises(contains="unpaired high surrogate"):
        _ = JSON.parse('"\\ud83d"')
    with assert_raises(contains="unpaired low surrogate"):
        _ = JSON.parse('"\\ude00"')


def test_repeated_key_keeps_the_last() raises -> None:
    var doc = JSON.parse('{"a": 1, "b": 2, "a": 3}')
    assert_equal(doc["a"].int(), 3)
    assert_equal(doc.keys(), ["a", "b"])


def test_wrong_kind_and_missing_raise_naming_them() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    with assert_raises(contains='no key "score"'):
        _ = config["score"]
    with assert_raises(contains="no item 2: the array has 2"):
        _ = config["enemies"][2]
    with assert_raises(contains=".float() needs a number, not a string"):
        _ = config["title"].float()
    with assert_raises(contains='["x"] needs an object, not an array'):
        _ = config["enemies"]["x"]
    with assert_raises(contains="[0] needs an array, not an object"):
        _ = config[0]


def test_malformed_input_names_line_and_column() raises -> None:
    with assert_raises(
        contains="bad_comma.json:3:14: expected a value, found ']'"
    ):
        _ = JSON.load(FIXTURES + "bad_comma.json")
    with assert_raises(contains="<input>:1:4: unexpected text after"):
        _ = JSON.parse("{} x")
    with assert_raises(contains="<input>:1:1: unterminated string"):
        _ = JSON.parse('"abc')
    with assert_raises(contains="expected ':' after a key"):
        _ = JSON.parse('{"a" 1}')
    with assert_raises(contains="expected a key in quotes"):
        _ = JSON.parse("{a: 1}")
    with assert_raises(contains="expected true"):
        _ = JSON.parse("tru")
    with assert_raises(contains="expected a value, found the end"):
        _ = JSON.parse("   ")
    with assert_raises(contains="control character"):
        _ = JSON.parse('"a\nb"')


def test_deep_nesting_raises_instead_of_crashing() raises -> None:
    var text = String()
    for _ in range(10000):
        text += "["
    with assert_raises(contains="nested deeper than 512 levels"):
        _ = JSON.parse(text)
    var ok = String()
    for _ in range(512):
        ok += "["
    for _ in range(512):
        ok += "]"
    assert_equal(JSON.parse(ok).kind(), JSONKind.ARRAY)


def test_prints_as_compact_json() raises -> None:
    assert_equal(
        String(JSON.parse('{ "a" : [1, 2.5, true, null], "b": "x\\ny" }')),
        '{"a":[1,2.5,true,null],"b":"x\\ny"}',
    )
    assert_equal(String(JSON.parse('"\\u0001"')), '"\\u0001"')
    var config = JSON.load(FIXTURES + "config.json")
    assert_equal(
        String(config["player"]), '{"speed":2.5,"lives":3,"name":null}'
    )


def test_every_fixture_round_trips() raises -> None:
    for name in ["config.json", "unicode.json"]:
        with open(FIXTURES + name, "r") as f:
            _round_trips(f.read())
    _round_trips("[0.1, 1e-7, -0.0, 1.7976931348623157e308, 5e-324]")


def test_kind_prints_as_written() raises -> None:
    assert_equal(String(JSONKind.OBJECT), "JSONKind.OBJECT")
    assert_equal(String(JSONKind(9)), "JSONKind(9)")


def test_root_preamble_reaches_json() raises -> None:
    from create import JSON as RootJSON

    assert_equal(RootJSON.parse("[1]")[0].int(), 1)


def test_nested_assignment_lands_in_the_document() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    config["player"]["speed"] = 3.0
    config["enemies"][0]["hp"] = 9
    config["player"]["name"] = "Ada"
    assert_equal(config["player"]["speed"].float(), 3.0)
    assert_equal(config["enemies"][0]["hp"].int(), 9)
    assert_equal(config["player"]["name"].string(), "Ada")


def test_editing_items_in_a_loop() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    for enemy in config["enemies"].items():
        enemy["hp"] = enemy["hp"].int() - 1
    assert_equal(
        String(config["enemies"]),
        '[{"name":"slime","hp":3},{"name":"bat","hp":1}]',
    )


def test_a_value_read_from_a_document_aliases_it() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    var player = config["player"]
    player["speed"] = 4.0
    assert_equal(config["player"]["speed"].float(), 4.0)


def test_copy_is_independent() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    var copied = config.copy()
    copied["x"] = 1
    copied["player"]["lives"] = 0
    assert_false("x" in config)
    assert_equal(config["player"]["lives"].int(), 3)
    assert_equal(copied["player"]["lives"].int(), 0)
    var player = config["player"].copy()
    player["lives"] = 7
    assert_equal(config["player"]["lives"].int(), 3)


def test_a_value_set_twice_is_two_values() raises -> None:
    var doc = JSON.object()
    var point = JSON.object()
    point["x"] = 1
    doc["a"] = point
    doc["b"] = point
    doc["a"]["x"] = 2
    assert_equal(doc["b"]["x"].int(), 1)
    point["x"] = 5
    assert_equal(doc["a"]["x"].int(), 2)
    doc["c"] = doc["a"]  # within one document: copied too
    doc["c"]["x"] = 3
    assert_equal(doc["a"]["x"].int(), 2)


def test_assigning_a_value_to_itself_changes_nothing() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    var before = String(config)
    config["player"] = config["player"]
    config["enemies"][1] = config["enemies"][1]
    assert_equal(String(config), before)


def test_build_a_document() raises -> None:
    var save = JSON.object()
    save["level"] = 3
    save["name"] = "Ada"
    save["ratio"] = 0.5
    save["done"] = False
    save["none"] = JSON.null()
    var path = JSON.array()
    path.append(1.5)
    path.append(JSON.object())
    path[1]["y"] = 2
    save["path"] = path
    save["level"] = 4  # replaces in place, order kept
    assert_equal(
        String(save),
        '{"level":4,"name":"Ada","ratio":0.5,"done":false,"none":null,'
        + '"path":[1.5,{"y":2}]}',
    )


def test_get_falls_back_to_the_default() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    assert_equal(config.get("volume", 1.0).float(), 0.8)
    assert_equal(config.get("music", 0.5).float(), 0.5)
    assert_equal(config.get("lives", 3).int(), 3)
    with assert_raises(contains=".get() needs an object"):
        _ = config["enemies"].get("x", 1)


def test_remove() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    config.remove("debug")
    config["enemies"].remove(0)
    assert_false("debug" in config)
    assert_equal(len(config["enemies"]), 1)
    assert_equal(config["enemies"][0]["name"].string(), "bat")
    with assert_raises(contains='no key "debug"'):
        config.remove("debug")
    with assert_raises(contains="no item 1: the array has 1"):
        config["enemies"].remove(1)


def test_edits_check_the_kind_and_range() raises -> None:
    var config = JSON.load(FIXTURES + "config.json")
    with assert_raises(contains='["x"] = needs an object, not an array'):
        config["enemies"]["x"] = 1
    with assert_raises(contains="no item 5: the array has 2"):
        config["enemies"][5] = 1
    with assert_raises(contains=".append() needs an array"):
        config.append(1)


def test_copy_drops_what_edits_left_behind() raises -> None:
    var doc = JSON.object()
    for i in range(100):
        doc["value"] = i
    assert_equal(len(doc._document[].nodes), 101)
    var copied = doc.copy()
    assert_equal(len(copied._document[].nodes), 2)
    assert_equal(copied["value"].int(), 99)


def test_int_stays_exact_when_built() raises -> None:
    var doc = JSON.object()
    doc["seed"] = 9007199254740993
    assert_equal(String(doc), '{"seed":9007199254740993}')


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
