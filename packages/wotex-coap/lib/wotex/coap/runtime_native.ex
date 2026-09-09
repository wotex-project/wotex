defmodule Wotex.CoAP.RuntimeNative do
  @moduledoc """
  Performs native session establishment and cleanup for a CoAP Runtime relay.

  An explicitly started linked worker opens the configured session under one
  monotonic deadline. It reports the session to `Wotex.CoAP.RuntimeRelay`, waits
  for permission to register Observe, and returns the resulting subscription.
  The relay verifies the worker, owner, numeric endpoint, and generation through
  library-owned process markers before accepting either resource.

  Closing spends the remaining operation budget on native cancellation and
  always aborts the exact connection afterward. An expired cancellation budget
  remains an error even when local resources are released. The worker retains
  only its generation after establishment; it receives no Runtime execution
  context. This module is an internal transport mechanism, not a connection
  pool or consumer supervision policy.
  """

  alias Wotex.CoAP
  alias Wotex.CoAP.{Connection, Error, Subscription}

  @doc false
  @spec start(pid(), reference(), map()) :: {pid(), reference()}
  def start(parent, generation, options) do
    {worker, monitor} =
      :erlang.spawn_opt(fn -> open(parent, generation, options) end, [:link, :monitor])

    {worker, monitor}
  end

  @doc false
  @spec close(CoAP.session() | nil, term(), integer()) :: :ok | {:error, Error.t()}
  def close(nil, _, _), do: :ok

  def close(session, subscription, deadline) do
    try do
      cancel(session, subscription, deadline - now())
    after
      Connection.abort(session.pid)
    end
  end

  defp cancel(session, nil, _), do: CoAP.disconnect(session)

  defp cancel(session, subscription, remaining) when remaining > 0,
    do: CoAP.unsubscribe(%{session | timeout: min(session.timeout, remaining)}, subscription)

  defp cancel(session, _, _) do
    CoAP.disconnect(session)
    {:error, Error.new(:deadline_exceeded)}
  end

  @doc false
  @spec abort(CoAP.session() | nil) :: :ok | {:error, Error.t()}
  def abort(nil), do: :ok
  def abort(session), do: Connection.abort(session.pid)

  @doc false
  @spec valid_session?(term(), pid(), pid(), keyword()) :: boolean()
  def valid_session?(%{pid: pid, timeout: timeout} = value, worker, owner, options)
      when map_size(value) == 2 and is_pid(pid) and node(pid) == node() and timeout in 1..60_000 do
    with {:ok, config} <- Connection.config(options),
         expected = %{owner: owner, creator: worker, host: config.host, port: config.port},
         {{:dictionary, :wotex_coap_route}, ^expected} <-
           :erlang.process_info(pid, {:dictionary, :wotex_coap_route}),
         do: true,
         else: (_ -> false)
  end

  def valid_session?(_, _, _, _), do: false

  @doc false
  @spec valid_subscription?(CoAP.session() | nil, term()) :: boolean()
  def valid_subscription?(%{pid: pid}, subscription) do
    Subscription.validate(subscription, pid) == :ok and
      :erlang.process_info(pid, {:dictionary, :wotex_coap_owner}) ==
        {{:dictionary, :wotex_coap_owner}, {Connection, subscription.generation}}
  end

  def valid_subscription?(_, _), do: false

  defp open(parent, generation, options) do
    with remaining when remaining > 0 <- options.deadline - now(),
         config = Keyword.merge(options.connection_options, owner: parent, timeout: remaining),
         {:ok, session} <- CoAP.connect(config) do
      send(parent, {:runtime_session, generation, self(), session})

      receive do
        {:subscribe, ^generation} ->
          result = subscribe(session, options, parent)
          send(parent, {:runtime_subscribed, generation, self(), result})
          hold(generation)
      after
        max(options.deadline - now(), 0) ->
          send(
            parent,
            {:runtime_subscribed, generation, self(), {:error, Error.new(:deadline_exceeded)}}
          )

          hold(generation)
      end
    else
      {:error, _} = result ->
        send(parent, {:runtime_subscribed, generation, self(), result})
        hold(generation)

      _ ->
        send(
          parent,
          {:runtime_subscribed, generation, self(), {:error, Error.new(:deadline_exceeded)}}
        )

        hold(generation)
    end
  end

  defp subscribe(session, options, parent) do
    remaining = options.deadline - now()

    if remaining > 0,
      do:
        CoAP.subscribe(%{session | timeout: remaining}, %{
          path: options.path,
          receiver: parent,
          renew: options.renew,
          max_queue_length: options.max_queue_length
        }),
      else: {:error, Error.new(:deadline_exceeded)}
  end

  defp hold(generation) do
    receive do
      {:halt, ^generation} -> :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
