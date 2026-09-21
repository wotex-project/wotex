defmodule Mix.Tasks.Wotex.Native.VerifyTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Verify

  test "requires one local absolute archive" do
    assert Verify.parse_args(
             ~w(--package native --profile production --target linux --artifact /artifact.tar --json)
           ) == [
             package: "native",
             profile: "production",
             target: "linux",
             artifact: "/artifact.tar",
             json: true
           ]

    assert_raise Mix.Error, ~r/--artifact must be absolute/, fn ->
      Verify.parse_args(
        ~w(--package native --profile production --target linux --artifact artifact.tar)
      )
    end
  end
end
