defmodule Wotex.BLE.NativeFrameTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.NativeLane

  @root Path.expand("../../..", __DIR__)
  @source Path.join(@root, "test/native/frame_test.cpp")
  @include Path.join(@root, "priv/bluez/native")
  @corpus Path.join(@root, "priv/fixtures/native-port-v1.json")
  @fixtures get_in(Jason.decode!(File.read!(@corpus)), ["cases"])
  @header_hash "9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6"

  setup_all do
    compiler = System.find_executable("c++") || flunk("native frame tests require a C++17 compiler")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    executable = Path.join(directory, "frame-test")

    {output, status} =
      System.cmd(
        compiler,
        NativeLane.flags() ++
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
        env: NativeLane.environment(clean_environment())
      )

    assert status == 0, output
    {:ok, executable: executable}
  end

  test "WBL-B01 pinned parser header identity" do
    hash =
      @include
      |> Path.join("vendor/json.hpp")
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert hash == @header_hash
  end

  test "WBL-B02 bounds, malformed input, split frames and monotonic ID churn", context do
    assert {"native frame invariants passed\n", 0} =
             System.cmd(context.executable, [], env: NativeLane.environment(clean_environment()))
  end

  for fixture <- @fixtures,
      fixture["operation"] == "parse_request" do
    @fixture fixture
    test "#{fixture["id"]} validates the production native request parser", context do
      {output, status} =
        System.cmd(context.executable, ["--parse-request", @fixture["input"]["line_utf8"]],
          env: NativeLane.environment(clean_environment())
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
