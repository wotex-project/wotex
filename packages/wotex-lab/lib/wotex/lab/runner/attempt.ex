defmodule Wotex.Lab.Runner.Attempt do
  @moduledoc """
  One admitted run as a process under the instance's session supervisor.

  The attempt moves `admitted -> starting -> running -> stopping -> terminal`.
  Starting places every component's child specifications under the owning
  instance; a failure unwinds what already started and ends in `error`.
  Running executes the definition's steps in dependency order, each in a
  monitored worker with the remaining wall budget, so a raise, throw, exit,
  invalid return or hang inside a component becomes a normalized, redacted
  step error and never escapes. Stopping runs bounded cleanup: component
  children are terminated through the instance, the private work directory is
  removed, and a cleanup failure turns any outcome into `error`. Cleanup is
  bounded by the `cleanup_ms` budget: a child still running when it is spent
  is killed and recorded as a forced `cleanup_budget_exhausted` failure. Terminal
  outcomes are `pass`, `fail`, `unsupported`, `timeout`, `cancelled` and
  `error`; a forced kill is recorded as such. A result that arrives after the
  attempt left `running` is ignored, so a late worker cannot complete a new
  attempt. Every phase change and step is reported to the observer as
  `{:wotex_lab_run, attempt_id, event}` and appended to the recording.
  """

  use GenServer

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Runner.{Definition, Recording}
  alias Wotex.Lab.Scenario

  @phases [:admitted, :starting, :running, :stopping, :terminal]
  @forced_stop_ms 1_000

  @doc false
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :attempt_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "The current phase, outcome and counters."
  @spec status(pid()) :: map()
  def status(attempt), do: GenServer.call(attempt, :status)

  @doc "Blocks until the attempt is terminal or `timeout` elapses; returns the final status."
  @spec await(pid(), timeout()) :: {:ok, map()} | {:error, :timeout}
  def await(attempt, timeout) do
    monitor = Process.monitor(attempt)
    :ok = GenServer.call(attempt, {:await, self()})

    receive do
      {:wotex_lab_run_done, ^attempt, status} ->
        Process.demonitor(monitor, [:flush])
        {:ok, status}

      {:DOWN, ^monitor, :process, ^attempt, _} ->
        {:error, :timeout}
    after
      timeout ->
        Process.demonitor(monitor, [:flush])
        {:error, :timeout}
    end
  end

  @doc "Requests cancellation; idempotent."
  @spec cancel(pid()) :: :ok
  def cancel(attempt), do: GenServer.call(attempt, :cancel)

  @doc "Forces the attempt to stop now; recorded as a forced kill."
  @spec kill(pid()) :: :ok
  def kill(attempt), do: GenServer.call(attempt, :kill)

  @impl GenServer
  def init(opts) do
    scenario = Keyword.fetch!(opts, :scenario)
    definition = Keyword.fetch!(opts, :definition)
    host = Keyword.fetch!(opts, :host)
    attempt_id = Keyword.fetch!(opts, :attempt_id)
    seed = host.seed || scenario_seed(scenario)
    now = host.clock.()

    state = %{
      attempt_id: attempt_id,
      scenario: scenario,
      definition: definition,
      host: host,
      seed: seed,
      phase: :admitted,
      outcome: nil,
      reason: nil,
      forced: false,
      started_at: now,
      deadline: now + host.budgets.wall_ms,
      children: %{},
      results: %{},
      errors: %{},
      events: [],
      pending: [],
      worker: nil,
      waiters: [],
      work_dir: Path.join(host.work_root, attempt_id),
      observer_monitor: if(host.observer, do: Process.monitor(host.observer)),
      delivery_overflow: false,
      cleanup: nil
    }

    Process.flag(:trap_exit, true)
    {:ok, notify(state, {:phase, :admitted}), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    case phase(state, :starting) do
      %{delivery_overflow: true} = state -> {:noreply, finish(state, :error, nil)}
      state -> {:noreply, start(state)}
    end
  end

  @impl GenServer
  def handle_call(:status, _, state), do: {:reply, status_map(state), state}

  def handle_call({:await, pid}, _, %{phase: :terminal} = state) do
    send(pid, {:wotex_lab_run_done, self(), status_map(state)})
    {:reply, :ok, state}
  end

  def handle_call({:await, pid}, _, state),
    do: {:reply, :ok, %{state | waiters: [pid | state.waiters]}}

  def handle_call(:cancel, _, %{phase: phase} = state) when phase in [:stopping, :terminal],
    do: {:reply, :ok, state}

  def handle_call(:cancel, _, state),
    do: {:reply, :ok, finish(state, :cancelled, %{code: :cancelled})}

  def handle_call(:kill, _, %{phase: :terminal} = state), do: {:reply, :ok, state}

  def handle_call(:kill, _, state),
    do: {:reply, :ok, finish(%{state | forced: true}, :error, %{code: :forced_kill})}

  @impl GenServer
  def handle_info(
        {:step_result, attempt_id, step_id, ref, result},
        %{phase: :running, worker: {ref, worker_step_id, _}, attempt_id: attempt_id} = state
      ) do
    if step_id == worker_step_id do
      Process.demonitor(ref, [:flush])
      {:noreply, state |> record_step(step_id, result) |> next_step()}
    else
      {:noreply, state}
    end
  end

  def handle_info({:step_result, _, _, _, _}, state), do: {:noreply, state}

  def handle_info(
        {:DOWN, ref, :process, _, reason},
        %{phase: :running, worker: {ref, step_id, _}} = state
      ) do
    {:noreply, state |> record_step(step_id, {:error, crash(reason)}) |> next_step()}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{observer_monitor: ref} = state)
      when state.phase in [:starting, :running] do
    {:noreply, finish(%{state | observer_monitor: nil}, :error, %{code: :receiver_down})}
  end

  def handle_info({:wall_deadline, attempt_id}, %{attempt_id: attempt_id, phase: phase} = state)
      when phase in [:starting, :running] do
    {:noreply, finish(state, :timeout, %{code: :wall_budget_exhausted})}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, %{phase: :terminal}), do: :ok

  def terminate(_, state) do
    _ = cleanup(state)
    :ok
  end

  defp start(state) do
    case start_children(state) do
      {:ok, state} ->
        case File.mkdir_p(state.work_dir) do
          :ok ->
            state
            |> Map.put(:pending, Definition.order(state.definition))
            |> phase(:running)
            |> next_step()

          {:error, _} ->
            finish(state, :error, %{code: :work_directory_unavailable})
        end

      {:error, state, error} ->
        finish(state, :error, %{code: error.code, phase: :starting})
    end
  end

  defp start_children(state) do
    Process.send_after(
      self(),
      {:wall_deadline, state.attempt_id},
      max(state.deadline - state.host.clock.(), 0)
    )

    limit = state.host.budgets.children_per_role

    state.host.configs
    |> Enum.reduce_while({:ok, state}, fn {module, config}, {:ok, acc} ->
      case start_component(acc, module, config, limit) do
        {:ok, started} -> {:cont, {:ok, started}}
        {:error, started, error} -> {:halt, {:error, started, error}}
      end
    end)
  end

  defp start_component(state, module, config, limit) do
    component_config =
      Keyword.merge(config,
        attempt_id: state.attempt_id,
        seed: state.seed,
        instance: state.host.instance
      )

    with {:ok, specs} <- child_specs(module, component_config),
         :ok <- child_capacity(state, specs, limit) do
      start_specs(state, module, specs)
    else
      {:error, %Error{} = error} -> {:error, state, error}
    end
  end

  defp child_capacity(state, specs, limit) do
    if map_size(state.children) + length(specs) <= limit,
      do: :ok,
      else:
        {:error,
         Error.new(
           :children_budget_exhausted,
           :starting,
           "component children exceed the role budget"
         )}
  end

  defp child_specs(module, config) do
    case module.child_specs(config) do
      specs when is_list(specs) and length(specs) <= 10_000 ->
        {:ok, specs}

      _ ->
        {:error, Error.new(:invalid_child_specs, :starting, "component child specs are invalid")}
    end
  rescue
    _ ->
      {:error, Error.new(:child_specs_raised, :starting, "component child specs raised")}
  catch
    _, _ ->
      {:error, Error.new(:child_specs_failed, :starting, "component child specs failed")}
  end

  defp start_specs(state, module, specs) do
    Enum.reduce_while(specs, {:ok, state}, fn spec, {:ok, acc} ->
      case start_child(acc.host.instance, spec) do
        {:ok, pid} ->
          {:cont, {:ok, %{acc | children: Map.put(acc.children, pid, module)}}}

        {:error, %Error{} = error} ->
          {:halt, {:error, acc, error}}

        {:error, reason} ->
          {:halt,
           {:error, acc,
            Error.new(:child_start_failed, :starting, "component child did not start",
              details: %{module: module, reason: redact(reason)}
            )}}
      end
    end)
  end

  defp start_child(instance, spec) do
    Lab.start_child(instance, :things, spec)
  catch
    :exit, _ ->
      {:error, Error.new(:supervisor_unavailable, :starting, "component supervisor is unavailable")}
  end

  defp next_step(%{delivery_overflow: true} = state), do: finish(state, :error, nil)

  defp next_step(%{pending: []} = state), do: finish(state, assess(state), nil)

  defp next_step(%{pending: [step | rest]} = state) do
    remaining = state.deadline - state.host.clock.()
    executed = map_size(state.results) + map_size(state.errors)

    cond do
      executed >= state.host.budgets.max_steps ->
        finish(state, :error, %{code: :step_budget_exhausted})

      remaining <= 0 ->
        finish(state, :timeout, %{code: :wall_budget_exhausted})

      Enum.any?(step.depends_on, &Map.has_key?(state.errors, &1)) ->
        state
        |> record_step(
          step.id,
          {:error, Error.new(:dependency_failed, :running, "a dependency step failed")}
        )
        |> Map.put(:pending, rest)
        |> next_step()

      byte_size(:erlang.term_to_binary(step.input)) > state.host.budgets.ingress_bytes ->
        state
        |> record_step(
          step.id,
          {:error,
           Error.new(:ingress_budget_exhausted, :running, "step input exceeds the ingress budget")}
        )
        |> Map.put(:pending, rest)
        |> next_step()

      true ->
        spawn_worker(%{state | pending: rest}, step, remaining)
    end
  end

  defp spawn_worker(state, step, remaining) do
    module = Map.fetch!(state.host.modules, step.capability)
    attempt = self()
    attempt_id = state.attempt_id
    fault = Map.get(state.definition.faults, step.id)

    context = %{
      attempt_id: attempt_id,
      step_id: step.id,
      seed: :erlang.phash2({state.seed, step.id}, 4_294_967_296),
      remaining_ms: remaining,
      instance: state.host.instance,
      work_dir: state.work_dir,
      children: for({pid, ^module} <- state.children, do: pid),
      results: Map.take(state.results, step.depends_on),
      budgets: state.host.budgets
    }

    {pid, ref} =
      spawn_monitor(fn ->
        result = safe_execute(fault, module, step, context)
        send(attempt, {:step_result, attempt_id, step.id, ref_placeholder(), result})
      end)

    # The worker learns its own monitor reference from the attempt so a late
    # message cannot masquerade as the current step.
    send(pid, {:monitor_ref, ref})
    {_, _} = {pid, ref}
    %{state | worker: {ref, step.id, pid}}
  end

  defp ref_placeholder do
    receive do
      {:monitor_ref, ref} -> ref
    after
      1_000 -> :no_ref
    end
  end

  defp execute("raise", _, _, _), do: raise("injected fault")
  defp execute("throw", _, _, _), do: throw(:injected_fault)
  defp execute("exit", _, _, _), do: exit(:injected_fault)
  defp execute("invalid_return", _, _, _), do: :not_a_result
  defp execute("hang", _, _, _), do: Process.sleep(:infinity)
  defp execute(nil, module, step, context), do: module.execute(step.operation, step.input, context)

  defp safe_execute(fault, module, step, context) do
    execute(fault, module, step, context)
  rescue
    exception ->
      {:error,
       Error.new(:component_raised, :running, "component raised",
         details: %{exception: exception.__struct__}
       )}
  catch
    :throw, _ -> {:error, Error.new(:component_threw, :running, "component threw")}
    :exit, _ -> {:error, Error.new(:component_exited, :running, "component exited")}
  end

  defp record_step(state, step_id, {:ok, value}) do
    if byte_size(:erlang.term_to_binary(value)) > state.host.budgets.ingress_bytes do
      record_step(
        state,
        step_id,
        {:error,
         Error.new(:ingress_budget_exhausted, :running, "step value exceeds the ingress budget")}
      )
    else
      event = %{
        step: step_id,
        input_digest: digest(input_of(state, step_id)),
        outcome: :ok,
        digest: digest(value)
      }

      state = notify(state, {:step, step_id, :ok})

      %{
        state
        | results: Map.put(state.results, step_id, value),
          events: [event | state.events],
          worker: nil
      }
    end
  end

  defp record_step(state, step_id, {:error, %Error{} = error}) do
    event = %{
      step: step_id,
      input_digest: digest(input_of(state, step_id)),
      outcome: :error,
      digest: digest(error.code)
    }

    state = notify(state, {:step, step_id, :error})

    %{
      state
      | errors: Map.put(state.errors, step_id, %{code: error.code, phase: error.phase}),
        events: [event | state.events],
        worker: nil
    }
  end

  defp record_step(state, step_id, _),
    do:
      record_step(
        state,
        step_id,
        {:error,
         Error.new(
           :invalid_component_return,
           :running,
           "component returned neither {:ok, value} nor {:error, error}"
         )}
      )

  defp input_of(state, step_id), do: Enum.find(state.definition.steps, &(&1.id == step_id)).input

  defp crash({:shutdown, _}),
    do: Error.new(:component_stopped, :running, "component worker stopped")

  defp crash(:killed), do: Error.new(:component_killed, :running, "component worker was killed")

  defp crash({%{__struct__: exception}, _}) when is_atom(exception),
    do: Error.new(:component_raised, :running, "component raised", details: %{exception: exception})

  defp crash({{:nocatch, _}, _}),
    do: Error.new(:component_threw, :running, "component threw")

  defp crash(_), do: Error.new(:component_exited, :running, "component exited")

  defp assess(state) do
    cond do
      map_size(state.errors) > 0 -> :fail
      Enum.all?(state.definition.assertions, &assertion_holds?(&1, state.results)) -> :pass
      true -> :fail
    end
  end

  defp assertion_holds?(%{"step" => step, "equals" => expected} = assertion, results) do
    case Map.fetch(results, step) do
      {:ok, value} ->
        case Map.get(assertion, "key") do
          nil -> value == expected
          key when is_map(value) -> Map.get(value, key) == expected
          _ -> false
        end

      :error ->
        false
    end
  end

  defp finish(%{phase: :terminal} = state, _, _), do: state

  defp finish(state, outcome, reason) do
    state = phase(state, :stopping)
    state = kill_worker(state)
    cleanup_result = cleanup(state)
    {outcome, reason} = settle(state, cleanup_result, outcome, reason)
    state = %{state | outcome: outcome, reason: reason, cleanup: cleanup_result, children: %{}}
    state = state |> phase(:terminal) |> notify({:terminal, outcome})
    Enum.each(state.waiters, &send(&1, {:wotex_lab_run_done, self(), status_map(state)}))
    %{state | waiters: []}
  end

  defp settle(_, cleanup_result, _, _) when cleanup_result != :ok,
    do: {:error, %{code: :cleanup_failed, details: cleanup_result}}

  defp settle(%{delivery_overflow: true}, _, _, _),
    do: {:error, %{code: :delivery_budget_exhausted}}

  defp settle(_, _, outcome, reason), do: {outcome, reason}

  defp kill_worker(%{worker: {ref, _, pid}} = state) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
    %{state | worker: nil}
  end

  defp kill_worker(state), do: state

  defp cleanup(state) do
    deadline = state.host.clock.() + state.host.budgets.cleanup_ms

    failures = Enum.flat_map(state.children, &stop_owned_child(&1, state, deadline))

    case File.rm_rf(state.work_dir) do
      {:ok, _} -> cleanup_result(failures)
      {:error, reason, _} -> %{children: failures, work_dir: reason}
    end
  end

  # Each stop runs in a linked task bounded by what remains of the cleanup
  # budget. A child still running at the deadline is killed while its
  # supervisor termination is in flight, so it is removed rather than
  # restarted, and the forced stop is recorded as a cleanup failure.
  defp stop_owned_child({pid, module}, state, deadline) do
    instance = state.host.instance
    remaining = max(deadline - state.host.clock.(), 0)
    task = Task.async(fn -> Lab.stop_child(instance, :things, pid) end)

    case Task.yield(task, remaining) do
      {:ok, result} ->
        stop_result(result, module)

      {:exit, _} ->
        [%{module: module, reason: :supervisor_unavailable}]

      nil ->
        Process.exit(pid, :kill)
        _ = Task.yield(task, @forced_stop_ms) || Task.shutdown(task, :brutal_kill)
        [%{module: module, reason: :cleanup_budget_exhausted, forced: true}]
    end
  end

  defp stop_result(:ok, _), do: []
  defp stop_result({:error, :not_found}, _), do: []
  defp stop_result({:error, reason}, module), do: [%{module: module, reason: redact(reason)}]

  defp cleanup_result([]), do: :ok
  defp cleanup_result(failures), do: %{children: failures}

  defp phase(state, phase) when phase in @phases do
    %{notify(state, {:phase, phase}) | phase: phase}
  end

  # A delivery is sent only while the observer's queue is below the
  # queued-delivery budget; a refused delivery marks the attempt so it ends
  # with `delivery_budget_exhausted` instead of silently dropping events.
  defp notify(%{host: %{observer: pid}, attempt_id: id} = state, event) when is_pid(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, length} when length < state.host.budgets.queued_deliveries ->
        send(pid, {:wotex_lab_run, id, event})
        state

      {:message_queue_len, _} ->
        %{state | delivery_overflow: true}

      nil ->
        state
    end
  end

  defp notify(state, _), do: state

  defp status_map(state) do
    %{
      attempt_id: state.attempt_id,
      scenario_id: state.scenario.id,
      phase: state.phase,
      outcome: state.outcome,
      reason: state.reason,
      forced: state.forced,
      seed: state.seed,
      steps: %{
        completed: map_size(state.results),
        failed: map_size(state.errors),
        pending: length(state.pending)
      },
      results: state.results,
      errors: state.errors,
      cleanup: state.cleanup,
      recording: recording(state)
    }
  end

  defp recording(state) do
    %Recording{
      schema_version: "1.0.0",
      attempt_id: state.attempt_id,
      scenario_id: state.scenario.id,
      definition_id: state.definition.id,
      revision: state.definition.revision,
      seed: state.seed,
      lab_version: lab_version(),
      events: Enum.reverse(state.events),
      outcome: state.outcome || :running,
      forced: state.forced
    }
  end

  defp lab_version do
    case Application.spec(:wotex_lab, :vsn) do
      nil -> "unknown"
      vsn -> List.to_string(vsn)
    end
  end

  defp scenario_seed(scenario), do: Scenario.to_map(scenario)["seed"]

  defp digest(term), do: Digest.bytes(:erlang.term_to_binary(term, [:deterministic]))

  defp redact(reason) when is_atom(reason), do: reason
  defp redact({reason, _}) when is_atom(reason), do: reason
  defp redact(_), do: :redacted
end
