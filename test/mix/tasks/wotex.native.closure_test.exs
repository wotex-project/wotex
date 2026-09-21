defmodule Mix.Tasks.Wotex.Native.ClosureTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Closure

  @identity String.duplicate("a", 64)

  test "requires explicit absolute cache, rootfs, target and artifacts" do
    spec = "wotex-thread/production/#{@identity}"

    assert Closure.parse_args([
             "--cache",
             "/cache",
             "--rootfs",
             "/rootfs",
             "--target",
             "linux-x86-64",
             "--artifact",
             spec,
             "--json"
           ]) == [
             cache: "/cache",
             rootfs: "/rootfs",
             target: "linux-x86-64",
             artifact: spec,
             json: true
           ]

    assert Closure.parse_artifact!(spec) == {"wotex-thread", "production", @identity}

    assert_raise Mix.Error, ~r/at least one --artifact/, fn ->
      Closure.parse_args(~w(--cache /cache --rootfs /rootfs --target linux-x86-64))
    end

    assert_raise Mix.Error, ~r/--rootfs must be absolute/, fn ->
      Closure.parse_args([
        "--cache",
        "/cache",
        "--rootfs",
        "relative",
        "--target",
        "linux-x86-64",
        "--artifact",
        spec
      ])
    end
  end

  test "rejects abbreviated and malformed artifact selections" do
    assert_raise Mix.Error, ~r/full lowercase SHA-256/, fn ->
      Closure.parse_artifact!("wotex-thread/production/abc")
    end

    assert_raise Mix.Error, ~r/PACKAGE\/PROFILE/, fn ->
      Closure.parse_artifact!("wotex-thread")
    end
  end
end
