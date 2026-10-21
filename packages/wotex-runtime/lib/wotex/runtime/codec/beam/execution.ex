defmodule Wotex.Runtime.Codec.Beam.Execution do
  @moduledoc false

  alias Wotex.Runtime.Implementation.Error

  @spec run(pid(), pos_integer(), non_neg_integer(), (-> term()), (term() -> term())) :: term()
  def run(supervisor, budget, cleanup_ms, work, accept) do
    owner = self()
    token = make_ref()
    {timer, relay, relay_ref, alias} = deadline(owner, token, budget)

    {custodian, monitor} =
      spawn_monitor(fn -> custody(owner, token, supervisor, cleanup_ms, work) end)

    try do
      case await(custodian, monitor, token, cleanup_ms, relay_ref) do
        {:ok, returned} ->
          result = accept.(returned)
          if Process.read_timer(timer) == false, do: failure(:deadline_exceeded), else: result

        error ->
          error
      end
    after
      Process.cancel_timer(timer)
      :erlang.unalias(alias)
      Process.exit(relay, :kill)
      Process.demonitor(relay_ref, [:flush])
      Process.demonitor(monitor, [:flush])
      flush(token)
    end
  end

  defp deadline(owner, token, budget) do
    alias = :erlang.alias()

    {relay, monitor} =
      spawn_monitor(fn ->
        owner_ref = Process.monitor(owner)

        receive do
          {^token, :expired} -> send(alias, {token, :expired})
          {:DOWN, ^owner_ref, :process, ^owner, _} -> :ok
        end
      end)

    # Timer cancellation does not prove its notification has arrived. The alias
    # drops any notification still in flight when this call finishes.
    {Process.send_after(relay, {token, :expired}, budget), relay, monitor, alias}
  end

  defp await(custodian, monitor, token, cleanup_ms, relay_ref) do
    receive do
      {:DOWN, ^monitor, :process, ^custodian, {:shutdown, {^token, result}}} ->
        result

      {:DOWN, ^monitor, :process, ^custodian, _} ->
        failure(:cleanup_unconfirmed)

      {^token, :expired} ->
        cancel(custodian, monitor, token, cleanup_ms, :deadline_exceeded)

      {:DOWN, ^relay_ref, :process, _, _} ->
        cancel(custodian, monitor, token, cleanup_ms, :enforcement_unavailable)
    end
  end

  defp cancel(custodian, monitor, token, cleanup_ms, reason) do
    send(custodian, {token, :cancel, reason})

    receive do
      {:DOWN, ^monitor, :process, ^custodian, {:shutdown, {^token, result}}} -> result
      {:DOWN, ^monitor, :process, ^custodian, _} -> failure(:cleanup_unconfirmed)
    after
      cleanup_ms ->
        Process.exit(custodian, :kill)
        failure(:cleanup_unconfirmed)
    end
  end

  defp flush(token) do
    receive do
      {^token, :expired} -> :ok
    after
      0 -> :ok
    end
  end

  defp custody(owner, token, supervisor, cleanup_ms, work) do
    Process.flag(:trap_exit, true)
    owner_ref = Process.monitor(owner)
    custodian = self()

    {starter, starter_ref} =
      spawn_monitor(fn ->
        Process.link(custodian)
        start(supervisor, custodian, token, work)
      end)

    loop(%{
      owner: owner,
      owner_ref: owner_ref,
      token: token,
      starter: starter,
      starter_ref: starter_ref,
      starter_down: false,
      settled: false,
      worker: nil,
      worker_ref: nil,
      worker_down: false,
      attached: false,
      started: false,
      returned: nil,
      cleanup_ms: cleanup_ms,
      closing: nil
    })
  end

  defp start(supervisor, custodian, token, work) do
    try do
      task =
        Task.Supervisor.async_nolink(
          supervisor,
          fn -> invoke(custodian, token, work) end,
          shutdown: :brutal_kill
        )

      send(custodian, {token, :started, task.pid})

      returned =
        case Task.yield(task, :infinity) do
          {:ok, value} -> value
          _ -> failure(:codec_unavailable)
        end

      send(custodian, {token, :returned, returned})
    rescue
      RuntimeError -> send(custodian, {token, :refused, :overloaded})
      _ -> send(custodian, {token, :refused, :codec_unavailable})
    catch
      _, _ -> send(custodian, {token, :refused, :codec_unavailable})
    end
  end

  defp invoke(custodian, token, work) do
    try do
      Process.link(custodian)
      monitor = Process.monitor(custodian)
      send(custodian, {token, :attach, self()})

      receive do
        {^token, :go} ->
          Process.demonitor(monitor, [:flush])
          work.()

        {:DOWN, ^monitor, :process, ^custodian, _} ->
          failure(:codec_unavailable)
      end
    rescue
      _ -> failure(:codec_unavailable)
    catch
      _, _ -> failure(:codec_unavailable)
    end
  end

  defp loop(state) do
    if complete?(state), do: exit({:shutdown, {state.token, outcome(state)}})
    token = state.token

    receive do
      {^token, :started, worker} -> loop(worker(state, worker, :started))
      {^token, :attach, worker} -> loop(worker(state, worker, :attached))
      {^token, :returned, returned} -> loop(%{state | returned: {:ok, returned}})
      {^token, :refused, code} -> loop(%{state | settled: true, returned: failure(code)})
      {^token, :cancel, reason} -> loop(close(state, reason))
      {^token, :cleanup_expired} -> abandon(state)
      {:DOWN, ref, :process, _, _} -> loop(down(state, ref))
      _ -> loop(state)
    end
  end

  defp worker(%{worker: known} = state, worker, _) when known != nil and known != worker,
    do: close(state, :protocol_fault)

  defp worker(state, worker, stage) do
    state =
      if state.worker == nil,
        do: %{state | worker: worker, worker_ref: Process.monitor(worker), settled: true},
        else: state

    state = Map.put(state, stage, true)

    cond do
      state.closing != nil ->
        Process.exit(worker, :kill)
        state

      not Process.alive?(state.owner) ->
        close(state, :owner_lost)

      state.started and state.attached ->
        send(worker, {state.token, :go})
        state

      true ->
        state
    end
  end

  defp down(%{owner_ref: ref} = state, ref), do: close(state, :owner_lost)
  defp down(%{worker_ref: ref} = state, ref), do: %{state | worker_down: true}

  defp down(%{starter_ref: ref} = state, ref) do
    state = %{state | starter_down: true}
    if state.returned == nil, do: close(state, :codec_unavailable), else: state
  end

  defp down(state, _), do: state

  defp close(%{closing: reason} = state, _) when reason != nil, do: state

  defp close(state, reason) do
    if state.worker != nil, do: Process.exit(state.worker, :kill)
    Process.send_after(self(), {state.token, :cleanup_expired}, state.cleanup_ms)
    %{state | closing: reason}
  end

  defp complete?(state) do
    state.settled and state.starter_down and (state.worker == nil or state.worker_down) and
      (state.closing != nil or state.returned != nil)
  end

  defp outcome(%{closing: nil, returned: returned}), do: returned
  defp outcome(state), do: failure(state.closing)

  defp abandon(state) do
    Process.exit(state.starter, :kill)
    if state.worker != nil, do: Process.exit(state.worker, :kill)
    exit({:shutdown, {state.token, failure(:cleanup_unconfirmed)}})
  end

  defp failure(code), do: {:error, Error.new(code, :decode, %{})}
end
