defmodule Wotex.BACnet.NativeCall do
  @moduledoc """
  Preserves a native request deadline across client dispatch and return.

  An expired request returns an internal `:not_started` outcome before invoking
  a callback. First-party clients receive the absolute deadline; other clients
  receive the remaining milliseconds through `Wotex.BACnet.PortCall`.

  Successful single-operation responses arriving after expiry become deadline
  errors. A write then carries unknown effect because transmission may already
  have occurred. Batch completion checks belong to `Wotex.BACnet.NativeHelpers`
  and `Wotex.BACnet.Batch`. This helper does not independently interrupt a
  custom client callback.
  """

  alias Wotex.BACnet.{Error, PortCall, Session}

  @doc false
  @spec invoke(Session.t(), :request | :read_properties, term(), integer()) ::
          {:ok, term()} | {:error, Error.t()} | {:not_started, Error.t()}
  def invoke(session, operation, request, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      session
      |> dispatch(operation, request, deadline, remaining)
      |> finish(request, deadline)
    else
      {:not_started, Error.new(:deadline_exceeded)}
    end
  end

  defp dispatch(%{client: client, handle: handle}, operation, request, deadline, _)
       when client in [Wotex.BACnet.BACstack, Wotex.BACnet.IPv4] do
    function = if operation == :request, do: :request_deadline, else: :read_properties_deadline
    PortCall.invoke(client, function, [handle, request, deadline])
  end

  defp dispatch(session, :request, request, _, remaining),
    do: PortCall.invoke(session.client, :request, [session.handle, request, remaining])

  defp dispatch(session, :read_properties, requests, _, remaining),
    do: PortCall.optional(session.client, :read_properties, [session.handle, requests, remaining])

  defp finish({:ok, _} = result, requests, _) when is_list(requests), do: result

  defp finish({:ok, _} = result, request, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      result
    else
      effect = if match?(%{type: :write_property}, request), do: :unknown, else: :none
      {:error, Error.with_effect(Error.new(:deadline_exceeded), effect)}
    end
  end

  defp finish({:error, _} = error, _, _), do: error
end
