defmodule Wotex.BACnet.RuntimeNative do
  @moduledoc """
  Owns the worker that establishes a native session for a Runtime relay.

  The worker first transfers session information to
  `Wotex.BACnet.RuntimeRelay`, then waits for an explicit subscription handoff.
  Connect and subscribe share the relay's absolute deadline. The worker stays
  alive after reporting establishment so the first-party session retains its
  creating process until cleanup.

  Normal close delegates to the native operation owner or the custom client's
  unsubscribe and disconnect callbacks. Forced first-party cleanup targets only
  the owned operation, subscription, and explicitly owned stack resources.
  Borrowed SDK clients are preserved; arbitrary custom resources cannot be
  forcefully reclaimed by this helper.
  """

  alias Wotex.BACnet
  alias Wotex.BACnet.{BACstack, Error, IPv4, OperationOwner, Session, StackOwner, Subscription}

  @doc false
  @spec start(pid(), reference(), map()) :: {pid(), reference()}
  def start(parent, token, options) do
    {worker, monitor} =
      :erlang.spawn_opt(fn -> open(parent, token, options) end, [:link, :monitor])

    {worker, monitor}
  end

  @doc false
  @spec close(Session.t() | nil, term(), integer()) :: :ok | {:error, Error.t()}
  def close(nil, _, _), do: :ok

  def close(%Session{client: BACstack, handle: %{owner: owner}}, _, deadline),
    do: OperationOwner.close(owner, deadline)

  def close(%Session{client: IPv4, handle: %{stack: %{owner: owner}}}, _, deadline),
    do: OperationOwner.close(owner, deadline)

  def close(%Session{} = session, subscription, deadline) do
    try do
      if subscription do
        timeout = max(min(deadline - now(), session.timeout), 1)
        BACnet.unsubscribe(%{session | timeout: timeout}, subscription)
      else
        :ok
      end
    after
      BACnet.disconnect(session)
    end
  end

  @doc false
  @spec abort(Session.t() | nil, term(), integer()) :: :ok
  def abort(%Session{client: BACstack, handle: config}, subscription, deadline),
    do: abort_stack(config, subscription, deadline)

  def abort(%Session{client: IPv4, handle: %{stack: config}}, subscription, deadline),
    do: abort_stack(config, subscription, deadline)

  def abort(_, _, _), do: :ok

  defp abort_stack(config, subscription, deadline) do
    if config.owned_stack, do: StackOwner.close(config.owned_stack, deadline)
    Process.exit(config.owner, :kill)
    if Subscription.valid?(subscription), do: Process.exit(subscription.pid, :kill)
    :ok
  end

  @doc false
  @spec valid_subscription?(Session.t() | nil, term()) :: boolean()
  def valid_subscription?(session, subscription) do
    Subscription.valid?(subscription) and Process.alive?(subscription.pid) and
      valid_generation?(session, subscription.session_generation)
  end

  defp valid_generation?(%Session{client: BACstack, handle: %{generation: generation}}, generation),
    do: true

  defp valid_generation?(
         %Session{client: IPv4, handle: %{stack: %{generation: generation}}},
         generation
       ),
       do: true

  defp valid_generation?(%Session{client: client}, _) when client not in [BACstack, IPv4], do: true
  defp valid_generation?(_, _), do: false

  defp open(parent, token, options) do
    with remaining when remaining > 0 <- options.deadline - now(),
         {:ok, session} <- BACnet.connect(Keyword.put(options.client_options, :timeout, remaining)) do
      send(parent, {:runtime_session, token, self(), session})

      receive do
        {:subscribe, ^token, receiver} ->
          result = subscribe(session, options.request, receiver, options.deadline)
          send(parent, {:runtime_subscribed, token, self(), result})
          hold(token)
      after
        max(options.deadline - now(), 0) ->
          send(
            parent,
            {:runtime_subscribed, token, self(), {:error, Error.new(:deadline_exceeded)}}
          )

          hold(token)
      end
    else
      {:error, _} = error ->
        send(parent, {:runtime_subscribed, token, self(), error})
        hold(token)

      _ ->
        send(parent, {:runtime_subscribed, token, self(), {:error, Error.new(:deadline_exceeded)}})
        hold(token)
    end
  end

  defp subscribe(session, request, receiver, deadline) do
    message =
      request
      |> Map.from_struct()
      |> Map.put(:receiver, receiver)

    BACnet.subscribe_deadline(session, message, deadline)
  end

  defp hold(token) do
    receive do
      {:halt, ^token} -> :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
