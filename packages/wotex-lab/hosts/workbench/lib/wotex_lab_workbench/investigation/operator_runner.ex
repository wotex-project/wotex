defmodule WotexLabWorkbench.Investigation.OperatorRunner do
  @moduledoc """
  Invokes the explicitly selected BeamLens operator for an investigation.

  The adapter passes the supplied prompt as the invocation reason and forwards
  the caller's timeout to the dependency's public API. It returns the dependency
  result unchanged. Admission, queue refusal, cancellation and result validation
  belong to the surrounding investigation owner; this adapter does not provide
  those guarantees by itself. Tests can supply another runner at that boundary.
  """

  @doc false
  @spec run(pid(), String.t(), pos_integer()) :: term()
  def run(operator, prompt, timeout) do
    Beamlens.Operator.run(operator, %{reason: prompt}, timeout: timeout)
  end
end
