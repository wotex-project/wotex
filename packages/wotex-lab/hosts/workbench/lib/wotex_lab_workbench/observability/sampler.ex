defmodule WotexLabWorkbench.Observability.Sampler do
  @moduledoc """
  Explicit, single-writer PromEx-to-ETS history sampling for the local operator.

  One capture is in flight at a time. The next periodic tick is scheduled
  after completion, with no queued catch-up samples. Defaults to five seconds
  (admitted interval 1–60 seconds). No database sink, listener, browser scope
  or model call is inferred. Failed attempts consume sequence numbers so a
  later successful history row exposes the gap (or a collector restart's reset);
  failure is never a zero. Operator calls are serialized; callers must bound
  their own concurrency. This API is not exposed to telemetry or HTTP callers.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{History, Snapshot}
  alias WotexLabWorkbench.Observability.Capture

  @doc "Starts the fixed host sampler with a supplied history and optional interval."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:history, :interval_ms]) do
      history = Keyword.get(opts, :history)
      interval = Keyword.get(opts, :interval_ms, 5_000)

      if (is_pid(history) or (is_atom(history) and history not in [nil, true, false])) and
           is_integer(interval) and interval in 1_000..60_000 do
        GenServer.start_link(__MODULE__, {history, interval}, name: __MODULE__)
      else
        {:error, Error.new(:invalid_sampler, :metrics, "history or sampling interval is invalid")}
      end
    end
  end

  @doc "One serialized operator-requested sample; never called from a telemetry handler."
  @spec sample_now(GenServer.server()) :: {:ok, map()} | {:error, Error.t()}
  def sample_now(server \\ __MODULE__), do: GenServer.call(server, :sample, 10_000)

  @doc "Attempt, storage and failure counts, interval and the last static error code."
  @spec stats(GenServer.server()) :: map()
  def stats(server \\ __MODULE__), do: GenServer.call(server, :stats, 10_000)

  @impl GenServer
  def init({history, interval}) do
    {:ok,
     schedule(%{
       history: history,
       interval_ms: interval,
       previous: nil,
       sequence: 0,
       stored: 0,
       failures: 0,
       last_error: nil,
       timer: nil
     })}
  end

  @impl GenServer
  def handle_call(:sample, _from, state) do
    {result, state} = sample(state)
    {:reply, result, state}
  end

  def handle_call(:stats, _from, state),
    do: {:reply, Map.take(state, [:interval_ms, :sequence, :stored, :failures, :last_error]), state}

  @impl GenServer
  def handle_info({:sample, token}, %{timer: {_timer, token}} = state) do
    {_result, state} = sample(state)
    {:noreply, schedule(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule(state) do
    token = make_ref()
    timer = Process.send_after(self(), {:sample, token}, state.interval_ms)
    %{state | timer: {timer, token}}
  end

  defp sample(state) do
    sequence = state.sequence + 1

    case capture_and_put(state.history, state.previous, sequence) do
      {:ok, snapshot, admission} ->
        {{:ok, admission},
         %{
           state
           | sequence: sequence,
             previous: snapshot,
             stored: state.stored + 1,
             last_error: nil
         }}

      {:error, error} ->
        {{:error, error},
         %{state | sequence: sequence, failures: state.failures + 1, last_error: error.code}}
    end
  end

  defp capture_and_put(history, previous, sequence) do
    with {:ok, snapshot} <- Capture.sample(),
         snapshot = %{snapshot | sequence: sequence},
         {:ok, reading} <- stale(snapshot, previous),
         {:ok, admission} <- History.put(history, reading) do
      {:ok, snapshot, admission}
    end
  catch
    :exit, _reason -> {:error, Error.new(:history_unavailable, :metrics, "history unavailable")}
  end

  defp stale(snapshot, nil), do: {:ok, snapshot}

  defp stale(snapshot, previous) do
    snapshot
    |> Map.from_struct()
    |> Map.put(:series, snapshot.series ++ Snapshot.stale_markers(previous, snapshot))
    |> Snapshot.new()
  end
end
