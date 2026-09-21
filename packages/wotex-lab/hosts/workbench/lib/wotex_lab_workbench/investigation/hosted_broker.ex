defmodule WotexLabWorkbench.Investigation.HostedBroker do
  @moduledoc """
  Owns isolated hosted BeamLens workers and their loopback capabilities.

  There is no queue. At most eight one-request worker VMs run for the host;
  tenant concurrency and rate admission happen before this boundary. Owner
  death, timeout and explicit cancellation terminate the task invoking the
  native custodian. Provider and metric-query capabilities exist only while
  their request is active and each has an eight-call ceiling.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options, Telemetry}
  alias WotexLabWorkbench.Investigation.HostedCommand

  @max_active 8
  @max_bridge_calls 8
  @max_prompt_bytes 4 * 1_024
  @timeout_margin_ms 2_000
  @providers [:codex_then_ollama, :ollama]

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:command, :provider]),
         {:ok, command} <- HostedCommand.configure(Keyword.get(opts, :command, [])),
         provider when provider in @providers <- Keyword.get(opts, :provider) do
      GenServer.start_link(
        __MODULE__,
        %{command: command, provider: provider},
        name: __MODULE__
      )
    else
      {:error, _} = error -> error
      _ -> failure(:invalid_hosted_investigation)
    end
  end

  @doc "Starts one owner-bound isolated investigation without queueing."
  @spec ask(map(), String.t(), term(), term()) ::
          {:ok, reference()} | {:error, Error.t()}
  def ask(binding, prompt, current \\ nil, baseline \\ nil) do
    GenServer.call(__MODULE__, {:ask, binding, prompt, current, baseline})
  catch
    :exit, _ -> failure(:hosted_investigation_unavailable)
  end

  @doc "Cancels the calling owner's active request."
  @spec cancel(reference()) :: :ok | {:error, Error.t()}
  def cancel(reference) when is_reference(reference) do
    GenServer.call(__MODULE__, {:cancel, reference})
  catch
    :exit, _ -> failure(:hosted_investigation_unavailable)
  end

  def cancel(_), do: failure(:unknown_hosted_investigation)

  @doc false
  @spec authorize_provider(term()) :: {:ok, :codex_then_ollama | :ollama} | {:error, atom()}
  def authorize_provider(capability) do
    GenServer.call(__MODULE__, {:authorize, :provider, capability})
  catch
    :exit, _ -> {:error, :bridge_denied}
  end

  @doc false
  @spec authorize_query(term()) :: {:ok, map()} | {:error, atom()}
  def authorize_query(capability) do
    GenServer.call(__MODULE__, {:authorize, :query, capability})
  catch
    :exit, _ -> {:error, :bridge_denied}
  end

  @doc false
  @spec record_provider(term(), term()) :: :ok
  def record_provider(capability, metadata) do
    GenServer.call(__MODULE__, {:record_provider, capability, metadata})
  catch
    :exit, _ -> :ok
  end

  @doc "Returns bounded host counters without tenant, prompt or capability data."
  @spec status() :: map() | {:error, Error.t()}
  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _ -> failure(:hosted_investigation_unavailable)
  end

  @impl GenServer
  def init(config),
    do: {:ok, Map.merge(config, %{active: %{}, completed: 0, failed: 0, cancelled: 0})}

  @impl GenServer
  def handle_call({:ask, _, _, _, _}, _, state) when map_size(state.active) >= @max_active,
    do: {:reply, failure(:hosted_investigation_capacity), state}

  def handle_call({:ask, binding, prompt, current, baseline}, {owner, _}, state) do
    with :ok <- validate_binding(binding),
         :ok <- validate_prompt(prompt),
         {:ok, context_bytes} <- validate_context(current, baseline) do
      reference = make_ref()
      provider_capability = capability()
      query_capability = capability()

      request = %{
        "schema_version" => "wotex-lab-hosted-investigation/v1",
        "prompt" => prompt,
        "current" => current,
        "baseline" => baseline,
        "provider_url" => Keyword.fetch!(state.command, :provider_url),
        "query_url" => Keyword.fetch!(state.command, :query_url),
        "provider_capability" => provider_capability,
        "query_capability" => query_capability,
        "timeout_ms" => min(Keyword.fetch!(state.command, :timeout_ms), 29_000)
      }

      command = state.command

      task =
        Task.Supervisor.async_nolink(WotexLabHosted.TaskSupervisor, fn ->
          HostedCommand.run(command, request)
        end)

      timeout = Keyword.fetch!(command, :timeout_ms) + @timeout_margin_ms
      timer = Process.send_after(self(), {:timeout, reference}, timeout)
      owner_monitor = Process.monitor(owner)
      started_at = System.monotonic_time()

      :telemetry.execute(
        [:wotex, :lab, :metrics, :investigation, :start],
        %{monotonic_time: started_at, system_time: System.system_time()},
        %{profile: :other}
      )

      active = %{
        owner: owner,
        owner_monitor: owner_monitor,
        task: task,
        timer: timer,
        binding: binding,
        provider_capability: provider_capability,
        query_capability: query_capability,
        provider_calls: 0,
        query_calls: 0,
        provider_result: nil,
        context_bytes: context_bytes,
        started_at: started_at
      }

      {:reply, {:ok, reference}, put_in(state, [:active, reference], active)}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:cancel, reference}, {owner, _}, state) do
    case state.active[reference] do
      %{owner: ^owner} ->
        {:reply, :ok, finish(state, reference, {:error, :investigation_cancelled}, true, true)}

      _ ->
        {:reply, failure(:unknown_hosted_investigation), state}
    end
  end

  def handle_call({:authorize, kind, capability}, _, state) do
    case authorized(state.active, kind, capability) do
      {:ok, reference, active} ->
        key = if kind == :provider, do: :provider_calls, else: :query_calls
        active = Map.update!(active, key, &(&1 + 1))
        state = put_in(state, [:active, reference], active)

        reply =
          case kind do
            :provider -> {:ok, state.provider}
            :query -> {:ok, active.binding}
          end

        {:reply, reply, state}

      :error ->
        {:reply, {:error, :bridge_denied}, state}
    end
  end

  def handle_call({:record_provider, capability, metadata}, _, state) do
    state =
      case authorized(state.active, :provider_record, capability) do
        {:ok, reference, active} ->
          put_in(state, [:active, reference], %{
            active
            | provider_result: provider_metadata(metadata)
          })

        :error ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call(:status, _, state) do
    {:reply,
     %{
       running: map_size(state.active),
       capacity: @max_active,
       completed: state.completed,
       failed: state.failed,
       cancelled: state.cancelled,
       isolated_worker: true
     }, state}
  end

  @impl GenServer
  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    case find_by_task(state.active, task_ref) do
      {:ok, reference, active} ->
        Process.demonitor(task_ref, [:flush])
        normalized = normalize(result, active.provider_result)
        {:noreply, finish(state, reference, normalized, false, true)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _, reason}, state) do
    case find_by_monitor(state.active, monitor) do
      {:owner, reference} ->
        {:noreply, finish(state, reference, {:error, :owner_down}, true, false)}

      {:task, reference} ->
        result = {:error, {:hosted_worker_failed, safe_reason(reason)}}
        {:noreply, finish(state, reference, result, false, true)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:timeout, reference}, state) do
    if Map.has_key?(state.active, reference),
      do: {:noreply, finish(state, reference, {:error, :investigation_timeout}, true, true)},
      else: {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    Enum.each(state.active, fn {reference, _} ->
      _ = finish(state, reference, {:error, :investigation_stopped}, true, false)
    end)

    :ok
  end

  defp finish(state, reference, result, kill?, notify?) do
    case Map.pop(state.active, reference) do
      {nil, _} ->
        state

      {active, remaining} ->
        Process.cancel_timer(active.timer)
        Process.demonitor(active.owner_monitor, [:flush])
        if kill?, do: Task.shutdown(active.task, :brutal_kill)
        if notify?, do: send(active.owner, {:hosted_investigation, reference, result})

        duration = max(System.monotonic_time() - active.started_at, 0)

        :telemetry.execute(
          [:wotex, :lab, :metrics, :investigation, :stop],
          %{duration: duration},
          %{outcome: telemetry_outcome(result), profile: :other}
        )

        Telemetry.event(
          :metrics,
          :investigation,
          %{
            tool_calls: active.provider_calls + active.query_calls,
            context_bytes: active.context_bytes
          },
          %{profile: :other}
        )

        counter =
          case result do
            {:ok, _, _} -> :completed
            {:error, reason} when reason in [:investigation_cancelled, :owner_down] -> :cancelled
            _ -> :failed
          end

        state
        |> Map.put(:active, remaining)
        |> Map.update!(counter, &(&1 + 1))
    end
  end

  defp authorized(active, kind, capability) when is_binary(capability) do
    Enum.reduce_while(active, :error, fn {reference, entry}, :error ->
      {expected, calls} =
        case kind do
          :query -> {entry.query_capability, entry.query_calls}
          :provider_record -> {entry.provider_capability, 0}
          _ -> {entry.provider_capability, entry.provider_calls}
        end

      if calls < @max_bridge_calls and secure_match?(capability, expected),
        do: {:halt, {:ok, reference, entry}},
        else: {:cont, :error}
    end)
  end

  defp authorized(_, _, _), do: :error

  defp find_by_task(active, task_ref) do
    Enum.find_value(active, :error, fn {reference, entry} ->
      if entry.task.ref == task_ref, do: {:ok, reference, entry}
    end)
  end

  defp find_by_monitor(active, monitor) do
    Enum.find_value(active, :error, fn {reference, entry} ->
      cond do
        entry.owner_monitor == monitor -> {:owner, reference}
        entry.task.ref == monitor -> {:task, reference}
        true -> nil
      end
    end)
  end

  defp validate_binding(%{instance: instance, durable: durable} = binding)
       when map_size(binding) == 2 and is_binary(instance) and is_function(durable, 1),
       do: :ok

  defp validate_binding(_), do: failure(:invalid_hosted_scope)

  defp validate_prompt(prompt)
       when is_binary(prompt) and byte_size(prompt) in 1..@max_prompt_bytes,
       do: if(String.trim(prompt) == "", do: failure(:invalid_prompt), else: :ok)

  defp validate_prompt(_), do: failure(:invalid_prompt)

  defp validate_context(current, baseline) do
    case Jason.encode(%{"current" => current, "baseline" => baseline}) do
      {:ok, encoded} when byte_size(encoded) <= 8 * 1_024 ->
        {:ok, context_bytes(current) + context_bytes(baseline)}

      _ ->
        failure(:invalid_context)
    end
  end

  defp context_bytes(nil), do: 0

  defp context_bytes(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> byte_size(encoded)
      _ -> 0
    end
  end

  defp normalize({:ok, %{"status" => "ok", "notifications" => notifications} = result}, provider)
       when is_list(notifications) do
    evidence = Map.get(result, "evidence", [])
    {:ok, %{notifications: notifications, evidence: evidence}, provider || %{}}
  end

  defp normalize({:ok, %{"status" => "error"}}, _),
    do: {:error, :diagnostics_unavailable}

  defp normalize({:error, %Error{code: code}}, _), do: {:error, code}
  defp normalize(_, _), do: {:error, :hosted_worker_failed}

  defp provider_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.take([:provider, :model, :reason, :plan_type, :quota, :usage])
    |> Map.put_new(:provider, nil)
    |> Map.put_new(:model, nil)
  end

  defp provider_metadata(_), do: %{}

  defp telemetry_outcome({:ok, _, _}), do: :ok
  defp telemetry_outcome({:error, :investigation_timeout}), do: :timeout

  defp telemetry_outcome({:error, reason})
       when reason in [:investigation_cancelled, :owner_down],
       do: :rejected

  defp telemetry_outcome(_), do: :error

  defp secure_match?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right),
       do: Plug.Crypto.secure_compare(left, right)

  defp secure_match?(_, _), do: false

  defp capability, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason(_), do: :worker_failure

  defp failure(code),
    do: {:error, Error.new(code, :hosted_investigation, "hosted investigation is refused")}
end
