defmodule Wotex.OPCUA.Native.JSONTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.OPCUA.Native.Command

  @fixture "docs/specs/fixtures/native-json-v1.json"
  @cases Jason.decode!(File.read!(@fixture))["cases"]
  @flags ~w(-std=c11 -Wall -Wextra -Werror -DYYJSON_DISABLE_NON_STANDARD=1
    -DYYJSON_DISABLE_UTILS=1 -DYYJSON_DISABLE_INCR_READER=1
    -DYYJSON_DISABLE_FAST_FP_CONV=0 -DYYJSON_DISABLE_UTF8_VALIDATION=0)

  setup_all do
    directory =
      Path.join(System.tmp_dir!(), "wotex-opcua-json-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    compiler = System.find_executable("cc") || flunk("native JSON tests require a C11 compiler")
    native = Application.app_dir(:wotex_opcua, "priv/native")

    for {name, sources} <- [
          {"json_check", ~w(json_codec.c json_check.c vendor/yyjson/yyjson.c)},
          {"build_command", ["build_command.c"]}
        ] do
      {output, status} =
        System.cmd(
          compiler,
          @flags ++ Enum.map(sources, &Path.join(native, &1)) ++ ["-o", Path.join(directory, name)],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status == 0, output
    end

    # Pay macOS first-launch assessment outside the per-case command deadline.
    assert {_, 0} =
             System.cmd(Path.join(directory, "json_check"), ["--self-test"], env: [{"LC_ALL", "C"}])

    assert {_, 126} =
             System.cmd(Path.join(directory, "build_command"), ["--warm"], env: [{"LC_ALL", "C"}])

    %{directory: directory}
  end

  for fixture <- @cases do
    @case fixture
    test "#{fixture["id"]} native strict parser and numeric bits match exact corpus", context do
      fixture = @case

      frame =
        case fixture do
          %{"frame_base64" => encoded} ->
            Base.decode64!(encoded)

          %{"frame" => parts} ->
            Base.decode64!(parts["prefix_base64"]) <>
              :binary.copy(" ", parts["space_bytes"]) <>
              Base.decode64!(parts["suffix_base64"])
        end

      input = Path.join(context.directory, fixture["id"])
      File.write!(input, frame)

      pool =
        case Map.get(fixture, "pool_bytes", 2_097_152) do
          size when is_integer(size) -> Integer.to_string(size)
        end

      args = ["--parse", input, pool]
      assert run(context, args) == fixture["expected"]
    end
  end

  test "WOP-X03 standalone native self-test uses no SDK or protocol resources", context do
    assert run(context, ["--self-test"]) == %{"status" => "passed"}
  end

  defp run(context, args) do
    assert {:ok, result} =
             Command.run(Path.join(context.directory, "build_command"), %{
               id: :native_json,
               executable: Path.join(context.directory, "json_check"),
               args: args,
               cwd: context.directory,
               env: [{"LC_ALL", "C"}],
               timeout_ms: 1000,
               output_bytes: 8192,
               cleanup_ms: 500
             })

    Jason.decode!(result.output)
  end
end
