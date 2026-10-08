defmodule Wotex.Zigbee.Freshness do
  @moduledoc """
  Consumer-owned reporting and Check-in cadence with explicit monotonic time.

  Arm a `Wotex.Zigbee.Freshness.Policy` for each selected stream and retain
  every returned table. `observe/4` checks an AF Event through the current
  `Wotex.Zigbee.Routes` custody and decodes an actual Report Attributes or
  finite Poll Control Check-in frame. It preserves the Event, security
  disposition and selected raw records. Read responses and other commands
  cannot renew a reporting expectation.

  A periodic deadline starts at arming, then at the latest eligible owner's
  observation time, plus the expected interval and grace. Delayed consumption
  does not extend it. Values and explicit nulls renew packet cadence; a null
  remains unavailable attribute data. Duplicate IDs, unsupported types,
  wrong types and opaque tails remain visible without renewing the window.
  An opaque tail prevents proving uniqueness even for a known record before
  it. On-change and disabled modes have no periodic deadline.

  A late window is an observation about the consumer's expectation. It
  establishes no offline state, reachability, wakefulness, authentication or
  canonical Property truth. Nothing here polls, responds to Check-in, changes
  intervals, retries or selects queued downlinks. Qualify reporting, bindings
  and battery policy separately. Dropped owner events can explain missing
  observations; the consumer retains that evidence separately.

  Tables hold at most 1,024 streams, with only the latest matching receipt,
  latest eligible receipt and one previous receipt per stream. Mutations and
  snapshots advance the supplied time watermark. Owner sequence and received
  time cannot rewind within the latest table. Immutable older snapshots and
  copied context cannot establish radio replay protection or authenticate
  receipt provenance. Explicit owner rebind invalidates current receipts and
  requires fresh route custody; it preserves bounded historical evidence.
  """

  alias Wotex.Zigbee.{Error, Event, Routes}
  alias Wotex.Zigbee.Freshness.{Observation, Policy}

  @max_time 0x7FFFFFFFFFFFFFFF
  @max_sequence 0xFFFFFFFFFFFFFFFF
  @fields [:epoch, :capacity, :last_now_ms, :last_owner_sequence, :last_received_at_ms, :entries]
  @entry_fields [:policy, :armed_at_ms, :latest, :eligible, :previous]

  @enforce_keys [:epoch, :capacity]
  defstruct @enforce_keys ++
              [last_now_ms: nil, last_owner_sequence: 0, last_received_at_ms: nil, entries: %{}]

  @type disposition ::
          :value | :null | :checkin | :ambiguous | :unsupported | :wrong_type | :opaque_tail
  @type receipt :: %{
          peer_ieee: <<_::64>>,
          event: Event.t(),
          disposition: disposition(),
          records: [Wotex.Zigbee.ZCL.attribute()]
        }
  @type history :: %{policy: Policy.t(), receipt: receipt()}
  @type entry :: %{
          policy: Policy.t(),
          armed_at_ms: integer(),
          latest: receipt() | nil,
          eligible: receipt() | nil,
          previous: history() | nil
        }
  @type row :: %{
          policy: Policy.t(),
          armed_at_ms: integer(),
          state: :awaiting | :within_window | :late | :on_change | :disabled,
          due_at_ms: integer() | nil,
          latest: receipt() | nil,
          eligible: receipt() | nil,
          previous: history() | nil
        }
  @opaque t :: %__MODULE__{
            epoch: reference(),
            capacity: 1..1_024,
            last_now_ms: integer() | nil,
            last_owner_sequence: non_neg_integer(),
            last_received_at_ms: integer() | nil,
            entries: %{Policy.key() => entry()}
          }

  @doc """
  Builds an empty inert table for one owner epoch, with 1–1,024 streams (default 128).

      iex> {:ok, policy} = Wotex.Zigbee.Freshness.Policy.checkin(peer_ieee: <<1::64>>, remote_endpoint: 1, local_endpoint: 2, expected_interval_ms: 172_800_000)
      iex> {:ok, table} = Wotex.Zigbee.Freshness.new(make_ref())
      iex> {:ok, table} = Wotex.Zigbee.Freshness.arm(table, policy, 0)
      iex> {:ok, %{rows: [row]}} = Wotex.Zigbee.Freshness.snapshot(table, 86_400_000)
      iex> {row.state, row.due_at_ms, row.latest}
      {:awaiting, 172_800_000, nil}
  """
  @spec new(reference(), pos_integer()) :: {:ok, t()} | {:error, Error.t()}
  def new(epoch, capacity \\ 128)

  def new(epoch, capacity)
      when is_reference(epoch) and is_integer(capacity) and capacity in 1..1_024,
      do: {:ok, %__MODULE__{epoch: epoch, capacity: capacity}}

  def new(_, _), do: failure(:invalid_value)

  @doc "Revalidates complete fields, bounded policy/receipt evidence and time/sequence relationships."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = table) do
    complete?(table, @fields, true) and is_reference(table.epoch) and
      in_range?(table.capacity, 1, 1_024) and
      in_range?(table.last_owner_sequence, 0, @max_sequence) and
      is_map(table.entries) and map_size(table.entries) <= table.capacity and
      valid_watermarks?(table) and
      Enum.all?(table.entries, fn {key, entry} -> valid_entry?(key, entry, table) end)
  end

  def valid?(_), do: false

  @doc """
  Arms or explicitly replaces one stream policy, starting its window at `now`.

  Replacing the same selector resets current receipts and retains its latest
  receipt with the previous policy. Type, full-range and cadence changes do
  not create a second stream. Overflow refuses a new selector without dropping
  an existing one. Historical observations cannot satisfy a newly armed window.
  """
  @spec arm(t(), Policy.t(), integer()) :: {:ok, t()} | {:error, Error.t()}
  def arm(table, policy, now) do
    with :ok <- admission(table, now),
         true <- Policy.valid?(policy),
         key = Policy.key(policy),
         :ok <- capacity_admission(table, key),
         entry = reset_entry(policy, Map.get(table.entries, key), now),
         true <- valid_deadline?(entry) do
      {:ok, %{table | entries: Map.put(table.entries, key, entry), last_now_ms: now}}
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  @doc """
  Consumes one source-checked Report Attributes or Poll Control Check-in Event.

  Require the current table and route ledger's owner epoch, monotonically
  increasing owner sequence and nondecreasing owner observation time. A
  matching stream accepts only observations at or after its arming time.
  The supplied `now` may be later than the observation. Each matched receipt
  retains partial records; only values, nulls and Check-in renew cadence.

  Return the updated table, unchanged Event, decoded message and matching
  receipts ordered by stream selector. A valid unmatched message advances
  the watermarks and remains visible in the result. No failed observation
  mutates the supplied table or triggers a command.
  """
  @spec observe(t(), Routes.t(), Event.t(), integer()) ::
          {:ok,
           %{
             table: t(),
             event: Event.t(),
             message: map(),
             matched: [%{policy: Policy.t(), receipt: receipt()}]
           }}
          | {:error, Error.t()}
  def observe(table, routes, event, now) do
    with :ok <- admission(table, now),
         true <- Routes.valid?(routes) and Observation.valid_event?(event),
         :ok <- same_epoch(table.epoch, routes.epoch),
         :ok <- same_epoch(table.epoch, event.owner_epoch),
         :ok <- observation_admission(table, event),
         {:ok, source} <- Routes.resolve(routes, event, now),
         {:ok, message} <- Observation.decode(event),
         {entries, matched} = match_entries(table.entries, source.entry.peer_ieee, event, message),
         true <- Enum.all?(Map.values(entries), &valid_deadline?/1) do
      updated = %{
        table
        | entries: entries,
          last_now_ms: now,
          last_owner_sequence: event.owner_sequence,
          last_received_at_ms: event.received_at_ms
      }

      {:ok, %{table: updated, event: event, message: message, matched: matched}}
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  @doc """
  Evaluates explicit cadence at `now`, returning rows and an advanced table.

  Retain its returned table to fence later clock rewind. Rows are ordered by
  stream selector. Before a periodic deadline they are `:awaiting` until an
  eligible receipt, then `:within_window`; at or after the exact deadline they
  are `:late`. Nonperiodic rows are `:on_change` or `:disabled`, with no due
  time. Receipt dispositions remain separate from these cadence states.
  """
  @spec snapshot(t(), integer()) ::
          {:ok, %{table: t(), evaluated_at_ms: integer(), rows: [row()]}} | {:error, Error.t()}
  def snapshot(table, now) do
    with :ok <- admission(table, now) do
      rows =
        table.entries
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&row(elem(&1, 1), now))

      {:ok, %{table: %{table | last_now_ms: now}, evaluated_at_ms: now, rows: rows}}
    end
  end

  @doc "Removes one explicit stream selector and returns its retained entry without an offline claim."
  @spec forget(t(), Policy.t(), integer()) ::
          {:ok, %{table: t(), forgotten: entry()}} | {:error, Error.t()}
  def forget(table, policy, now) do
    with :ok <- admission(table, now),
         true <- Policy.valid?(policy),
         {entry, retained} when entry != nil <- Map.pop(table.entries, Policy.key(policy)) do
      {:ok, %{table: %{table | entries: retained, last_now_ms: now}, forgotten: entry}}
    else
      false -> failure(:invalid_value)
      {nil, _} -> failure(:invalid_value)
      error -> error
    end
  end

  @doc """
  Replaces the owner epoch explicitly and rearms retained policies at `now`.

  Current receipts and owner ordering reset; each stream retains one previous
  receipt and its interpretation policy. A fresh source-checked observation
  requires current route custody. This function neither rebinds routes nor
  transfers network credentials or counter state.
  """
  @spec rebind(t(), reference(), integer()) :: {:ok, t()} | {:error, Error.t()}
  def rebind(table, epoch, now) do
    with :ok <- admission(table, now),
         true <- is_reference(epoch) and epoch != table.epoch,
         entries =
           Map.new(table.entries, fn {key, entry} ->
             {key, reset_entry(entry.policy, entry, now)}
           end),
         true <- Enum.all?(Map.values(entries), &valid_deadline?/1) do
      {:ok,
       %{
         table
         | epoch: epoch,
           entries: entries,
           last_now_ms: now,
           last_owner_sequence: 0,
           last_received_at_ms: nil
       }}
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  defp match_entries(entries, peer, event, message) do
    {updated, matched} =
      entries
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({entries, []}, fn {key, entry}, {updated, matched} ->
        receipt = Observation.build(entry.policy, peer, event, message)

        if receipt != nil and event.received_at_ms >= entry.armed_at_ms do
          eligible = if Observation.eligible?(receipt), do: receipt, else: entry.eligible
          entry = %{entry | latest: receipt, eligible: eligible}
          {Map.put(updated, key, entry), [%{policy: entry.policy, receipt: receipt} | matched]}
        else
          {updated, matched}
        end
      end)

    {updated, Enum.reverse(matched)}
  end

  defp reset_entry(policy, previous, now),
    do: %{
      policy: policy,
      armed_at_ms: now,
      latest: nil,
      eligible: nil,
      previous: history(previous)
    }

  defp history(nil), do: nil
  defp history(%{latest: nil} = entry), do: entry.previous
  defp history(entry), do: %{policy: entry.policy, receipt: entry.latest}

  defp row(entry, now) do
    deadline = deadline(entry)

    state =
      cond do
        deadline == nil -> entry.policy.expected_interval_ms
        now >= deadline -> :late
        entry.eligible == nil -> :awaiting
        true -> :within_window
      end

    entry
    |> Map.put(:state, state)
    |> Map.put(:due_at_ms, deadline)
  end

  defp deadline(%{policy: %{expected_interval_ms: interval}} = entry) when is_integer(interval) do
    basis =
      if entry.eligible == nil, do: entry.armed_at_ms, else: entry.eligible.event.received_at_ms

    basis + interval + entry.policy.grace_ms
  end

  defp deadline(_), do: nil
  defp valid_deadline?(entry), do: deadline(entry) == nil or valid_time?(deadline(entry))

  defp valid_watermarks?(table) do
    (valid_time?(table.last_now_ms) or
       (table.last_now_ms == nil and table.last_owner_sequence == 0 and table.entries == %{})) and
      if table.last_owner_sequence == 0 do
        table.last_received_at_ms == nil
      else
        valid_time?(table.last_received_at_ms) and table.last_received_at_ms <= table.last_now_ms
      end
  end

  defp valid_entry?(key, entry, table) when is_map(entry) do
    complete?(entry, @entry_fields, false) and Policy.valid?(entry.policy) and
      Policy.key(entry.policy) == key and valid_time?(entry.armed_at_ms) and
      valid_time?(table.last_now_ms) and entry.armed_at_ms <= table.last_now_ms and
      current_receipt?(entry.latest, entry, table) and
      current_receipt?(entry.eligible, entry, table) and
      receipt_order?(entry) and valid_history?(entry.previous, key, entry.armed_at_ms) and
      valid_deadline?(entry)
  end

  defp valid_entry?(_, _, _), do: false

  defp current_receipt?(nil, _, _), do: true

  defp current_receipt?(receipt, entry, table) do
    Observation.valid_receipt?(receipt, entry.policy) and
      receipt.event.owner_epoch == table.epoch and
      receipt.event.received_at_ms >= entry.armed_at_ms and
      receipt.event.received_at_ms <= table.last_received_at_ms and
      receipt.event.owner_sequence <= table.last_owner_sequence
  end

  defp receipt_order?(%{latest: nil, eligible: nil}), do: true
  defp receipt_order?(%{latest: nil}), do: false

  defp receipt_order?(%{latest: latest, eligible: eligible}) do
    cond do
      Observation.eligible?(latest) ->
        eligible == latest

      eligible == nil ->
        true

      true ->
        Observation.eligible?(eligible) and
          eligible.event.owner_sequence < latest.event.owner_sequence and
          eligible.event.received_at_ms <= latest.event.received_at_ms
    end
  end

  defp valid_history?(nil, _, _), do: true

  defp valid_history?(history, key, armed) when is_map(history) do
    complete?(history, [:policy, :receipt], false) and Policy.valid?(history.policy) and
      Policy.key(history.policy) == key and
      Observation.valid_receipt?(history.receipt, history.policy) and
      history.receipt.event.received_at_ms <= armed
  end

  defp valid_history?(_, _, _), do: false

  defp observation_admission(table, event) do
    if event.owner_sequence > table.last_owner_sequence and
         (table.last_received_at_ms == nil or event.received_at_ms >= table.last_received_at_ms),
       do: :ok,
       else: failure(:stale_observation)
  end

  defp capacity_admission(table, key) do
    if map_size(table.entries) < table.capacity or Map.has_key?(table.entries, key),
      do: :ok,
      else: failure(:overload)
  end

  defp admission(table, now) do
    cond do
      not valid?(table) or not valid_time?(now) -> failure(:invalid_value)
      table.last_now_ms != nil and now < table.last_now_ms -> failure(:stale_observation)
      true -> :ok
    end
  end

  defp complete?(map, keys, struct),
    do:
      map_size(map) == length(keys) + if(struct, do: 1, else: 0) and
        Enum.all?(keys, &Map.has_key?(map, &1))

  defp same_epoch(epoch, epoch), do: :ok
  defp same_epoch(_, _), do: failure(:stale_epoch)
  defp valid_time?(value), do: in_range?(value, -@max_time, @max_time)
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :freshness}}
end
