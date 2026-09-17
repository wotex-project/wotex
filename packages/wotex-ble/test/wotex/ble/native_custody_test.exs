Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeCustodyTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.{NativeCommand, NativeLane}

  @root Path.expand("../../..", __DIR__)
  @fixtures @root
            |> Path.join("priv/fixtures/custody-contract-v1.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")
  @source_digest "d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2"

  setup_all do
    compiler = System.find_executable("cc") || flunk("native custody tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-custody-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    command = Path.join(directory, "command")
    guardian = Path.join(directory, "custody")
    executable = Path.join(directory, "custody-check")

    options = [
      cd: @root,
      timeout: NativeLane.timeout(15_000),
      limit: 1_048_576,
      env: NativeLane.environment(clean_environment())
    ]

    source = Path.join(@root, "priv/bluez/native/custody.c")
    assert Base.encode16(:crypto.hash(:sha256, File.read!(source)), case: :lower) == @source_digest

    assert {:ok, "", 0} =
             NativeCommand.bootstrap(
               compiler,
               Path.join(@root, "priv/bluez/native/build_command.c"),
               command,
               options
             )

    for {input, output} <- [
          {source, guardian},
          {Path.join(@root, "test/native/custody_check.c"), executable}
        ] do
      arguments =
        NativeLane.flags() ++ ["-std=c11", "-Wall", "-Wextra", "-Werror", input, "-o", output]

      assert {:ok, "", 0} = NativeCommand.run(command, compiler, arguments, options)
    end

    {:ok,
     directory: directory,
     command: command,
     guardian: guardian,
     executable: executable,
     options: Keyword.put(options, :env, NativeLane.environment(cleared_environment()))}
  end

  for fixture <- @fixtures do
    @fixture fixture
    @tag timeout: NativeLane.timeout(30_000)
    test "#{fixture["id"]} actual opaque-stream custody matches the executable fixture", context do
      fixture = @fixture
      workspace = Path.join(context.directory, fixture["id"])
      File.mkdir!(workspace)

      assert {:ok, output, 0} =
               NativeCommand.run(
                 context.command,
                 context.executable,
                 [context.guardian, fixture["id"], workspace] ++ leak_audit(),
                 context.options
               )

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

      # Only the LeakSanitizer lane grants the guardian's post-main scan its
      # named harness allowance; SDK reap keeps the production allowance.
      instrumentation = if NativeLane.leak_audit?(), do: 1000, else: 0
      assert result["cleanup_ms"] in 0..fixture["cleanup_allowance_ms"]
      assert result["guardian_exit_ms"] in 0..(fixture["cleanup_allowance_ms"] + instrumentation)
      assert result["instrumented_exit_allowance_ms"] == instrumentation
    end
  end

  defp clean_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end

  defp leak_audit, do: if(NativeLane.leak_audit?(), do: ["--leak-audit"], else: [])

  defp cleared_environment, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)
end
