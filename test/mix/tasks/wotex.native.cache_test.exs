defmodule Mix.Tasks.Wotex.Native.CacheTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Cache

  @identity String.duplicate("a", 64)

  test "requires an exact identity and cell for inspection" do
    assert Cache.parse_args([
             "--cache",
             "/cache",
             "--identity",
             @identity,
             "--package",
             "native",
             "--profile",
             "production",
             "--target",
             "linux",
             "--json"
           ]) == [
             cache: "/cache",
             identity: @identity,
             package: "native",
             profile: "production",
             target: "linux",
             json: true
           ]

    assert_raise Mix.Error, ~r/required for inspection/, fn ->
      Cache.parse_args(["--cache", "/cache", "--identity", @identity])
    end

    assert_raise Mix.Error, ~r/full lowercase SHA-256/, fn ->
      Cache.parse_args(~w(--cache /cache --identity abc --delete))
    end
  end

  test "separates exact deletion from bounded collection" do
    assert Cache.parse_args(["--cache", "/cache", "--identity", @identity, "--delete"]) ==
             [cache: "/cache", identity: @identity, delete: true]

    assert Cache.parse_args([
             "--cache",
             "/cache",
             "--gc",
             "--keep",
             @identity,
             "--max-scan",
             "10",
             "--max-remove",
             "2"
           ]) == [
             cache: "/cache",
             gc: true,
             keep: @identity,
             max_scan: 10,
             max_remove: 2
           ]

    assert_raise Mix.Error, ~r/mutually exclusive/, fn ->
      Cache.parse_args(["--cache", "/cache", "--identity", @identity, "--delete", "--gc"])
    end

    assert_raise Mix.Error, ~r/does not accept --identity/, fn ->
      Cache.parse_args(["--cache", "/cache", "--identity", @identity, "--gc"])
    end
  end
end
