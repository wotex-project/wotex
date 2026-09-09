# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(WotexContinuum.Codec) do
  defmodule Wotex.Lab.Continuum.Channel do
    @moduledoc """
    A bounded, instance-owned in-memory channel carrying continuum values.

    Every send is encoded canonically with the continuum codec and delivered to
    the pid attached to the destination endpoint as
    `{:wotex_continuum, destination, delivery_id, wire_bytes}`. A source-aware
    attachment receives the source and an unforgeable acknowledgement token as
    additional tuple elements. The token never enters a public delivery record.
    Endpoint
    attachment establishes in-process source ownership: only the attached
    process may send from that endpoint, and an endpoint cannot be transplanted
    to another live process. Each send yields
    a `WotexContinuum.Delivery` record that moves `pending` to `in_flight` to
    `acknowledged`, or to `failed` when the fault schedule drops it. Capacity
    bounds the number of unacknowledged deliveries. `disconnect/1` buffers new
    sends and `reconnect/1` replays every unacknowledged delivery with a new
    attempt, so a receiver must distinguish receiving a message from having
    observed its state. The clock is a supplied function; the channel never reads
    wall-clock time on its own.
    """

    use GenServer

    alias Wotex.Lab.Continuum.FaultSchedule
    alias Wotex.Lab.Error
    alias Wotex.Lab.Telemetry
    alias WotexContinuum.{Codec, Delivery}

    @doc false
    @spec child_spec(keyword()) :: Supervisor.child_spec()
    def child_spec(opts) do
      %{
        id: {__MODULE__, Keyword.get(opts, :id, :default)},
        start: {__MODULE__, :start_link, [opts]},
        restart: Keyword.get(opts, :restart, :transient),
        type: :worker
      }
    end

    @doc "Starts a channel with `:clock` (zero-arity DateTime function), `:capacity` (64) and `:faults`."
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      case Keyword.get(opts, :name) do
        nil -> GenServer.start_link(__MODULE__, opts)
        name -> GenServer.start_link(__MODULE__, opts, name: name)
      end
    end

    @doc "Attaches a receiving pid to an endpoint name; `source: true` includes the authenticated source in deliveries."
    @spec attach(pid(), String.t(), pid(), keyword()) :: :ok | {:error, Error.t()}
    def attach(channel, endpoint, pid, opts \\ [])

    def attach(channel, endpoint, pid, opts) when is_pid(pid),
      do: GenServer.call(channel, {:attach, endpoint, pid, opts})

    def attach(_, _, _, _),
      do: {:error, error(:invalid_endpoint, "endpoint attachment is invalid")}

    @doc "Sends a continuum value from one endpoint to another."
    @spec send_value(pid(), String.t(), String.t(), struct()) ::
            {:ok, Delivery.t()} | {:error, Error.t()}
    def send_value(channel, from, to, value), do: GenServer.call(channel, {:send, from, to, value})

    @doc "Acknowledges a delivery."
    @spec ack(pid(), String.t()) :: :ok | {:error, Error.t()}
    def ack(channel, delivery_id), do: GenServer.call(channel, {:ack, delivery_id})

    @doc "Acknowledges a source-aware delivery with its in-process receipt token."
    @spec ack(pid(), String.t(), reference()) :: :ok | {:error, Error.t()}
    def ack(channel, delivery_id, receipt_token),
      do: GenServer.call(channel, {:ack, delivery_id, receipt_token})

    @doc "Returns every delivery record in send order."
    @spec deliveries(pid()) :: [Delivery.t()]
    def deliveries(channel), do: GenServer.call(channel, :deliveries)

    @doc "Simulates a disconnection: sends are buffered and nothing is delivered."
    @spec disconnect(pid()) :: :ok
    def disconnect(channel), do: GenServer.call(channel, :disconnect)

    @doc "Reconnects and replays every unacknowledged delivery with a new attempt."
    @spec reconnect(pid()) :: :ok
    def reconnect(channel), do: GenServer.call(channel, :reconnect)

    @impl GenServer
    def init(opts) do
      {:ok, faults} = FaultSchedule.new(Keyword.get(opts, :faults, []))

      {:ok,
       %{
         clock: Keyword.get(opts, :clock, fn -> DateTime.utc_now() end),
         capacity: Keyword.get(opts, :capacity, 64),
         faults: faults,
         endpoints: %{},
         sequence: 0,
         connected?: true,
         items: %{},
         order: [],
         held: %{},
         monitors: %{}
       }}
    end

    @impl GenServer
    def handle_call({:attach, endpoint, pid, opts}, _, state) do
      source? = if Keyword.keyword?(opts), do: Keyword.get(opts, :source, false), else: :invalid

      cond do
        not endpoint?(endpoint) or not Keyword.keyword?(opts) or
          Enum.any?(Keyword.keys(opts), &(&1 != :source)) or not is_boolean(source?) ->
          {:reply, {:error, error(:invalid_endpoint, "endpoint attachment is invalid")}, state}

        match?(%{pid: owner} when owner != pid, state.endpoints[endpoint]) ->
          {:reply, {:error, error(:endpoint_in_use, "endpoint already has an owner")}, state}

        match?(%{pid: ^pid}, state.endpoints[endpoint]) ->
          {:reply, :ok, put_in(state, [:endpoints, endpoint, :source?], source?)}

        true ->
          monitor = Process.monitor(pid)
          attachment = %{pid: pid, monitor: monitor, source?: source?}

          state =
            state
            |> put_in([:endpoints, endpoint], attachment)
            |> put_in([:monitors, monitor], endpoint)

          {:reply, :ok, state}
      end
    end

    def handle_call({:send, from, to, value}, {caller, _}, state) do
      with :ok <- endpoint_names(from, to),
           :ok <- owns_source(state, from, caller),
           :ok <- capacity(state),
           {:ok, wire} <-
             Telemetry.span(:continuum, :codec, %{operation: :encode}, fn -> encode(value) end),
           {:ok, map} <- WotexContinuum.to_map(value) do
        Telemetry.event(:continuum, :codec, %{bytes: byte_size(wire)}, %{
          kind: map["kind"],
          operation: :encode
        })

        sequence = state.sequence + 1
        delivery_id = "delivery-#{sequence}"
        now = state.clock.()

        item = %{
          id: delivery_id,
          sequence: sequence,
          from: from,
          to: to,
          wire: wire,
          item_kind: map["kind"],
          item_id: item_id(map),
          attempt: 1,
          status: :pending,
          emitted_at: now,
          acknowledged_at: nil,
          receipt_token: make_ref(),
          error: nil
        }

        state = %{
          state
          | sequence: sequence,
            items: Map.put(state.items, delivery_id, item),
            order: [delivery_id | state.order]
        }

        state = state |> transmit(delivery_id) |> release_holds(sequence)
        {:reply, {:ok, delivery(state.items[delivery_id])}, state}
      else
        {:error, error} ->
          Telemetry.event(:continuum, :dispatch, %{deliveries: 1}, %{outcome: error.code})
          {:reply, {:error, error}, state}
      end
    end

    def handle_call({:ack, delivery_id}, {caller, _}, state) do
      acknowledge(state, delivery_id, {:owner, caller})
    end

    def handle_call({:ack, delivery_id, receipt_token}, {caller, _}, state) do
      acknowledge(state, delivery_id, {:token, caller, receipt_token})
    end

    def handle_call(:deliveries, _, state) do
      {:reply, state.order |> Enum.reverse() |> Enum.map(&delivery(state.items[&1])), state}
    end

    def handle_call(:disconnect, _, state), do: {:reply, :ok, %{state | connected?: false}}

    def handle_call(:reconnect, _, state) do
      replay =
        state.order
        |> Enum.reverse()
        |> Enum.filter(fn id -> state.items[id].status in [:pending, :in_flight, :delivered] end)

      state = %{state | connected?: true}

      state =
        Enum.reduce(replay, state, fn id, acc ->
          item = acc.items[id]
          attempt = if item.status == :pending, do: item.attempt, else: item.attempt + 1
          acc = put_in(acc, [:items, id], %{item | attempt: attempt, status: :pending})
          transmit(acc, id)
        end)

      {:reply, :ok, state}
    end

    defp acknowledge(state, delivery_id, authorization) do
      case Map.fetch(state.items, delivery_id) do
        {:ok, item} ->
          if authorized_ack?(state, item, authorization) do
            acknowledge_item(state, delivery_id, item)
          else
            {:reply, {:error, error(:invalid_receipt_token, "delivery token is invalid")}, state}
          end

        :error ->
          {:reply,
           {:error, Error.new(:unknown_delivery, :channel, "delivery cannot be acknowledged")},
           state}
      end
    end

    defp acknowledge_item(state, delivery_id, %{status: status} = item)
         when status in [:in_flight, :delivered] do
      item = %{item | status: :acknowledged, acknowledged_at: state.clock.()}
      {:reply, :ok, put_in(state, [:items, delivery_id], item)}
    end

    defp acknowledge_item(state, _, %{status: :acknowledged}),
      do: {:reply, :ok, state}

    defp acknowledge_item(state, _, _),
      do:
        {:reply,
         {:error, Error.new(:unknown_delivery, :channel, "delivery cannot be acknowledged")}, state}

    defp authorized_ack?(state, item, {:owner, caller}),
      do: get_in(state, [:endpoints, item.to, :pid]) == caller

    defp authorized_ack?(state, item, {:token, caller, token}),
      do: get_in(state, [:endpoints, item.to, :pid]) == caller and item.receipt_token == token

    @impl GenServer
    def handle_info({:DOWN, monitor, :process, _, _}, state) do
      case Map.pop(state.monitors, monitor) do
        {nil, _} ->
          {:noreply, state}

        {endpoint, monitors} ->
          {:noreply,
           %{state | endpoints: Map.delete(state.endpoints, endpoint), monitors: monitors}}
      end
    end

    def handle_info(_, state), do: {:noreply, state}

    defp transmit(state, delivery_id) do
      item = state.items[delivery_id]

      cond do
        not state.connected? ->
          state

        fault?(state, item, :drop) ->
          fail(state, item)

        fault?(state, item, :hold) and not Map.has_key?(state.held, item.sequence) ->
          hold(state, item)

        true ->
          dispatch(state, item)
      end
    end

    # Faults apply to the first attempt only; a replay after reconnect is clean.
    defp fault?(_, %{attempt: attempt}, _) when attempt != 1, do: false
    defp fault?(state, item, :drop), do: MapSet.member?(state.faults.drop, item.sequence)
    defp fault?(state, item, :duplicate), do: MapSet.member?(state.faults.duplicate, item.sequence)
    defp fault?(state, item, :hold), do: Map.has_key?(state.faults.hold, item.sequence)

    defp fail(state, item) do
      failure = %{code: "dropped", message: "delivery dropped by the fault schedule"}
      Telemetry.event(:continuum, :dispatch, %{deliveries: 1}, %{outcome: :rejected})
      put_in(state, [:items, item.id], %{item | status: :failed, error: failure})
    end

    defp hold(state, item), do: put_in(state, [:held, item.sequence], item.id)

    defp dispatch(state, item) do
      copies = if fault?(state, item, :duplicate), do: 2, else: 1
      Enum.each(1..copies, fn _ -> deliver(state, item) end)
      Telemetry.event(:continuum, :dispatch, %{deliveries: copies}, %{outcome: :ok})
      put_in(state, [:items, item.id], %{item | status: :in_flight})
    end

    defp release_holds(state, sequence) do
      due = state.held |> Enum.filter(fn {held, _} -> state.faults.hold[held] <= sequence end)

      Enum.reduce(due, state, fn {held, id}, acc ->
        acc = %{acc | held: Map.delete(acc.held, held)}
        item = acc.items[id]
        deliver(acc, item)
        put_in(acc, [:items, id], %{item | status: :in_flight})
      end)
    end

    defp deliver(state, item) do
      case Map.fetch(state.endpoints, item.to) do
        {:ok, %{pid: pid, source?: true}} ->
          send(
            pid,
            {:wotex_continuum, item.to, item.from, item.id, item.receipt_token, item.wire}
          )

        {:ok, %{pid: pid}} ->
          send(pid, {:wotex_continuum, item.to, item.id, item.wire})

        :error ->
          :ok
      end
    end

    defp endpoint_names(from, to) do
      if endpoint?(from) and endpoint?(to),
        do: :ok,
        else: {:error, error(:invalid_endpoint, "source and destination endpoints are invalid")}
    end

    defp owns_source(state, endpoint, caller) do
      case state.endpoints do
        %{^endpoint => %{pid: ^caller}} -> :ok
        _ -> {:error, error(:source_not_attached, "caller does not own the source endpoint")}
      end
    end

    defp endpoint?(value),
      do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)

    defp error(code, message), do: Error.new(code, :channel, message, class: :permanent)

    defp capacity(state) do
      open =
        Enum.count(state.items, fn {_, item} ->
          item.status in [:pending, :in_flight, :delivered]
        end)

      if open < state.capacity,
        do: :ok,
        else:
          {:error,
           Error.new(:capacity_exhausted, :channel, "unacknowledged deliveries reached capacity",
             class: :unavailable
           )}
    end

    defp encode(value) do
      case Codec.encode(value, canonical: true) do
        {:ok, wire} ->
          {:ok, wire}

        {:error, _} ->
          {:error,
           Error.new(
             :invalid_continuum_value,
             :channel,
             "value is not a registered continuum value",
             class: :protocol
           )}
      end
    end

    defp item_id(map) do
      Enum.find_value(
        ~w(proposal_id intent_id result_id evidence_id delivery_id degradation_id receipt_id manifest_id execution_id subject_id id),
        "unknown",
        &Map.get(map, &1)
      )
    end

    defp delivery(item) do
      base = %{
        delivery_id: item.id,
        item_kind: item.item_kind,
        item_id: item.item_id,
        source: item.from,
        destination: item.to,
        status: item.status,
        attempt: item.attempt,
        sequence: item.sequence,
        emitted_at: item.emitted_at
      }

      base =
        if item.acknowledged_at,
          do: Map.put(base, :acknowledged_at, item.acknowledged_at),
          else: base

      base = if item.error, do: Map.put(base, :error, item.error), else: base
      {:ok, delivery} = Delivery.from_map(base)
      delivery
    end
  end
end
