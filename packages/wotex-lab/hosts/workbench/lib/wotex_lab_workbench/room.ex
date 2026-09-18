defmodule WotexLabWorkbench.Room do
  @moduledoc """
  One session's disposable room under the host's Lab instance.

  A room starts three loopback Reference Things (thermostat, energy meter
  and the actuator from the Lab fixture) under the instance's `:things` role,
  a session Directory, a continuum channel with a simulated cloud host, and
  a smart-room policy that allows the `operator` principal only. Every run,
  granted decision, dataset export and formal result lives here and vanishes
  when the room stops. The room dispatches nothing on its own: a granted
  decision waits for `approve/3`, which the policy checks again at that
  moment. Runs are synchronous and bounded; the room refuses more than its
  run, dataset and Thing capacities.

  Each room also owns a catalogue collector attributed to the room process
  and a bounded history of its snapshots. Only events emitted by the room, by
  processes it started or by tasks it awaits reach that collector; Things and
  shared processes started under the host instance are not attributed. The
  room captures a snapshot after each run or approval and every five seconds,
  keeping at most 120 snapshots and 1 MiB. The history is bound to a random
  per-room instance identifier, so a query scoped to another room is refused.
  `history/1` returns the history binding for trusted host queries. The
  collector, history and snapshots are discarded with the room.
  """

  use GenServer

  alias Wotex.{Directory, ThingDescription}
  alias Wotex.Directory.{Context, Service}
  alias Wotex.Lab.Adapters.Directory.{Authorization, Clock, EtsRepository, Identifier}
  alias Wotex.Lab.Adapters.Runtime.{Loopback, StaticRef}
  alias Wotex.Lab.Continuum.{Channel, Host}
  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Formal.Result
  alias Wotex.Lab.Metrics.{Collector, History}
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Lab.SmartRoom.{Policy, Scenario}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing}
  alias WotexLabWorkbench.Control.Ledger
  alias WotexLabWorkbench.{Evidence, Experiments, Formal, Metrics, Provenance, Run, Runs}
  alias WotexLabWorkbench.Runs.{SmartRoom, Thermal, WindowAnomaly}

  @max_runs 16
  @max_datasets 8
  @max_extra_tds 4
  @max_formal 8
  @max_td_bytes 16_384
  @run_timeout 30_000
  @history_interval_ms 5_000
  @history_snapshots 120
  @history_bytes 1_048_576
  @history_queries 4
  @things [
    %{
      key: "thermostat",
      role: :thermostat,
      scheme: "sim-thermostat",
      state: %{"temperature" => 21.5}
    },
    %{key: "meter", role: :meter, scheme: "sim-meter", state: %{"power" => 2_500.0}},
    %{
      key: "actuator",
      role: :actuator,
      scheme: "loopback",
      state: %{"temperature" => 20.0, "target" => 21.0}
    }
  ]

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc "Starts a room with `:id` (the session id) and `:lab` (the instance)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Runs an admitted experiment with admitted parameters."
  @spec start_run(pid(), String.t(), keyword()) :: {:ok, Run.t()} | {:error, Error.t()}
  def start_run(room, experiment_id, params),
    do: GenServer.call(room, {:run, experiment_id, params}, @run_timeout)

  @doc "Every run, newest first."
  @spec runs(pid()) :: [Run.t()]
  def runs(room), do: GenServer.call(room, :runs)

  @doc "Fetches one run."
  @spec fetch_run(pid(), term()) :: {:ok, Run.t()} | {:error, Error.t()}
  def fetch_run(room, id), do: GenServer.call(room, {:fetch_run, id})

  @doc "Cancels a run: a granted decision is revoked and the run is marked cancelled."
  @spec cancel_run(pid(), term()) :: {:ok, Run.t()} | {:error, Error.t()}
  def cancel_run(room, id), do: GenServer.call(room, {:cancel, id})

  @typedoc "An HTTP control command admitted by `WotexLabWorkbench.Control`."
  @type control_command ::
          {:run, String.t(), keyword()}
          | {:cancel, String.t()}
          | {:approve, String.t(), map(), map()}

  @typedoc "One idempotent HTTP control mutation."
  @type mutation :: %{key: String.t(), fingerprint: binary(), command: control_command()}

  @doc """
  Executes one HTTP control mutation at most once for its idempotency key.

  The room consults its `WotexLabWorkbench.Control.Ledger` when it dequeues the
  mutation: a retained identity replays its outcome with the run's current state,
  a reused key or a full ledger is refused, and a new key is refused without
  execution once the monotonic `deadline_at` millisecond has passed. Otherwise
  the same room command as the LiveView event runs once and its outcome is
  retained. An approval also has to name the granted decision's Thing, Action and
  input. The caller waits at most `timeout_ms`.
  """
  @spec control(pid(), mutation(), integer(), timeout()) ::
          {:executed | :replayed, {:ok, Run.t()} | {:error, Error.t()}} | {:error, Error.t()}
  def control(room, %{key: _, fingerprint: _, command: _} = mutation, deadline_at, timeout_ms),
    do: GenServer.call(room, {:control, mutation, deadline_at}, timeout_ms)

  @doc "Approves a granted decision; the policy dispatches it at most once."
  @spec approve(pid(), term(), map()) :: {:ok, Run.t()} | {:error, Error.t()}
  def approve(room, run_id, approval) when is_map(approval),
    do: GenServer.call(room, {:approve, run_id, approval}, @run_timeout)

  def approve(_, _, _),
    do: {:error, Error.new(:invalid_approval, :dispatch, "approval must be a field map")}

  @doc "The disposable Things with their TDs, transport and admission counters."
  @spec things(pid()) :: [map()]
  def things(room), do: GenServer.call(room, :things)

  @doc "Reads one simulated Property through the runtime."
  @spec read_property(pid(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def read_property(room, key, name), do: GenServer.call(room, {:read, key, name})

  @doc "Registers a pasted TD in the session Directory as an inert, non-consumable entry."
  @spec register_td(pid(), term()) :: {:ok, map()} | {:error, Error.t()}
  def register_td(room, json), do: GenServer.call(room, {:register, json})

  @doc "Freezes the current metrics query into an immutable dataset."
  @spec export_dataset(pid(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def export_dataset(room, query), do: GenServer.call(room, {:export, query})

  @doc "Runs one bounded formal verification and keeps the result as evidence."
  @spec verify(pid(), atom(), atom()) :: {:ok, Result.t()} | {:error, :unsupported | Error.t()}
  def verify(room, property, variant),
    do: GenServer.call(room, {:verify, property, variant}, 70_000)

  @typedoc "The room-owned history and the scope its queries must name."
  @type history_binding :: %{
          history: pid(),
          scope: %{instance: String.t(), session: String.t()},
          interval_ms: pos_integer()
        }

  @doc "Returns the room's attributed history binding for trusted host queries."
  @spec history(pid()) :: {:ok, history_binding()}
  def history(room), do: GenServer.call(room, :history)

  @doc "Runs, datasets, formal results, Things and counters for evidence and reports."
  @spec snapshot(pid()) :: map()
  def snapshot(room), do: GenServer.call(room, :snapshot)

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    Process.put(:room_owned_lab, [])
    Process.put(:room_owned_local, [])
    lab = Keyword.fetch!(opts, :lab)
    epoch = DateTime.utc_now()
    token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    instance = "room-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    with {:ok, things} <- start_things(lab, token),
         {:ok, repository} <- managed(lab, :things, {EtsRepository, id: :directory}),
         {:ok, clock} <- local(Clock.start_link(epoch)),
         {:ok, identifier} <- local(Identifier.start_link()),
         {:ok, service} <- service(repository, clock, identifier, things),
         context <- Context.new!(:operator),
         :ok <- register_all(service, context, things),
         {:ok, consumed} <- Scenario.discover(service, context, transport_opts(things, token)),
         {:ok, channel} <-
           local(Channel.start_link(id: :room_channel, clock: fn -> epoch end, capacity: 64)),
         {:ok, host} <-
           local(
             Host.start_link(
               id: :room_host,
               channel: channel,
               endpoint: "cloud",
               clock: fn -> epoch end,
               things: consumed
             )
           ),
         :ok <- Channel.attach(channel, "edge", self()),
         {:ok, policy} <-
           local(
             Policy.start_link(
               allowed: [:operator],
               limits: %{"setTarget" => %{min: 5, max: 35}}
             )
           ),
         {:ok, collector} <- local(Collector.start_link(attribute_to: self())),
         {:ok, history} <-
           local(
             History.start_link(
               instance: instance,
               max_snapshots: @history_snapshots,
               max_bytes: @history_bytes,
               max_queries: @history_queries
             )
           ) do
      schedule_history()

      {:ok,
       %{
         id: Keyword.fetch!(opts, :id),
         lab: lab,
         epoch: epoch,
         things: things,
         repository: repository,
         service: service,
         context: context,
         consumed: consumed,
         ids: Map.new(@things, fn spec -> {spec.role, things[spec.key].id} end),
         channel: channel,
         host: host,
         policy: policy,
         scope: Scenario.scope("edge", epoch),
         watermark: 1,
         state_revision: 1,
         runs: %{},
         order: [],
         sequence: 0,
         # Newest first; readers restore insertion order.
         datasets: [],
         formal: [],
         extra_tds: [],
         control: Ledger.new(),
         history: %{
           collector: collector,
           store: history,
           instance: instance,
           last_wall_ms: 0
         },
         owned_lab: take_owned(:room_owned_lab),
         owned_local: take_owned(:room_owned_local)
       }}
    else
      {:error, reason} ->
        cleanup_started(lab)
        {:stop, {:room_setup_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:run, experiment_id, params}, _, state) do
    with {:ok, experiment} <- Experiments.fetch(experiment_id),
         :ok <- no_pending_decision(state, experiment),
         :ok <- capacity(map_size(state.runs), @max_runs, :run_limit, "run capacity reached") do
      sequence = state.sequence + 1
      started = DateTime.utc_now()
      outcome = execute(experiment, params, state)
      run = build_run(experiment, params, sequence, started, outcome)
      record_metric(state.id, :scenario, :inference, run.duration_ms, run.status)

      state =
        sample_history(%{
          state
          | sequence: sequence,
            runs: Map.put(state.runs, run.id, run),
            order: [run.id | state.order]
        })

      {:reply, {:ok, run}, state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {:control, %{key: key, fingerprint: fingerprint, command: command}, deadline_at},
        from,
        state
      ) do
    case Ledger.check(state.control, key, fingerprint) do
      {:replay, {:ok, run_id}} ->
        {:reply, {:replayed, fetch_run_state(state, run_id)}, state}

      {:replay, {:error, error}} ->
        {:reply, {:replayed, {:error, error}}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}

      :new ->
        if System.monotonic_time(:millisecond) >= deadline_at do
          {:reply,
           {:error,
            Error.new(:deadline_exceeded, :control_api, "deadline passed before the command ran")},
           state}
        else
          {:reply, reply, state} = control_command(command, from, state)
          {reply, outcome} = control_outcome(reply)
          control = Ledger.retain(state.control, key, fingerprint, outcome)
          {:reply, {:executed, reply}, %{state | control: control}}
        end
    end
  end

  def handle_call(:runs, _, state), do: {:reply, Enum.map(state.order, &state.runs[&1]), state}

  def handle_call(:history, _, state) do
    binding = %{
      history: state.history.store,
      scope: %{instance: state.history.instance, session: state.history.instance},
      interval_ms: @history_interval_ms
    }

    {:reply, {:ok, binding}, state}
  end

  def handle_call({:fetch_run, id}, _, state), do: {:reply, fetch_run_state(state, id), state}

  def handle_call({:cancel, id}, _, state) do
    case fetch_run_state(state, id) do
      {:ok, %Run{status: :awaiting_approval} = run} ->
        Policy.revoke(state.policy, run.decision["id"])
        run = %{run | status: :cancelled, decision: nil}
        state = %{state | runs: Map.put(state.runs, id, run), watermark: state.watermark + 1}
        {:reply, {:ok, run}, state}

      {:ok, %Run{}} ->
        {:reply, {:error, Error.new(:not_cancellable, :room, "run has no pending work")}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:approve, id, approval}, _, state) do
    with {:ok, %Run{status: :awaiting_approval} = run} <- fetch_run_state(state, id),
         {:ok, outcome} <- SmartRoom.dispatch(run, approval, state) do
      run = %{
        run
        | status: :dispatched,
          dispatch: outcome.dispatch,
          effect: outcome.effect,
          assertions: Enum.map(run.assertions, &dispatched_assertion/1),
          summary:
            Enum.concat(run.summary, [
              {"Effect", "target read back as #{Runs.plain(outcome.effect)} Cel"}
            ])
      }

      run = with_record(run, state)
      record_metric(state.id, :policy, :dispatch, 0, :dispatched)

      {:reply, {:ok, run},
       sample_history(%{
         state
         | runs: Map.put(state.runs, id, run),
           state_revision: state.state_revision + 1,
           watermark: state.watermark + 1
       })}
    else
      {:ok, %Run{}} ->
        {:reply, {:error, Error.new(:not_approvable, :dispatch, "run has no pending decision")},
         state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(:things, _, state) do
    listed =
      Enum.map(@things, fn %{key: key, scheme: scheme} ->
        thing = state.things[key]

        %{
          key: key,
          id: thing.id,
          title: thing.document["title"],
          document: thing.document,
          transport: scheme,
          consumable: true,
          owner: "session #{state.id}; Lab instance workbench, role things",
          stats: Thing.stats(thing.pid)
        }
      end)

    extra =
      state.extra_tds
      |> Enum.reverse()
      |> Enum.map(fn document ->
        %{
          key: "registered",
          id: document["id"],
          title: document["title"],
          document: document,
          transport: "none",
          consumable: false,
          owner: "session #{state.id}; Directory entry only, no transport admitted",
          stats: %{handler_calls: 0, rejected: 0, subscriptions: 0, state: %{}}
        }
      end)

    {:reply, listed ++ extra, state}
  end

  def handle_call({:read, key, name}, _, state) when is_binary(key) and is_binary(name) do
    reply =
      with {:ok, thing} <-
             Map.fetch(state.things, key) |> known(:unknown_thing, "Thing is not in this room"),
           {:ok, consumed} <-
             Map.fetch(state.consumed, thing.id) |> known(:unknown_thing, "Thing is not consumable"),
           true <-
             Map.has_key?(thing.document["properties"] || %{}, name) ||
               {:error, Error.new(:unknown_property, :things, "property is not declared")},
           now <- System.monotonic_time(:millisecond),
           {:ok, result} <-
             ConsumedThing.read_property(
               consumed,
               name,
               Wotex.Runtime.Context.new!(request_id: "read:#{name}:#{now}", deadline: now + 5_000)
             ) do
        {:ok,
         %{
           thing: key,
           property: name,
           value: result.payload,
           status: result.status,
           binding: Runs.plain(result.metadata)
         }}
      end

    {:reply, reply, state}
  end

  def handle_call({:read, _, _}, _, state),
    do:
      {:reply, {:error, Error.new(:invalid_read, :things, "thing and property must be strings")},
       state}

  def handle_call({:register, json}, _, state)
      when is_binary(json) and byte_size(json) <= @max_td_bytes do
    with :ok <-
           capacity(
             length(state.extra_tds),
             @max_extra_tds,
             :td_limit,
             "registered TD capacity reached"
           ),
         {:ok, td} <- ThingDescription.parse(json) |> td_error(),
         {:ok, _} <- Directory.register(state.service, td, state.context) |> td_error() do
      document = ThingDescription.to_map(td)
      {:reply, {:ok, document}, %{state | extra_tds: [document | state.extra_tds]}}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:register, _}, _, state),
    do:
      {:reply,
       {:error,
        Error.new(:td_too_large, :things, "TD must be text of at most #{@max_td_bytes} bytes")},
       state}

  def handle_call({:export, query}, _, state) do
    with {:ok, query} <- dataset_query(query, state.id),
         :ok <-
           capacity(
             length(state.datasets),
             @max_datasets,
             :dataset_limit,
             "dataset capacity reached"
           ),
         {:ok, live} <- unavailable(Metrics.query(query)) do
      rows =
        Enum.map(
          live.samples,
          &Map.take(&1, [:sequence, :at, :component, :operation, :event, :duration_ms, :outcome])
        )

      encoded = Jason.encode!(Runs.plain(rows))
      digest = Digest.bytes(encoded)

      recorded_query =
        query
        |> Map.new()
        |> Map.delete(:scope)
        |> Runs.plain()

      dataset = %{
        id: "dataset-#{length(state.datasets) + 1}",
        digest: digest,
        query: recorded_query,
        interval: live.interval,
        watermark: live.watermark,
        rows: length(rows),
        unit: live.unit,
        ordering: "sequence ascending",
        method: "none (rows kept as queried)",
        loss: live.loss,
        frozen_at: DateTime.utc_now()
      }

      record_metric(state.id, :scenario, :encode, 0, :ok)
      {:reply, {:ok, dataset}, %{state | datasets: [dataset | state.datasets]}}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:verify, property, variant}, _, state) do
    with :ok <-
           capacity(
             length(state.formal),
             @max_formal,
             :formal_limit,
             "formal result capacity reached"
           ),
         {:ok, result} <- Formal.verify(property, variant) do
      record_metric(state.id, :scenario, :verification, 0, result.status)
      {:reply, {:ok, result}, %{state | formal: [result | state.formal]}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:snapshot, _, state) do
    {:reply,
     %{
       id: state.id,
       runs: Enum.map(state.order, &state.runs[&1]),
       datasets: Enum.reverse(state.datasets),
       formal: Enum.reverse(state.formal),
       policy: Policy.records(state.policy),
       watermark: state.watermark,
       state_revision: state.state_revision,
       host:
         Host.stats(state.host)
         |> Map.take([:received, :rejected])
         |> Map.new(fn {k, v} -> {k, length(v)} end)
     }, state}
  end

  @impl GenServer
  def handle_info({:wotex_continuum, "edge", delivery_id, _}, state) do
    _ = Channel.ack(state.channel, delivery_id)
    {:noreply, state}
  end

  def handle_info(:sample_history, state) do
    schedule_history()
    {:noreply, sample_history(state)}
  end

  def handle_info({:EXIT, _, :normal}, state), do: {:noreply, state}

  def handle_info({:EXIT, pid, reason}, state),
    do: {:stop, {:linked_process_exit, pid, reason}, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    cleanup(state.lab, state.owned_local, state.owned_lab)
    :ok
  end

  defp control_command({:run, experiment_id, params}, from, state),
    do: handle_call({:run, experiment_id, params}, from, state)

  defp control_command({:cancel, run_id}, from, state),
    do: handle_call({:cancel, run_id}, from, state)

  defp control_command({:approve, run_id, named, approval}, from, state) do
    case fetch_run_state(state, run_id) do
      {:ok, %Run{status: :awaiting_approval, decision: %{} = decision}} ->
        if names_decision?(decision, named) do
          handle_call({:approve, run_id, approval}, from, state)
        else
          {:reply,
           {:error,
            Error.new(:approval_mismatch, :dispatch, "approval does not name the granted decision")},
           state}
        end

      _ ->
        handle_call({:approve, run_id, approval}, from, state)
    end
  end

  defp control_outcome({:ok, %Run{id: id}} = reply), do: {reply, {:ok, id}}
  defp control_outcome({:error, %Error{} = error} = reply), do: {reply, {:error, error}}

  defp names_decision?(decision, named) do
    decision["thing_id"] == named["thing_id"] and
      decision["action_name"] == named["action_name"] and
      same_value?(decision["input"], named["input"])
  end

  defp same_value?(left, right) when is_number(left) and is_number(right), do: left == right
  defp same_value?(left, right), do: left === right

  defp execute(%{id: "thermal"}, params, _), do: Thermal.run(params)
  defp execute(%{id: "window_anomaly"}, params, _), do: WindowAnomaly.run(params)
  defp execute(%{id: "smart_room"}, params, state), do: SmartRoom.run(params, state)

  defp build_run(experiment, params, sequence, started, outcome) do
    base = %Run{
      id: "run-#{sequence}",
      experiment: experiment.id,
      attempt: sequence,
      params: params,
      status: :failed,
      source_mode: Provenance.source_mode(),
      backend: "none",
      started_at: started
    }

    case outcome do
      {:ok, result} ->
        %{
          base
          | status: if(result[:decision], do: :awaiting_approval, else: :completed),
            backend: result.backend,
            duration_ms: result.duration_ms,
            summary: result.summary,
            tensor: result.tensor,
            timeseries: result.timeseries,
            assertions: result.assertions,
            proposal: result.proposal,
            decision: result[:decision],
            cleanup: %{status: :ok, details: %{disposable: true}}
        }
        |> Map.put(:record, nil)
        |> with_record(%{
          outcomes: result.outcomes,
          inputs: result.inputs,
          seed: result.seed,
          budgets: result.budgets
        })

      {:error, error} ->
        %{
          base
          | error: error_view(error),
            assertions: [Runs.assertion("run:completed", false, "run failed")]
        }
        |> with_record(%{outcomes: %{error: error_code(error)}, inputs: [], seed: 0, budgets: %{}})
    end
  end

  defp with_record(%Run{} = run, extras) when is_map_key(extras, :outcomes) do
    case Evidence.record(run, extras) do
      {:ok, record, digest} -> %{run | record: record, record_digest: digest}
      {:error, _} -> run
    end
  end

  defp with_record(%Run{record: %{} = record} = run, _) do
    extras = %{
      outcomes: Map.merge(record.outcomes, %{decision: :dispatched, effect: run.effect}),
      inputs: record.inputs,
      seed: record.seed,
      budgets: record.budgets
    }

    with_record(run, extras)
  end

  defp dispatched_assertion(%{id: "room:dispatch-once"} = assertion),
    do: %{assertion | status: :pass, note: "policy dispatched the decision exactly once"}

  defp dispatched_assertion(assertion), do: assertion

  defp fetch_run_state(state, id) when is_binary(id) do
    Map.fetch(state.runs, id) |> known(:unknown_run, "run is not in this room")
  end

  defp fetch_run_state(_, _),
    do: {:error, Error.new(:unknown_run, :room, "run is not in this room")}

  defp known({:ok, value}, _, _), do: {:ok, value}
  defp known(:error, code, message), do: {:error, Error.new(code, :room, message)}

  defp capacity(current, max, _, _) when current < max, do: :ok
  defp capacity(_, _, code, message), do: {:error, Error.new(code, :room, message)}

  defp no_pending_decision(state, %{id: "smart_room"}) do
    if Enum.any?(state.runs, fn {_, run} -> run.status == :awaiting_approval end) do
      {:error, Error.new(:pending_decision, :room, "approve or cancel the pending decision first")}
    else
      :ok
    end
  end

  defp no_pending_decision(_, _), do: :ok

  defp unavailable({:ok, live}), do: {:ok, live}

  defp unavailable({:error, :unavailable}),
    do: {:error, Error.new(:unavailable, :metrics, "no measurements collected")}

  defp unavailable({:error, %Error{} = error}), do: {:error, error}

  defp dataset_query(query, scope) when is_list(query) do
    keys = Keyword.keys(query)

    if Keyword.keyword?(query) and length(keys) == length(Enum.uniq(keys)) do
      {:ok, Keyword.put(query, :scope, scope)}
    else
      {:error, Error.new(:invalid_query, :metrics, "query options must be unique keywords")}
    end
  end

  defp dataset_query(_, _),
    do: {:error, Error.new(:invalid_query, :metrics, "query options must be a keyword list")}

  defp td_error({:ok, value}), do: {:ok, value}

  defp td_error({:error, other}),
    do:
      {:error,
       Error.new(:td_rejected, :things, "TD was not admitted",
         details: %{reason: error_code(other)}
       )}

  defp error_view(%Error{} = error),
    do: %{
      code: Atom.to_string(error.code),
      phase: Atom.to_string(error.phase),
      message: error.message
    }

  defp error_view(other),
    do: %{code: Atom.to_string(error_code(other)), phase: "run", message: "run failed"}

  defp error_code(%{code: code}) when is_atom(code), do: code
  defp error_code(code) when is_atom(code), do: code
  defp error_code(list) when is_list(list), do: :invalid
  defp error_code(_), do: :error

  defp start_things(lab, token) do
    Enum.reduce_while(@things, {:ok, %{}}, fn spec, {:ok, acc} ->
      {:ok, td} = thing_description(spec.key)
      document = ThingDescription.to_map(td)

      child =
        {Thing,
         id: spec.key,
         td: td,
         state: spec.state,
         tokens: %{"bearer_sc" => token},
         actions: %{
           "setTarget" => fn input, state ->
             {:ok, %{"accepted" => true}, :accepted, Map.put(state, "target", input)}
           end
         }}

      case managed(lab, :things, child) do
        {:ok, pid} ->
          {:cont,
           {:ok,
            Map.put(acc, spec.key, %{
              key: spec.key,
              pid: pid,
              td: td,
              id: document["id"],
              document: document,
              scheme: spec.scheme
            })}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp thing_description("actuator") do
    :wotex_lab
    |> Application.app_dir("priv/fixtures/loopback/thing-description.json")
    |> File.read!()
    |> ThingDescription.parse()
  end

  defp thing_description("thermostat") do
    ThingDescription.from_map(%{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:wotex:lab:workbench:thermostat",
      "title" => "Simulated thermostat",
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "properties" => %{
        "temperature" => %{
          "type" => "number",
          "unit" => "Cel",
          "readOnly" => true,
          "forms" => [
            %{"href" => "sim-thermostat://thermostat/temperature", "op" => "readproperty"}
          ]
        }
      }
    })
  end

  defp thing_description("meter") do
    ThingDescription.from_map(%{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:wotex:lab:workbench:meter",
      "title" => "Simulated energy meter",
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "properties" => %{
        "power" => %{
          "type" => "number",
          "unit" => "W",
          "readOnly" => true,
          "forms" => [%{"href" => "sim-meter://meter/power", "op" => "readproperty"}]
        }
      }
    })
  end

  defp service(repository, clock, identifier, things) do
    Service.new(
      repository: {EtsRepository, repository},
      authorization: {Authorization, :allow_all},
      clock: {Clock, {:agent, clock}},
      identifier: {Identifier, identifier},
      introduction: things["thermostat"].td
    )
  end

  defp register_all(service, context, things) do
    Enum.reduce_while(things, :ok, fn {_, thing}, :ok ->
      case Directory.register(service, thing.td, context) do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp transport_opts(things, token) do
    profiles =
      Enum.map(@things, fn %{role: role, scheme: scheme} ->
        {:ok, profile} =
          BindingProfile.new(id: role, schemes: [scheme], operations: Wotex.Runtime.operations())

        profile
      end)

    [
      profiles: profiles,
      transports:
        Map.new(profiles, &{&1.id, {Loopback, %{host: things[Atom.to_string(&1.id)].pid}}}),
      credentials:
        {StaticRef, %{references: %{"bearer_sc" => "room"}, lookup: fn "room" -> {:ok, token} end}}
    ]
  end

  defp managed(lab, role, child) do
    case Wotex.Lab.start_child(lab, role, child) do
      {:ok, pid} = started ->
        Process.put(:room_owned_lab, [{role, pid} | Process.get(:room_owned_lab, [])])
        started

      error ->
        error
    end
  end

  defp local({:ok, pid} = started) when is_pid(pid) do
    Process.put(:room_owned_local, [pid | Process.get(:room_owned_local, [])])
    started
  end

  defp local(error), do: error

  defp take_owned(key) do
    owned = Process.get(key, [])
    Process.delete(key)
    owned
  end

  defp cleanup_started(lab) do
    cleanup(lab, take_owned(:room_owned_local), take_owned(:room_owned_lab))
  end

  defp cleanup(lab, local, managed) do
    Enum.each(local, &stop_local/1)
    Enum.each(managed, fn {role, pid} -> Wotex.Lab.stop_child(lab, role, pid) end)
  end

  defp stop_local(pid) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
  catch
    :exit, _ -> :ok
  end

  defp schedule_history, do: Process.send_after(self(), :sample_history, @history_interval_ms)

  # Snapshots advance wall time strictly, so a capture in the same millisecond
  # is skipped before it consumes a collector sequence and leaves a false gap.
  defp sample_history(%{history: history} = state) do
    with true <- System.system_time(:millisecond) > history.last_wall_ms,
         {:ok, snapshot} <- Collector.snapshot(history.collector),
         {:ok, _} <- History.put(history.store, snapshot) do
      %{state | history: %{history | last_wall_ms: snapshot.wall_time_ms}}
    else
      _ -> state
    end
  end

  defp record_metric(scope, component, operation, duration_ms, outcome) do
    duration = System.convert_time_unit(duration_ms, :millisecond, :native)

    Metrics.record(
      scope,
      component,
      operation,
      %{duration: duration},
      %{outcome: outcome, profile: :workbench}
    )
  end
end
