defmodule Wotex.BLE.NativeLane do
  @moduledoc false

  # Selects the WBL-G10 native test lane for component executables compiled by
  # ExUnit. The ordinary lane is the default suite. Sanitizer lanes are explicit:
  # `sanitizers` runs ASan/UBSan with exit-time leak scanning disabled for strict
  # timing, and `leak_audit` enables LeakSanitizer with the named custody
  # instrumentation allowance. Harness waits scale; library deadlines do not.

  @sanitizers ~w(-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all)

  @spec mode() :: :ordinary | :sanitizers | :leak_audit
  def mode do
    case System.get_env("WOTEX_BLE_NATIVE_LANE") do
      nil -> :ordinary
      "sanitizers" -> :sanitizers
      "leak_audit" -> linux!(:leak_audit)
      other -> raise ArgumentError, "unsupported WOTEX_BLE_NATIVE_LANE #{inspect(other)}"
    end
  end

  @spec flags() :: [String.t()]
  def flags, do: if(mode() == :ordinary, do: [], else: @sanitizers)

  @spec leak_audit?() :: boolean()
  def leak_audit?, do: mode() == :leak_audit

  @spec timeout(pos_integer()) :: pos_integer()
  def timeout(milliseconds) do
    # LeakSanitizer scans every instrumented process exit, including the
    # 1,000-launch custody churn; the scale bounds only harness waits.
    case mode() do
      :ordinary -> milliseconds
      :sanitizers -> milliseconds * 8
      :leak_audit -> milliseconds * 20
    end
  end

  @spec environment([{String.t(), String.t() | nil}]) :: [{String.t(), String.t() | nil}]
  def environment(base) do
    sanitizer =
      case mode() do
        :ordinary -> %{}
        :sanitizers -> options("detect_leaks=0")
        :leak_audit -> options("detect_leaks=1")
      end

    base
    |> Map.new()
    |> Map.merge(sanitizer)
    |> Enum.to_list()
  end

  defp options(leaks) do
    %{
      "ASAN_OPTIONS" => "#{leaks}:abort_on_error=1",
      "UBSAN_OPTIONS" => "print_stacktrace=1:halt_on_error=1"
    }
    |> Map.merge(symbolizer())
  end

  # Executed fixtures receive a cleared PATH. The macOS runtime otherwise reports
  # a missing atos symbolizer on every instrumented start; GCC on Linux
  # symbolizes internally.
  defp symbolizer do
    case System.find_executable("atos") do
      nil -> %{}
      atos -> %{"ASAN_SYMBOLIZER_PATH" => atos}
    end
  end

  defp linux!(mode) do
    if :os.type() == {:unix, :linux},
      do: mode,
      else: raise(ArgumentError, "LeakSanitizer lane requires Linux")
  end
end
