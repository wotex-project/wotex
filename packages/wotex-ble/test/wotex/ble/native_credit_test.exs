defmodule Wotex.BLE.NativeCreditTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @root Path.expand("../../..", __DIR__)
  @source Path.join(@root, "test/native/credit_test.cpp")
  @include Path.join(@root, "priv/bluez/native")
  @corpus Path.join(@root, "docs/specs/fixtures/native-port-v1.json")
  @fixtures get_in(Jason.decode!(File.read!(@corpus)), ["cases"])
  @implemented ~w(WBL-B-F07 WBL-B-F08 WBL-B-F09 WBL-B-F14 WBL-B-F15)

  setup_all do
    compiler =
      System.find_executable("c++") || flunk("native credit tests require a C++17 compiler")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-credit-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    executable = Path.join(directory, "credit-test")

    {output, status} =
      System.cmd(
        compiler,
        [
          "-std=c++17",
          "-Wall",
          "-Wextra",
          "-Werror",
          "-pedantic",
          "-I",
          @include,
          @source,
          "-o",
          executable
        ],
        stderr_to_stdout: true,
        env: clean_environment()
      )

    assert status == 0, output
    {:ok, executable: executable}
  end

  test "WBL-B02 exact credits, retired streams and 100000 subscription lifetimes", context do
    assert {"native credit invariants passed\n", 0} =
             System.cmd(context.executable, [], env: clean_environment())
  end

  for fixture <- @fixtures, fixture["id"] in @implemented do
    @fixture fixture
    test "#{fixture["id"]} enforces native reservation and retirement accounting", context do
      {output, status} =
        System.cmd(context.executable, ["--trace", Jason.encode!(@fixture["input"])],
          env: clean_environment()
        )

      assert status == 0
      assert Jason.decode!(output) == @fixture["expectation"]["value"]
    end
  end

  defp clean_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end
end
