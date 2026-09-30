defmodule Mix.Tasks.Wotex.Native.AdvisoriesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wotex.Native.Advisories

  test "takes --offline and repeated native package selections" do
    assert Advisories.parse_args(~w(--offline)) == [offline: true]
    assert Advisories.parse_args([]) == []
    assert_raise Mix.Error, fn -> Advisories.parse_args(~w(--all)) end

    assert Advisories.parse_args(~w(--package wotex-lab --package wotex-coap --offline)) ==
             [package: "wotex-lab", package: "wotex-coap", offline: true]

    assert_raise Mix.Error, fn -> Advisories.parse_args(~w(--package missing)) end
    assert_raise Mix.Error, fn -> Advisories.parse_args(~w(--package wotex)) end
  end

  test "a package selection excludes unrelated upstream pins" do
    output = capture_io(fn -> Advisories.run(~w(--package wotex-lab --offline)) end)
    assert output =~ "offline: skipped 0 OSV query(ies)"
    refute output =~ "libcoap"

    all = capture_io(fn -> Advisories.run(~w(--offline)) end)
    assert all =~ "libcoap"
  end
end
