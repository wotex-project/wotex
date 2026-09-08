defmodule WotexLabWorkbench.Investigation.OperatorRunner do
  @moduledoc "Calls the selected static BeamLens operator behind a testable boundary."

  @doc false
  @spec run(pid(), String.t(), pos_integer()) :: term()
  def run(operator, prompt, timeout) do
    Beamlens.Operator.run(operator, %{reason: prompt}, timeout: timeout)
  end
end
