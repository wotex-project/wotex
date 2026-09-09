defmodule Wotex.Runtime.PortCall do
  @moduledoc """
  Isolates raised failures at trusted consumer callback boundaries.

  `invoke/5` calls an explicitly selected module and function in the current
  process. Ordinary return values pass through unchanged, so the caller still
  validates the callback's result contract. Raised exceptions, exits and throws
  become a `Wotex.Runtime.Error` with code `:port_exception` and the supplied phase.
  The original reason and stacktrace are discarded.

  An exception telemetry event contains the callback name and failure kind,
  plus caller-supplied identity metadata. That metadata must already be bounded
  and non-secret. This helper does not enforce a timeout, authorize a callback,
  start a worker or sanitize normal return values. Runtime owns the surrounding
  request and subscription lifecycle.
  """

  alias Wotex.Runtime.{Error, Telemetry}

  @doc """
  Invokes a consumer port and isolates exceptions, exits, and throws.

  A failure never enters a public error value; it is reported through the
  `[:wotex, :runtime, :port, :exception]` telemetry event and returned as
  `{:error, %Error{code: :port_exception}}`.
  """
  @spec invoke(module(), atom(), [term()], Error.phase(), map()) :: term()
  def invoke(module, function, arguments, phase, metadata) do
    apply(module, function, arguments)
  rescue
    _ ->
      report(:error, function, metadata)
      {:error, exception_error(phase, function)}
  catch
    kind, _ ->
      report(kind, function, metadata)
      {:error, exception_error(phase, function)}
  end

  defp report(kind, function, metadata) do
    Telemetry.execute(
      [:port, :exception],
      Map.merge(metadata, %{callback: function, kind: kind, code: :port_exception})
    )
  end

  defp exception_error(phase, function) do
    Error.new(:port_exception, phase, "consumer port raised, exited, or threw", %{
      callback: function
    })
  end
end
