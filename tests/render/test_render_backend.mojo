# RenderBackend.from_arguments reads the command line; its rule is tested on
# lists through the internal _from_argument_list it delegates to.

from std.testing import TestSuite, assert_equal

from create import *


def test_no_arguments_is_the_cpu() raises -> None:
    assert_equal(
        RenderBackend._from_argument_list(List[String]()), RenderBackend.CPU
    )


def test_gpu_among_other_arguments_is_the_gpu() raises -> None:
    var arguments: List[String] = ["fullscreen", "gpu"]
    assert_equal(
        RenderBackend._from_argument_list(arguments), RenderBackend.GPU
    )


def test_the_last_named_backend_wins() raises -> None:
    var arguments: List[String] = ["gpu", "cpu"]
    assert_equal(
        RenderBackend._from_argument_list(arguments), RenderBackend.CPU
    )
    arguments = ["cpu", "gpu"]
    assert_equal(
        RenderBackend._from_argument_list(arguments), RenderBackend.GPU
    )


def test_unrelated_arguments_leave_the_cpu() raises -> None:
    var arguments: List[String] = ["GPU", "--gpu", "fullscreen"]
    assert_equal(
        RenderBackend._from_argument_list(arguments), RenderBackend.CPU
    )


def test_the_test_runs_command_line_names_no_backend() raises -> None:
    assert_equal(RenderBackend.from_arguments(), RenderBackend.CPU)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
