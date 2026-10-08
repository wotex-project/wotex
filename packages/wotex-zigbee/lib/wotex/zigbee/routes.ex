defmodule Wotex.Zigbee.Routes do
  @moduledoc """
  Consumer-owned, finite IEEE-to-route custody from explicitly adopted interviews.

  The table has no process, clock or persistence side effect. Its epoch comes
  from a complete `Wotex.Zigbee.Interview.Result`. Callers supply monotonic
  milliseconds to adoption and resolution and retain the returned table,
  including the updated table returned on a conflict. Adoption is a consumer
  decision; matching IEEE bytes does not authenticate a radio peer.

  Entries are keyed by raw IEEE identity, never manufacturer/model labels.
  A rejoin replaces that identity's route. A different identity claiming an
  occupied route quarantines both claims; forgetting one does not promote the
  other. At capacity, an occupied route is still quarantined and retains the
  latest conflicting identity. The consumer retains full interview history.

  `rebind/2` retains peer records but invalidates their source authority for a
  new owner epoch. A new complete interview is required before using a route.
  Expiry limits route custody; it does not establish that a sleepy peer is
  offline. Lifetimes are at most 24 hours from the identity observation, and
  adopting the same old result cannot refresh that observation.
  An older owner observation cannot move a peer back to its prior route.

  Supply the current table to `Wotex.Zigbee.send_routed_data/4`; immutable old
  snapshots remain values and cannot detect a consumer's newer decisions.
  `resolve/3` preserves the original Event and its security disposition.
  Neither operation grants authorization, canonical truth or replay proof.
  """

  alias Wotex.Zigbee.{DataRequest, Error, Event, Reply}
  alias Wotex.Zigbee.Interview.Result

  @max_generation 0xFFFFFFFFFFFFFFFF
  @max_time 0x7FFFFFFFFFFFFFFF
  @entry_keys [
    :peer_ieee,
    :route_address,
    :owner_epoch,
    :generation,
    :observed_at_ms,
    :expires_at_ms,
    :status,
    :last_conflict,
    :owner_sequence
  ]

  @enforce_keys [:epoch, :capacity]
  defstruct [:epoch, :capacity, generation: 0, entries: %{}]

  @type entry :: %{
          peer_ieee: <<_::64>>,
          route_address: 0..0xFFF7,
          owner_epoch: reference(),
          owner_sequence: pos_integer(),
          generation: pos_integer(),
          observed_at_ms: integer(),
          expires_at_ms: integer(),
          status: :current | :unverified | :conflicted,
          last_conflict: <<_::64>> | nil
        }
  @opaque t :: %__MODULE__{
            epoch: reference(),
            capacity: 1..1_024,
            generation: non_neg_integer(),
            entries: %{binary() => entry()}
          }

  @doc "Builds an empty inert table for one owner epoch, with at most 1,024 peers."
  @spec new(reference(), pos_integer()) :: {:ok, t()} | {:error, Error.t()}
  def new(epoch, capacity \\ 128)

  def new(epoch, capacity) when is_reference(epoch) and capacity in 1..1_024,
    do: {:ok, %__MODULE__{epoch: epoch, capacity: capacity}}

  def new(_, _), do: failure(:invalid_value)

  @doc "Checks complete table fields and bounded entries after a consumer copies a value."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = table) do
    map_size(table) == 5 and
      Enum.all?([:epoch, :capacity, :generation, :entries], &Map.has_key?(table, &1)) and
      is_reference(table.epoch) and
      in_range?(table.capacity, 1, 1_024) and
      in_range?(table.generation, 0, @max_generation) and is_map(table.entries) and
      map_size(table.entries) <= table.capacity and
      Enum.all?(table.entries, fn {ieee, entry} -> valid_entry?(ieee, entry, table.generation) end)
  end

  def valid?(_), do: false

  @doc "Retains records while fencing their authority to a newly selected owner epoch."
  @spec rebind(t(), reference()) :: {:ok, t()} | {:error, Error.t()}
  def rebind(table, epoch) do
    cond do
      not valid?(table) or not is_reference(epoch) ->
        failure(:invalid_value)

      epoch == table.epoch ->
        failure(:invalid_value)

      table.generation == @max_generation ->
        failure(:correlation_exhausted)

      true ->
        entries =
          Map.new(table.entries, fn {ieee, entry} ->
            status = if entry.status == :conflicted, do: :conflicted, else: :unverified
            {ieee, %{entry | status: status}}
          end)

        {:ok, %{table | epoch: epoch, generation: table.generation + 1, entries: entries}}
    end
  end

  @doc """
  Adopts a complete matching interview with a finite lifetime from its identity observation.

  On conflict, the third element is the updated quarantined table. On other
  refusals it is the original table, or nil for an invalid table. Retain it
  before dispatching or resolving further traffic.
  """
  @spec adopt(t(), Result.t(), integer(), pos_integer()) ::
          {:ok, t()} | {:error, Error.t(), t() | nil}
  def adopt(table, result, now, lifetime_ms) do
    with :ok <- table_admission(table),
         {:ok, entry} <- interview_entry(result, now, lifetime_ms),
         :ok <- same_epoch(table.epoch, entry.owner_epoch),
         :ok <- generation_admission(table) do
      insert(table, entry)
    else
      {:error, error} -> {:error, error, if(valid?(table), do: table)}
    end
  end

  @doc "Returns bounded peer records in deterministic raw-IEEE order."
  @spec entries(t()) :: {:ok, [entry()]} | {:error, Error.t()}
  def entries(table) do
    with :ok <- table_admission(table) do
      entries =
        table.entries
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&elem(&1, 1))

      {:ok, entries}
    end
  end

  @doc "Forgets one peer without granting authority to any remaining conflicted peer."
  @spec forget(t(), binary()) :: {:ok, t()} | {:error, Error.t()}
  def forget(table, ieee) do
    with :ok <- table_admission(table),
         true <- valid_ieee?(ieee),
         :ok <- generation_admission(table) do
      {:ok, %{table | entries: Map.delete(table.entries, ieee), generation: table.generation + 1}}
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  @doc "Resolves a received source through current custody, retaining the unchanged Event."
  @spec resolve(t(), Event.t(), integer()) ::
          {:ok, %{entry: entry(), event: Event.t()}} | {:error, Error.t()}
  def resolve(table, %Event{} = event, now) do
    with :ok <- table_admission(table),
         :ok <- same_epoch(table.epoch, event.owner_epoch),
         {:ok, entry} <- source_entry(table, event.source_address),
         :ok <- usable(entry, table.epoch, now),
         :ok <- observation_admission(event, entry, now) do
      {:ok, %{entry: entry, event: event}}
    end
  end

  def resolve(_, _, _), do: failure(:invalid_value)

  @doc """
  Checks an explicit raw IEEE peer and unicast route in current receiver custody.

  Return the custody expiry for an explicitly selected peer operation. This
  supplies host mapping only; it grants no permission to configure a device
  or select a binding destination. Immutable old tables cannot observe newer
  consumer decisions.
  """
  @spec check_peer(t(), binary(), non_neg_integer(), reference(), integer()) ::
          {:ok, integer()} | {:error, Error.t()}
  def check_peer(table, ieee, route, epoch, now) do
    with :ok <- table_admission(table),
         :ok <- same_epoch(table.epoch, epoch),
         true <- valid_ieee?(ieee) and in_range?(route, 0, 0xFFF7),
         {:ok, entry} <- peer_entry(table, ieee),
         :ok <- usable(entry, epoch, now) do
      if entry.route_address == route,
        do: {:ok, entry.expires_at_ms},
        else: failure(:route_mismatch)
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  @doc "Checks an AF request at a current receiver epoch and returns its custody expiry."
  @spec check_request(t(), DataRequest.t(), reference(), integer()) ::
          {:ok, integer()} | {:error, Error.t()}
  def check_request(table, request, epoch, now) do
    with :ok <- table_admission(table),
         :ok <- same_epoch(table.epoch, epoch),
         :ok <- request_admission(request),
         {:ok, entry} <- peer_entry(table, request.peer_ieee),
         :ok <- usable(entry, epoch, now),
         true <- entry.route_address == request.route_address do
      {:ok, entry.expires_at_ms}
    else
      false -> failure(:route_mismatch)
      error -> error
    end
  end

  defp interview_entry(
         %Result{
           outcome: :complete,
           identity_matches: true,
           peer_ieee: ieee,
           route_address: route,
           owner_epoch: epoch,
           steps: [step | _]
         },
         now,
         ttl
       ) do
    case step do
      %{
        stage: :identity,
        issues: [],
        admission: %Reply{subsystem: 5, id: 1, status: 0, payload: <<0>>},
        response: %Event{
          kind: :zdo_ieee_address,
          owner_epoch: ^epoch,
          owner_sequence: sequence,
          received_at_ms: observed,
          status: 0,
          zdo: %{status: 0, peer_ieee: ^ieee, network_address: ^route}
        }
      } ->
        build_entry(ieee, route, epoch, sequence, observed, now, ttl)

      _ ->
        failure(:invalid_value)
    end
  end

  defp interview_entry(_, _, _), do: failure(:invalid_value)

  defp build_entry(ieee, route, epoch, sequence, observed, now, ttl) do
    if valid_ieee?(ieee) and in_range?(route, 0, 0xFFF7) and is_reference(epoch) and
         in_range?(sequence, 1, @max_generation) and
         valid_time?(now) and valid_time?(observed) and in_range?(ttl, 1, 86_400_000) and
         observed <= now and now < observed + ttl and valid_time?(observed + ttl) do
      {:ok,
       %{
         peer_ieee: ieee,
         route_address: route,
         owner_epoch: epoch,
         owner_sequence: sequence,
         observed_at_ms: observed,
         expires_at_ms: observed + ttl,
         generation: 1,
         status: :current,
         last_conflict: nil
       }}
    else
      failure(:invalid_value)
    end
  end

  defp insert(table, entry) do
    generation = table.generation + 1

    others =
      table.entries
      |> Enum.filter(fn {ieee, old} ->
        ieee != entry.peer_ieee and old.route_address == entry.route_address
      end)
      |> Enum.sort_by(&elem(&1, 0))

    previous = Map.get(table.entries, entry.peer_ieee)

    quarantined =
      previous != nil and previous.status == :conflicted and
        previous.route_address == entry.route_address

    cond do
      previous != nil and stale_entry?(previous, entry) ->
        {:error, error(:stale_observation), table}

      others != [] ->
        conflict(table, entry, others, generation)

      quarantined ->
        {:error, error(:route_conflict), table}

      map_size(table.entries) >= table.capacity and previous == nil ->
        {:error, error(:overload), table}

      true ->
        {:ok,
         %{
           table
           | generation: generation,
             entries: Map.put(table.entries, entry.peer_ieee, %{entry | generation: generation})
         }}
    end
  end

  defp conflict(table, entry, others, generation) do
    entries =
      Enum.reduce(others, table.entries, fn {ieee, old}, entries ->
        Map.put(entries, ieee, %{
          old
          | status: :conflicted,
            last_conflict: entry.peer_ieee,
            generation: generation
        })
      end)

    candidate = %{
      entry
      | status: :conflicted,
        last_conflict: elem(hd(others), 0),
        generation: generation
    }

    entries =
      if map_size(entries) < table.capacity or Map.has_key?(entries, entry.peer_ieee),
        do: Map.put(entries, entry.peer_ieee, candidate),
        else: entries

    {:error, error(:route_conflict), %{table | entries: entries, generation: generation}}
  end

  defp source_entry(table, route) do
    entries = Enum.filter(Map.values(table.entries), &(&1.route_address == route))

    case entries do
      [entry] -> {:ok, entry}
      [] -> failure(:unknown_route)
      _ -> failure(:route_conflict)
    end
  end

  defp peer_entry(table, ieee) do
    case Map.fetch(table.entries, ieee) do
      {:ok, entry} -> {:ok, entry}
      :error -> failure(:unknown_route)
    end
  end

  defp usable(entry, epoch, now) do
    cond do
      not valid_time?(now) or now < entry.observed_at_ms -> failure(:invalid_value)
      entry.owner_epoch != epoch -> failure(:stale_epoch)
      entry.status == :conflicted -> failure(:route_conflict)
      entry.status != :current -> failure(:unknown_route)
      entry.expires_at_ms <= now -> failure(:route_expired)
      true -> :ok
    end
  end

  defp observation_admission(event, entry, now) do
    if valid_time?(event.received_at_ms) and event.received_at_ms >= entry.observed_at_ms and
         event.received_at_ms <= now and
         in_range?(event.owner_sequence, entry.owner_sequence, @max_generation),
       do: :ok,
       else: failure(:stale_observation)
  end

  defp stale_entry?(previous, entry) do
    previous.owner_epoch == entry.owner_epoch and
      (entry.owner_sequence < previous.owner_sequence or
         (entry.owner_sequence == previous.owner_sequence and
            {entry.route_address, entry.observed_at_ms} !=
              {previous.route_address, previous.observed_at_ms}))
  end

  defp valid_entry?(ieee, entry, generation) when is_map(entry) do
    Enum.sort(Map.keys(entry)) == Enum.sort(@entry_keys) and
      entry.peer_ieee == ieee and valid_ieee?(ieee) and
      in_range?(Map.get(entry, :route_address), 0, 0xFFF7) and
      is_reference(Map.get(entry, :owner_epoch)) and
      in_range?(Map.get(entry, :owner_sequence), 1, @max_generation) and
      in_range?(Map.get(entry, :generation), 1, generation) and
      valid_entry_time?(entry) and valid_entry_status?(entry)
  end

  defp valid_entry?(_, _, _), do: false

  defp valid_entry_time?(entry),
    do:
      valid_time?(entry.observed_at_ms) and valid_time?(entry.expires_at_ms) and
        in_range?(entry.expires_at_ms - entry.observed_at_ms, 1, 86_400_000)

  defp valid_entry_status?(%{status: :conflicted} = entry),
    do: valid_ieee?(entry.last_conflict) and entry.last_conflict != entry.peer_ieee

  defp valid_entry_status?(entry),
    do: entry.status in [:current, :unverified] and entry.last_conflict == nil

  defp table_admission(table), do: if(valid?(table), do: :ok, else: failure(:invalid_value))

  defp request_admission(request),
    do: if(DataRequest.valid?(request), do: :ok, else: failure(:invalid_value))

  defp generation_admission(%{generation: @max_generation}), do: failure(:correlation_exhausted)
  defp generation_admission(_), do: :ok
  defp same_epoch(epoch, epoch), do: :ok
  defp same_epoch(_, _), do: failure(:stale_epoch)
  defp valid_time?(value), do: in_range?(value, -@max_time, @max_time)
  defp valid_ieee?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp valid_ieee?(_), do: false
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp failure(kind), do: {:error, error(kind)}
  defp error(kind), do: %Error{kind: kind, operation: :routes}
end
