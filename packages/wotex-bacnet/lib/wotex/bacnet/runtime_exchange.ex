defmodule Wotex.BACnet.RuntimeExchange do
  @moduledoc """
  Executes one Runtime Property request through an explicitly owned session.

  `Wotex.BACnet.Transport` supplies the mapped native request and its absolute
  deadline. Connect, request, returned-value validation, result construction,
  and successful cleanup consume that same budget. Reads require valid native
  values; writes require the exact `:written` acknowledgement.

  The result retains the Runtime request ID and operation. A cleanup failure
  prevents a successful result, and a late or uncertain write failure carries
  unknown effect. Callback return normalization belongs to the client boundary;
  custom clients remain responsible for honoring the budget they receive.
  """

  alias Wotex.BACnet
  alias Wotex.BACnet.{Error, Value}
  alias Wotex.Runtime.{Request, Result}

  @doc false
  @spec run(keyword(), map(), Request.t(), integer()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(options, message, request, deadline) do
    with remaining when remaining > 0 <- deadline - now(),
         {:ok, session} <- BACnet.connect(Keyword.put(options, :timeout, remaining)) do
      result = execute(session, message, request, deadline)
      cleanup = BACnet.disconnect(session)
      finish(result, cleanup, request.operation, deadline)
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp execute(session, message, request, deadline) do
    with {:ok, value} <- BACnet.send_deadline(session, message, deadline),
         :ok <- validate(value, request.operation) do
      {payload, metadata} = Value.result(value)
      Result.new(request.request_id, request.operation, payload, metadata: metadata)
    end
  end

  defp validate(value, :readproperty) do
    case Value.validate_read(value) do
      :ok -> :ok
      {:error, error} -> {:error, Error.protocol(error)}
    end
  end

  defp validate(:written, :writeproperty), do: :ok

  defp validate(_, :writeproperty),
    do: {:error, Error.with_effect(Error.new(:invalid_transport_return), :unknown)}

  defp finish({:error, _} = error, _, _, _), do: error

  defp finish({:ok, _}, {:error, error}, operation, _),
    do: {:error, Error.with_effect(error, effect(operation))}

  defp finish({:ok, _} = result, :ok, operation, deadline) do
    with :ok <- completed(deadline, effect(operation)), do: result
  end

  defp completed(deadline, effect) do
    if now() < deadline,
      do: :ok,
      else: {:error, Error.with_effect(Error.new(:deadline_exceeded), effect)}
  end

  defp effect(:writeproperty), do: :unknown
  defp effect(_), do: :none
  defp now, do: System.monotonic_time(:millisecond)
end
