defmodule Wotex.OPCUA.Native.CustodyTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @fixtures "docs/specs/fixtures/custody-contract-v1.json"
  @cases Jason.decode!(File.read!(@fixtures))["cases"]

  setup_all do
    directory =
      Path.join(System.tmp_dir!(), "wotex-opcua-custody-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    compiler = System.find_executable("cc") || flunk("runtime custody tests require a C11 compiler")
    native = Application.app_dir(:wotex_opcua, "priv/native")

    for name <- ["custody", "custody_check"] do
      {output, status} =
        System.cmd(
          compiler,
          [
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            Path.join(native, name <> ".c"),
            "-o",
            Path.join(directory, name)
          ],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status == 0, output
    end

    %{directory: directory}
  end

  for fixture <- @cases do
    @fixture fixture
    @tag timeout: 30_000
    test "#{fixture["id"]} actual opaque-stream custody matches the executable fixture", context do
      fixture = @fixture
      workspace = Path.join(context.directory, fixture["id"])
      File.mkdir_p!(workspace)

      {output, status} =
        System.cmd(
          Path.join(context.directory, "custody_check"),
          [Path.join(context.directory, "custody"), fixture["id"], workspace],
          stderr_to_stdout: true,
          env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
        )

      assert status == 0, output
      result = Jason.decode!(output)
      assert result["case"] == fixture["id"]
      assert result["input_capacity"] == fixture["input_capacity"]
      assert result["output_capacity"] == fixture["output_capacity"]
      expected = fixture["expectation"]

      assert Map.take(result, ~w(received_bytes direct_reaped background_stopped status)) ==
               Map.take(expected, ~w(received_bytes direct_reaped background_stopped status))

      case expected["sent_bytes"] do
        %{"operator" => "exact", "value" => value} -> assert result["sent_bytes"] == value
        %{"operator" => "positive"} -> assert result["sent_bytes"] > fixture["input_capacity"]
      end

      assert result["cleanup_ms"] in 0..fixture["cleanup_allowance_ms"]
      assert result["guardian_exit_ms"] in 0..fixture["cleanup_allowance_ms"]
      assert result["instrumented_exit_allowance_ms"] == 0
    end
  end
end
