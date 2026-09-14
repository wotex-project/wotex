Code.require_file("../../support/software/command.exs", __DIR__)

defmodule Wotex.Matter.NativeContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.SoftwareCommand

  @moduletag :software
  @fixture "docs/specs/fixtures/native-port-v1.json"

  test "WMA-B-F01 through F05 execute the shared native request validator" do
    fixture = fixture!()
    selected = Enum.filter(fixture["cases"], &(&1["operation"] == "parse_request"))
    assert Enum.map(selected, & &1["id"]) == Enum.map(1..5, &"WMA-B-F0#{&1}")
    executable = System.fetch_env!("WOTEX_MATTER_CONTRACT_DRIVER")

    directory =
      Path.join(System.tmp_dir!(), "wotex-native-corpus-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)

    try do
      for item <- selected do
        assert item["expectation"]["operator"] == "exact"
        path = Path.join(directory, item["id"])
        File.write!(path, item["input"]["line_utf8"], [:exclusive])

        assert {:ok, output} =
                 SoftwareCommand.run(executable, [item["operation"], path],
                   timeout: 1_000,
                   env: [
                     {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"},
                     {"UBSAN_OPTIONS", "halt_on_error=1"}
                   ]
                 )

        assert Jason.decode!(output) == item["expectation"]["value"], item["id"]
      end
    after
      File.rm_rf!(directory)
    end
  end

  test "WMA-B-F06 captures the real native ready frame and reaps its closed input" do
    item = Enum.find(fixture!()["cases"], &(&1["id"] == "WMA-B-F06"))
    assert item["operation"] == "ready"
    assert item["input"] == %{"stdin" => "close_after_ready"}
    executable = System.fetch_env!("WOTEX_MATTER_NATIVE_EXECUTABLE")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [:binary, :exit_status, :use_stdio, {:line, 131_072}]
      )

    {:os_pid, child} = Port.info(port, :os_pid)

    try do
      assert_receive {^port, {:data, {:eol, bytes}}}, 1_000
      Port.close(port)
      remaining = surviving_child(child, 100)
      observation = %{"frame" => Jason.decode!(bytes), "owned_processes_after_grace" => remaining}
      assert observation == item["expectation"]["value"]
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp surviving_child(_, 0), do: 1

  defp surviving_child(pid, remaining) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        surviving_child(pid, remaining - 1)

      {_, _} ->
        0
    end
  end

  defp fixture! do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    assert fixture["format"] == "wotex.native-contract"
    assert fixture["version"] == "1.0.0"
    assert fixture["package"] == "wotex_matter"

    assert Enum.map(fixture["cases"], & &1["id"]) ==
             Enum.map(1..17, &"WMA-B-F#{String.pad_leading(Integer.to_string(&1), 2, "0")}")

    assert Enum.all?(
             fixture["cases"],
             &(&1["operation"] in [
                 "parse_request",
                 "ready",
                 "flow_trace",
                 "process_flow",
                 "result_budget"
               ])
           )

    fixture
  end
end
