defmodule Mix.Tasks.Wotex.Native.AdoptTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Adopt

  test "requires one explicit cell and absolute artifact and cache paths" do
    assert Adopt.parse_args(~w(--package native --profile production --target linux \
                --artifact /artifact.tar --cache /cache --json)) == [
             package: "native",
             profile: "production",
             target: "linux",
             artifact: "/artifact.tar",
             cache: "/cache",
             json: true
           ]

    assert_raise Mix.Error, ~r/--cache is required/, fn ->
      Adopt.parse_args(
        ~w(--package native --profile production --target linux --artifact /artifact.tar)
      )
    end

    assert_raise Mix.Error, ~r/--artifact must be absolute/, fn ->
      Adopt.parse_args(~w(--package native --profile production --target linux \
           --artifact artifact.tar --cache /cache))
    end
  end
end
