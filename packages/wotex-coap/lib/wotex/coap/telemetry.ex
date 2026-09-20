defmodule Wotex.CoAP.Telemetry do
  @moduledoc false

  alias Wotex.CoAP.{Error, Message}

  @request_event [:wotex, :coap, :request, :stop]
  @error_classes [:timeout, :unavailable, :rate_limited, :protocol, :permanent]

  @doc false
  @spec request_stop(integer(), 1..4 | :get | :post | :put | :delete | :unknown, term()) :: :ok
  def request_stop(started, operation, result) when is_integer(started) do
    :telemetry.execute(
      @request_event,
      %{duration: max(System.monotonic_time() - started, 0)},
      %{
        operation: operation(operation),
        result: result(result),
        status: status(result)
      }
    )
  end

  @doc false
  @spec subscription(:open | :deliver | :close, :property | :event, :ok | Error.t()) :: :ok
  def subscription(event, kind, outcome)
      when event in [:open, :deliver, :close] and kind in [:property, :event] do
    :telemetry.execute(
      [:wotex, :coap, :subscription, event],
      %{count: 1},
      %{kind: kind, result: result(outcome)}
    )
  end

  defp operation(1), do: :get
  defp operation(2), do: :post
  defp operation(3), do: :put
  defp operation(4), do: :delete
  defp operation(operation) when operation in [:get, :post, :put, :delete], do: operation
  defp operation(_), do: :unknown

  defp result(:ok), do: :ok
  defp result({:ok, _}), do: :ok
  defp result(%Error{class: class}) when class in @error_classes, do: class
  defp result({:error, %Error{} = error}), do: result(error)
  defp result(_), do: :error

  defp status({:ok, %Message{code: code}}) when code in 0..255, do: code
  defp status({:error, %Error{details: %{code: code}}}) when code in 0..255, do: code
  defp status(_), do: nil
end
