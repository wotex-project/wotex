defmodule Mix.Tasks.Wotex.Native.RetrieveTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Retrieve

  @identity String.duplicate("a", 64)
  @transport String.duplicate("b", 64)

  test "requires one exact prebuilt cell, transport digest and absolute cache" do
    assert Retrieve.parse_args([
             "--package",
             "wotex-thread",
             "--profile",
             "production",
             "--target",
             "linux-x86-64",
             "--identity",
             @identity,
             "--sha256",
             @transport,
             "--cache",
             "/cache",
             "--source",
             "hosted",
             "--authorization-env",
             "WOTEX_ARTIFACT_AUTHORIZATION",
             "--json"
           ]) == [
             package: "wotex-thread",
             profile: "production",
             target: "linux-x86-64",
             identity: @identity,
             sha256: @transport,
             cache: "/cache",
             source: "hosted",
             authorization_env: "WOTEX_ARTIFACT_AUTHORIZATION",
             json: true
           ]

    assert_raise Mix.Error, ~r/--sha256 is required/, fn ->
      Retrieve.parse_args([
        "--package",
        "wotex-thread",
        "--profile",
        "production",
        "--target",
        "linux-x86-64",
        "--identity",
        @identity,
        "--cache",
        "/cache"
      ])
    end
  end

  test "rejects short identities, relative caches and unscoped authorization" do
    base =
      ~w(--package native --profile production --target linux --identity #{@identity} --sha256 #{@transport})

    assert_raise Mix.Error, ~r/--cache must be absolute/, fn ->
      Retrieve.parse_args(base ++ ["--cache", "relative"])
    end

    assert_raise Mix.Error, ~r/--identity must be a full/, fn ->
      Retrieve.parse_args(
        ~w(--package native --profile production --target linux --identity short --sha256 #{@transport} --cache /cache)
      )
    end

    assert_raise Mix.Error, ~r/requires --source/, fn ->
      Retrieve.parse_args(base ++ ["--cache", "/cache", "--authorization-env", "TOKEN"])
    end

    assert_raise Mix.Error, ~r/uppercase environment/, fn ->
      Retrieve.parse_args(
        base ++
          ["--cache", "/cache", "--source", "hosted", "--authorization-env", "token"]
      )
    end
  end
end
