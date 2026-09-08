defmodule Wotex.Runtime.PortCall do
  @moduledoc false

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
    _exception ->
      report(:error, function, metadata)
      {:error, exception_error(phase, function)}
  catch
    kind, _reason ->
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
