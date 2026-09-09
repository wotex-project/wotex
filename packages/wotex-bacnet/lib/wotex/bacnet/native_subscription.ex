defmodule Wotex.BACnet.NativeSubscription do
  @moduledoc false

  alias Wotex.BACnet.{BACstack, COVRequest, Error, IPv4, PortCall, Session, Subscription}

  @doc false
  @spec open(term(), term(), term()) :: {:ok, Subscription.t()} | {:error, Error.t()}
  def open(%Session{client: client, timeout: timeout} = session, request, deadline)
      when is_atom(client) and not is_nil(client) and is_integer(timeout) and
             timeout in 1..60_000 and is_integer(deadline) do
    with {:ok, request} <- COVRequest.new(request, self()),
         remaining when remaining > 0 <- deadline - now(),
         {:ok, subscription} <- dispatch(session, request, deadline, min(remaining, timeout)) do
      finish(session, subscription, deadline)
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  def open(_, _, _), do: {:error, Error.new(:invalid_subscription)}

  defp dispatch(%{client: client} = session, request, deadline, _)
       when client in [BACstack, IPv4],
       do:
         PortCall.invoke(client, :subscribe_deadline, [
           session.handle,
           request,
           request.receiver,
           deadline,
           session.timeout
         ])

  defp dispatch(session, request, _, remaining),
    do:
      PortCall.optional(session.client, :subscribe, [
        session.handle,
        request,
        request.receiver,
        remaining
      ])

  defp finish(session, subscription, deadline) do
    cond do
      not Subscription.valid?(subscription) or not Process.alive?(subscription.pid) ->
        {:error, Error.new(:invalid_transport_return)}

      now() >= deadline ->
        PortCall.optional(session.client, :unsubscribe, [
          session.handle,
          subscription,
          min(session.timeout, 1000)
        ])

        {:error, Error.new(:deadline_exceeded)}

      true ->
        {:ok, subscription}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
