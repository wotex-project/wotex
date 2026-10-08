defmodule Wotex.Zigbee.Downlinks do
  @moduledoc """
  Consumer-owned finite AF downlinks with explicit lifetime and custody checks.

  This inert queue performs no I/O, polling, wakeup, retry or authorization.
  A consumer admits each `Wotex.Zigbee.DataRequest`, supplies monotonic time
  and retains the latest returned queue. Counts are bounded globally and per
  raw IEEE peer, alongside a total payload-byte budget. Overflow refuses the
  new entry; it never silently drops an older command.

  `take/5` selects a peer's FIFO entries only when the consumer explicitly
  decides to attempt delivery. It expires old entries and checks the selected
  requests against current `Wotex.Zigbee.Routes` custody. Removed entries are
  returned separately as ready, expired or refused. A ready entry remains
  inert; its deadline is the earlier of its queue expiry and custody expiry.
  Pass it to `Wotex.Zigbee.send_queued_data/4` to enforce that absolute budget
  at the receiver. Retain actual NCP, APS and ZCL observations separately.

  Selection does not establish wakefulness, authentication or delivery.
  The consumer owns check-in interpretation, fresh transaction/sequence
  context, binding and battery policy. Queue expiry does not declare a quiet
  peer offline. Requests retain their original route and payload; rejoin does
  not silently retarget a command. Rebinding an owner invalidates all entries.
  Receipts remain consumer-owned values; validation does not prove prior
  enqueue or prevent an explicit consumer change to that context.
  """

  alias Wotex.Zigbee.{DataRequest, Error, Routes}

  @max_ticket 0xFFFFFFFFFFFFFFFF
  @max_time 0x7FFFFFFFFFFFFFFF
  @max_lifetime_ms 86_400_000
  @fields [:epoch, :capacity, :per_peer, :max_bytes, :generation, :last_now_ms, :entries]
  @entry_fields [:ticket, :request, :enqueued_at_ms, :expires_at_ms]
  @options [:capacity, :per_peer, :max_bytes]

  @enforce_keys [:epoch, :capacity, :per_peer, :max_bytes]
  defstruct @enforce_keys ++ [generation: 0, last_now_ms: nil, entries: []]

  @type entry :: %{
          ticket: pos_integer(),
          request: DataRequest.t(),
          enqueued_at_ms: integer(),
          expires_at_ms: integer()
        }
  @type delivery :: %{entry: entry(), deadline_ms: integer(), owner_epoch: reference()}
  @type refusal :: %{entry: entry(), reason: Error.kind()}
  @opaque t :: %__MODULE__{
            epoch: reference(),
            capacity: 1..1_024,
            per_peer: 1..128,
            max_bytes: 1..131_072,
            generation: non_neg_integer(),
            last_now_ms: integer() | nil,
            entries: [entry()]
          }

  @doc """
  Builds an empty queue for one owner epoch with explicit host budgets.

  Options are `capacity` (default 128, maximum 1,024), `per_peer` (default 8,
  maximum 128) and `max_bytes` (default 16,384, maximum 131,072). The byte
  budget counts AF payload bytes; finite entries and correlation lengths bound
  the other request fields. No clock or owner starts here.
  """
  @spec new(reference(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(epoch, options \\ [])

  def new(epoch, options) when is_reference(epoch) and is_list(options) do
    if Keyword.keyword?(options) and length(options) <= 3 and
         Enum.all?(Keyword.keys(options), &(&1 in @options)) and
         length(options) == length(Enum.uniq(Keyword.keys(options))) do
      queue = %__MODULE__{
        epoch: epoch,
        capacity: Keyword.get(options, :capacity, 128),
        per_peer: Keyword.get(options, :per_peer, 8),
        max_bytes: Keyword.get(options, :max_bytes, 16_384)
      }

      if valid?(queue), do: {:ok, queue}, else: failure(:invalid_value)
    else
      failure(:invalid_value)
    end
  end

  def new(_, _), do: failure(:invalid_value)

  @doc "Revalidates complete queue fields, requests, ordering and all budgets after copying."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = queue) do
    complete?(queue, @fields, true) and is_reference(queue.epoch) and
      in_range?(queue.capacity, 1, 1_024) and in_range?(queue.per_peer, 1, 128) and
      in_range?(queue.max_bytes, 1, 131_072) and
      in_range?(queue.generation, 0, @max_ticket) and
      (queue.last_now_ms == nil or valid_time?(queue.last_now_ms)) and
      is_list(queue.entries) and length(queue.entries) <= queue.capacity and
      valid_entries?(queue) and within_budgets?(queue, queue.entries)
  end

  def valid?(_), do: false

  @doc "Revalidates a complete inert delivery receipt and its supplied finite absolute lifetime."
  @spec valid_delivery?(term()) :: boolean()
  def valid_delivery?(delivery) when is_map(delivery) do
    complete?(delivery, [:entry, :deadline_ms, :owner_epoch], false) and
      is_reference(delivery.owner_epoch) and base_entry?(delivery.entry) and
      valid_time?(delivery.deadline_ms) and
      delivery.deadline_ms > delivery.entry.enqueued_at_ms and
      delivery.deadline_ms <= delivery.entry.expires_at_ms
  end

  def valid_delivery?(_), do: false

  @doc """
  Enqueues one explicit request for 1 ms to 24 hours without dispatching it.

  Expired entries continue to occupy capacity until `expire/2` or `take/5`
  explicitly removes them. Duplicate pending correlation IDs for the same
  peer fail. Queue tickets never wrap; context/token allocation remains with
  the consumer. A refused admission leaves the queue unchanged.
  """
  @spec enqueue(t(), DataRequest.t(), integer(), pos_integer()) ::
          {:ok, %{queue: t(), ticket: pos_integer()}} | {:error, Error.t()}
  def enqueue(queue, request, now, lifetime_ms) do
    with :ok <- admission(queue, now),
         true <- DataRequest.valid?(request),
         true <- in_range?(lifetime_ms, 1, @max_lifetime_ms),
         true <- valid_time?(now + lifetime_ms),
         :ok <- entry_admission(queue, request) do
      ticket = queue.generation + 1

      entry = %{
        ticket: ticket,
        request: request,
        enqueued_at_ms: now,
        expires_at_ms: now + lifetime_ms
      }

      updated = %{
        queue
        | entries: Enum.concat(queue.entries, [entry]),
          generation: ticket,
          last_now_ms: now
      }

      {:ok, %{queue: updated, ticket: ticket}}
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  @doc "Returns expired entries in original FIFO order and removes them without delivery."
  @spec expire(t(), integer()) :: {:ok, %{queue: t(), expired: [entry()]}} | {:error, Error.t()}
  def expire(queue, now) do
    with :ok <- admission(queue, now) do
      {expired, retained} = Enum.split_with(queue.entries, &(&1.expires_at_ms <= now))
      {:ok, %{queue: %{queue | entries: retained, last_now_ms: now}, expired: expired}}
    end
  end

  @doc """
  Removes up to `limit` FIFO entries for an explicitly selected peer.

  The limit is 1 through the configured per-peer bound, default 1. All expired
  entries are returned separately first. Every selected request receives a
  current custody check, including route, epoch, conflict and expiry. A refused
  request is removed and returned with its bounded reason, never retried or
  retargeted. Retain the returned queue before attempting any ready entry.
  """
  @spec take(t(), Routes.t(), binary(), integer(), pos_integer()) ::
          {:ok, %{queue: t(), ready: [delivery()], refused: [refusal()], expired: [entry()]}}
          | {:error, Error.t()}
  def take(queue, routes, peer_ieee, now, limit \\ 1) do
    with :ok <- admission(queue, now),
         true <- Routes.valid?(routes) and valid_ieee?(peer_ieee),
         true <- in_range?(limit, 1, queue.per_peer),
         :ok <- same_epoch(queue.epoch, routes.epoch),
         {:ok, %{queue: current, expired: expired}} <- expire(queue, now) do
      {selected, retained} = select(current.entries, peer_ieee, limit)
      {ready, refused} = classify(selected, routes, queue.epoch, now)

      {:ok,
       %{
         queue: %{current | entries: retained},
         ready: ready,
         refused: refused,
         expired: expired
       }}
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  @doc "Cancels one pending ticket explicitly; cancellation is no delivery observation."
  @spec cancel(t(), pos_integer()) ::
          {:ok, %{queue: t(), cancelled: entry()}} | {:error, Error.t()}
  def cancel(queue, ticket) do
    if valid?(queue) and in_range?(ticket, 1, queue.generation) do
      case Enum.split_with(queue.entries, &(&1.ticket == ticket)) do
        {[entry], retained} -> {:ok, %{queue: %{queue | entries: retained}, cancelled: entry}}
        _ -> failure(:invalid_value)
      end
    else
      failure(:invalid_value)
    end
  end

  @doc "Invalidates all queued requests on explicit epoch replacement, retaining ticket history."
  @spec rebind(t(), reference()) ::
          {:ok, %{queue: t(), invalidated: [entry()]}} | {:error, Error.t()}
  def rebind(queue, epoch) do
    if valid?(queue) and is_reference(epoch) and epoch != queue.epoch do
      {:ok, %{queue: %{queue | epoch: epoch, entries: []}, invalidated: queue.entries}}
    else
      failure(:invalid_value)
    end
  end

  defp select(entries, peer, limit) do
    {selected, retained, _} =
      Enum.reduce(entries, {[], [], limit}, fn entry, {selected, retained, left} ->
        if left > 0 and entry.request.peer_ieee == peer,
          do: {[entry | selected], retained, left - 1},
          else: {selected, [entry | retained], left}
      end)

    {Enum.reverse(selected), Enum.reverse(retained)}
  end

  defp classify(entries, routes, epoch, now) do
    {ready, refused} =
      Enum.reduce(entries, {[], []}, fn entry, {ready, refused} ->
        case Routes.check_request(routes, entry.request, epoch, now) do
          {:ok, custody_expiry} ->
            delivery = %{
              entry: entry,
              owner_epoch: epoch,
              deadline_ms: min(entry.expires_at_ms, custody_expiry)
            }

            {[delivery | ready], refused}

          {:error, %Error{kind: kind}} ->
            {ready, [%{entry: entry, reason: kind} | refused]}
        end
      end)

    {Enum.reverse(ready), Enum.reverse(refused)}
  end

  defp entry_admission(queue, request) do
    cond do
      queue.generation == @max_ticket -> failure(:correlation_exhausted)
      duplicate?(queue.entries, request) -> failure(:invalid_value)
      length(queue.entries) == queue.capacity -> failure(:overload)
      peer_count(queue.entries, request.peer_ieee) >= queue.per_peer -> failure(:overload)
      payload_bytes(queue.entries) + byte_size(request.data) > queue.max_bytes -> failure(:overload)
      true -> :ok
    end
  end

  defp duplicate?(entries, request),
    do:
      Enum.any?(entries, fn entry ->
        entry.request.peer_ieee == request.peer_ieee and
          entry.request.correlation_id == request.correlation_id
      end)

  defp valid_entries?(queue) do
    Enum.reduce_while(queue.entries, 0, fn entry, previous ->
      if valid_entry?(entry, queue, previous),
        do: {:cont, entry.ticket},
        else: {:halt, false}
    end) != false and
      distinct_contexts?(queue.entries)
  end

  defp valid_entry?(entry, queue, previous) do
    base_entry?(entry) and
      in_range?(entry.ticket, previous + 1, queue.generation) and
      valid_time?(queue.last_now_ms) and entry.enqueued_at_ms <= queue.last_now_ms
  end

  defp base_entry?(entry) do
    is_map(entry) and complete?(entry, @entry_fields, false) and
      in_range?(entry.ticket, 1, @max_ticket) and DataRequest.valid?(entry.request) and
      valid_time?(entry.enqueued_at_ms) and valid_time?(entry.expires_at_ms) and
      in_range?(entry.expires_at_ms - entry.enqueued_at_ms, 1, @max_lifetime_ms)
  end

  defp distinct_contexts?(entries) do
    contexts = Enum.map(entries, &{&1.request.peer_ieee, &1.request.correlation_id})
    length(contexts) == length(Enum.uniq(contexts))
  end

  defp within_budgets?(queue, entries) do
    payload_bytes(entries) <= queue.max_bytes and
      Enum.all?(Enum.frequencies_by(entries, & &1.request.peer_ieee), fn {_, count} ->
        count <= queue.per_peer
      end)
  end

  defp payload_bytes(entries), do: Enum.reduce(entries, 0, &(byte_size(&1.request.data) + &2))
  defp peer_count(entries, peer), do: Enum.count(entries, &(&1.request.peer_ieee == peer))

  defp admission(queue, now) do
    cond do
      not valid?(queue) or not valid_time?(now) -> failure(:invalid_value)
      queue.last_now_ms != nil and now < queue.last_now_ms -> failure(:stale_observation)
      true -> :ok
    end
  end

  defp complete?(map, keys, struct),
    do:
      map_size(map) == length(keys) + if(struct, do: 1, else: 0) and
        Enum.all?(keys, &Map.has_key?(map, &1))

  defp same_epoch(epoch, epoch), do: :ok
  defp same_epoch(_, _), do: failure(:stale_epoch)
  defp valid_ieee?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp valid_ieee?(_), do: false
  defp valid_time?(value), do: in_range?(value, -@max_time, @max_time)
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :downlinks}}
end
