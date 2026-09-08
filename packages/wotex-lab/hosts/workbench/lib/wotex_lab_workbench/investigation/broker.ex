defmodule WotexLabWorkbench.Investigation.Broker do
  @moduledoc """
  Owner-bound admission and cancellation for the single trusted-host BeamLens
  investigation.

  There is no queue. One request runs at a time for at most 30 seconds. Caller
  death, explicit cancellation, timeout and normal completion all kill the
  worker, clear supplied run context and replace BeamLens's static operator and
  coordinator so neither conversation nor queued work survives.
  """

  use GenServer

  alias Wotex.Lab.Telemetry
  alias WotexLabWorkbench.Investigation.{BeamlensSupervisor, ContextStore, Skill}
  alias WotexLabWorkbench.Runs

  @timeout_ms 30_000
  @max_prompt_bytes 4_096
  @option_keys [:run, :baseline]

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Admits one prompt and asynchronously returns its owner-only reference."
  @spec ask(String.t(), keyword()) :: {:ok, reference()} | {:error, atom()}
  def ask(prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:ask, prompt, opts})
  catch
    :exit, _reason -> {:error, :investigation_disabled}
  end

  @doc "Cancels the caller's active investigation."
  @spec cancel(reference()) :: :ok | {:error, atom()}
  def cancel(reference) when is_reference(reference) do
    GenServer.call(__MODULE__, {:cancel, reference})
  catch
    :exit, _reason -> {:error, :investigation_disabled}
  end

  def cancel(_reference), do: {:error, :unknown_investigation}

  @doc "Returns only bounded state/counters, never prompt or run data."
  @spec status() :: map() | {:error, atom()}
  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _reason -> {:error, :investigation_disabled}
  end

  @impl GenServer
  def init(_opts) do
    timeout = Application.get_env(:wotex_lab_workbench, :beamlens_timeout_ms, @timeout_ms)

    timeout =
      if is_integer(timeout) and timeout in 1..@timeout_ms,
        do: timeout,
        else: @timeout_ms

    runner =
      Application.get_env(
        :wotex_lab_workbench,
        :beamlens_operator_runner,
        WotexLabWorkbench.Investigation.OperatorRunner
      )

    {:ok,
     %{
       active: nil,
       completed: 0,
       cancelled: 0,
       timed_out: 0,
       timeout_ms: timeout,
       runner: runner
     }}
  end

  @impl GenServer
  def handle_call({:ask, _prompt, _opts}, _from, %{active: active} = state)
      when active != nil,
      do: {:reply, {:error, :investigation_busy}, state}

  def handle_call({:ask, prompt, opts}, {owner, _tag}, state) do
    with :ok <- validate_prompt(prompt),
         :ok <- validate_options(opts),
         :ok <- ContextStore.put(Keyword.get(opts, :run), Keyword.get(opts, :baseline)),
         {:ok, operator} <- operator() do
      request = make_ref()
      owner_monitor = Process.monitor(owner)

      runner = state.runner
      timeout = state.timeout_ms

      task =
        Task.Supervisor.async_nolink(Beamlens.TaskSupervisor, fn ->
          runner.run(operator, prompt, timeout)
        end)

      timer = Process.send_after(self(), {:timeout, request}, timeout)
      started_at = System.monotonic_time()

      :telemetry.execute(
        [:wotex, :lab, :metrics, :investigation, :start],
        %{monotonic_time: started_at, system_time: System.system_time()},
        %{profile: :other}
      )

      active = %{
        request: request,
        owner: owner,
        owner_monitor: owner_monitor,
        task: task,
        timer: timer,
        started_at: started_at
      }

      {:reply, {:ok, request}, %{state | active: active}}
    else
      {:error, reason} ->
        ContextStore.clear()
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel, request}, {owner, _tag}, %{active: active} = state) do
    if active != nil and active.request == request and active.owner == owner do
      {:reply, :ok, finish(state, {:error, :investigation_cancelled}, :cancelled, true)}
    else
      {:reply, {:error, :unknown_investigation}, state}
    end
  end

  def handle_call(:status, _from, state) do
    reply = %{
      running: state.active != nil,
      completed: state.completed,
      cancelled: state.cancelled,
      timed_out: state.timed_out,
      max_duration_ms: state.timeout_ms,
      max_model_turns: BeamlensSupervisor.max_iterations(),
      max_tool_calls: BeamlensSupervisor.max_iterations(),
      max_context_bytes: 32 * 1_024
    }

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info({task_ref, result}, %{active: %{task: %Task{ref: task_ref}}} = state) do
    Process.demonitor(task_ref, [:flush])
    result = normalize_result(result)
    {:noreply, finish(state, result, :completed, false)}
  end

  def handle_info({:timeout, request}, %{active: %{request: request}} = state),
    do: {:noreply, finish(state, {:error, :investigation_timeout}, :timed_out, true)}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{active: %{owner_monitor: monitor}} = state
      ),
      do: {:noreply, finish(state, {:error, :owner_down}, :cancelled, true, false)}

  def handle_info(
        {:DOWN, task_ref, :process, _pid, reason},
        %{active: %{task: %Task{ref: task_ref}}} = state
      ),
      do:
        {:noreply,
         finish(state, {:error, {:investigation_failed, safe_reason(reason)}}, :completed, false)}

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{active: nil}), do: ContextStore.clear()

  def terminate(_reason, state) do
    _state = finish(state, {:error, :investigation_stopped}, :cancelled, true, false)
    :ok
  end

  defp finish(state, result, counter, kill?, notify? \\ true) do
    active = state.active
    Process.cancel_timer(active.timer)
    Process.demonitor(active.owner_monitor, [:flush])
    if kill?, do: Task.shutdown(active.task, :brutal_kill)
    if notify?, do: send(active.owner, {:investigation, active.request, result})
    usage = ContextStore.usage()
    ContextStore.clear()
    BeamlensSupervisor.reset()

    duration = max(System.monotonic_time() - active.started_at, 0)

    :telemetry.execute(
      [:wotex, :lab, :metrics, :investigation, :stop],
      %{duration: duration},
      %{outcome: telemetry_outcome(result), profile: :other}
    )

    Telemetry.event(:metrics, :investigation, usage, %{profile: :other})

    increment(%{state | active: nil}, counter)
  end

  defp increment(state, :completed), do: %{state | completed: state.completed + 1}
  defp increment(state, :cancelled), do: %{state | cancelled: state.cancelled + 1}
  defp increment(state, :timed_out), do: %{state | timed_out: state.timed_out + 1}

  defp telemetry_outcome({:ok, _notifications}), do: :ok
  defp telemetry_outcome({:error, :investigation_timeout}), do: :timeout

  defp telemetry_outcome({:error, reason}) when reason in [:investigation_cancelled, :owner_down],
    do: :rejected

  defp telemetry_outcome(_result), do: :error

  defp operator do
    case Registry.lookup(Beamlens.OperatorRegistry, Skill) do
      [{pid, _value}] ->
        if Beamlens.Operator.status(pid).running,
          do: {:error, :investigation_busy},
          else: {:ok, pid}

      [] ->
        {:error, :investigation_unavailable}
    end
  catch
    :exit, _reason -> {:error, :investigation_unavailable}
  end

  defp validate_prompt(prompt)
       when is_binary(prompt) and byte_size(prompt) in 1..@max_prompt_bytes do
    if String.trim(prompt) == "", do: {:error, :invalid_prompt}, else: :ok
  end

  defp validate_prompt(_prompt), do: {:error, :invalid_prompt}

  defp validate_options(opts) when is_list(opts) do
    keys = Keyword.keys(opts)

    if Keyword.keyword?(opts) and length(keys) == length(Enum.uniq(keys)) and
         Enum.all?(keys, &(&1 in @option_keys)),
       do: :ok,
       else: {:error, :invalid_context}
  end

  defp validate_options(_opts), do: {:error, :invalid_context}

  defp normalize_result({:ok, notifications}),
    do: {:ok, %{notifications: Runs.plain(notifications)}}

  defp normalize_result({:error, reason}),
    do: {:error, {:investigation_failed, safe_reason(reason)}}

  defp normalize_result(other), do: {:error, {:investigation_failed, safe_reason(other)}}

  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason(_reason), do: :provider_failure
end
