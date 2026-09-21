defmodule Mix.Tasks.Wotex.Native.ManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Manifest

  test "requires one explicit cell and absolute paths" do
    assert Manifest.parse_args([
             "--package",
             "native",
             "--profile",
             "production",
             "--target",
             "linux",
             "--root",
             "/payload",
             "--output",
             "/artifact-manifest.json"
           ]) == [
             package: "native",
             profile: "production",
             target: "linux",
             root: "/payload",
             output: "/artifact-manifest.json"
           ]

    assert_raise Mix.Error, ~r/--output is required/, fn ->
      Manifest.parse_args(~w(--package native --profile production --target linux --root /payload))
    end

    assert_raise Mix.Error, ~r/--root must be absolute/, fn ->
      Manifest.parse_args(
        ~w(--package native --profile production --target linux --root relative --output /manifest)
      )
    end
  end
end
