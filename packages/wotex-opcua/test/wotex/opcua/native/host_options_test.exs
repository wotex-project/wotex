defmodule Wotex.OPCUA.Native.HostOptionsTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.{Error, Native.HostOptions}
  doctest HostOptions

  @valid [
    executable: "/explicit/sdk",
    executable_digest: String.duplicate("0", 64),
    guardian: "/explicit/guardian",
    guardian_digest: String.duplicate("a", 64)
  ]

  test "WOP-X01 pure options require explicit identities and keep exact deadline bounds" do
    assert {:ok, %HostOptions{timeout: 5000, executable: "/explicit/sdk"}} =
             HostOptions.new(@valid)

    for timeout <- [1, 60_000] do
      assert {:ok, %HostOptions{timeout: ^timeout}} = HostOptions.new([timeout: timeout] ++ @valid)
    end

    assert {:ok, settings} = HostOptions.new(@valid)
    refute inspect(settings) =~ "/explicit"
    refute inspect(settings) =~ String.duplicate("a", 64)
  end

  test "WOP-X01 malformed, unknown, duplicate and missing options fail before admission" do
    for invalid <-
          [nil, %{}, [1], [{"executable", "/x"}], [{:timeout, 1} | :bad]] ++
            Enum.map(Keyword.keys(@valid), &Keyword.delete(@valid, &1)) ++
            [[{:other, true} | @valid], [{:guardian, "/other"} | @valid]] do
      assert {:error, %Error{code: :invalid_native_configuration}} = HostOptions.new(invalid)
    end
  end

  test "WOP-X01 path, digest and timeout malformed values cannot acquire resources" do
    for key <- [:executable, :guardian],
        value <- [nil, "relative", "", <<255>>, "/" <> <<0>>, "/" <> String.duplicate("x", 4096)] do
      assert {:error, %Error{code: :invalid_native_configuration}} =
               HostOptions.new(Keyword.put(@valid, key, value))
    end

    for key <- [:executable_digest, :guardian_digest],
        value <- [
          nil,
          "",
          String.duplicate("A", 64),
          String.duplicate("g", 64),
          String.duplicate("0", 10_000),
          String.duplicate("0", 65)
        ] do
      assert {:error, %Error{code: :invalid_native_configuration}} =
               HostOptions.new(Keyword.put(@valid, key, value))
    end

    for value <- [0, 60_001, :infinity, true, 1.0] do
      assert {:error, %Error{code: :invalid_native_configuration}} =
               HostOptions.new(Keyword.put(@valid, :timeout, value))
    end
  end
end
