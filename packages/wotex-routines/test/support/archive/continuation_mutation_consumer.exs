defmodule ContinuationMutationAssertions do
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
    IO.write("\nCONTINUATION_ASSERTIONS=" <> JSON.encode!(state) <> "\n")
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}
end

ExUnit.start(
  autorun: false,
  seed: 0,
  max_cases: 1,
  formatters: [ExUnit.CLIFormatter, ContinuationMutationAssertions]
)

[replacement] = System.argv()

if replacement != "baseline" do
  Code.compiler_options(ignore_module_conflict: true)
  Code.compile_file(replacement)
end

Code.require_file("test/continuation_consumer_test.exs")
result = ExUnit.run()
IO.write("CONTINUATION_RESULT=" <> JSON.encode!(result) <> "\n")
System.halt(if result.failures == 0, do: 0, else: 1)
