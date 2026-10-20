defmodule CoreArchiveAssertions do
  @moduledoc false

  use GenServer
  @impl GenServer
  def init(_), do: {:ok, %{assertions: 0, errors: 0}}
  @impl GenServer
  def handle_cast({:test_finished, %{state: {:failed, failures}}}, state) do
    assertions = Enum.count(failures, &match?({:error, %ExUnit.AssertionError{}, _}, &1))

    {:noreply,
     %{
       assertions: state.assertions + assertions,
       errors: state.errors + length(failures) - assertions
     }}
  end

  def handle_cast({:suite_finished, _}, state) do
    IO.write("\nCORE_ASSERTIONS=" <> JSON.encode!(state) <> "\n")
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}
end

ExUnit.start(
  autorun: false,
  seed: 0,
  max_cases: 1,
  timeout: 15_000,
  formatters: [ExUnit.CLIFormatter, CoreArchiveAssertions]
)

[phase, replacement] = System.argv()

if phase == "identity" do
  Code.require_file("corebluetooth_identity.exs", __DIR__)
else
  {:ok, _} = Application.ensure_all_started(:wotex_ble)

  if replacement != "baseline" do
    Code.compiler_options(ignore_module_conflict: true)
    Code.compile_file(replacement)
  end

  if phase == "build" do
    Code.require_file("corebluetooth_build.exs", __DIR__)
  else
    Code.require_file(
      "corebluetooth_#{System.fetch_env!("WOTEX_CORE_FAMILY")}_consumer.exs",
      __DIR__
    )
  end
end

result = ExUnit.run()
IO.write("\nCORE_RESULT=" <> JSON.encode!(result) <> "\n")
System.halt(if result.failures == 0, do: 0, else: 1)
