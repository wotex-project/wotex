Code.require_file("../support/software/command.exs", __DIR__)

defmodule Wotex.Matter.NativeOutputFailureInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.SoftwareCommand

  @moduletag :interop
  @moduletag :software

  test "WMA-C03 the SDK host reaps failed stdout while command input remains open" do
    harness = System.fetch_env!("WOTEX_MATTER_CONTROLLER_TEST")
    host = System.fetch_env!("WOTEX_MATTER_NATIVE_EXECUTABLE")

    assert {:ok, output} =
             SoftwareCommand.run(harness, [host],
               timeout: 2_000,
               env: [
                 {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"},
                 {"UBSAN_OPTIONS", "halt_on_error=1"}
               ]
             )

    refute output =~ ~r/AddressSanitizer|LeakSanitizer|runtime error:/
    result = output |> String.split("\n", trim: true) |> List.last()

    assert %{
             "status" => "passed",
             "cleanup_ms" => elapsed,
             "owned_processes_after_grace" => 0
           } = Jason.decode!(result)

    # Failure observed before the input poll can close immediately. A blocked
    # poll retains the watchdog path; both obey the same maximum cleanup grace.
    assert is_integer(elapsed) and elapsed >= 0 and elapsed <= 1_000
  end
end
