defmodule WotexLabWorkbench.Investigation.ContextStore do
  @moduledoc """
  Holds the bounded, server-admitted run context for the single active
  investigation. Model text cannot write or select this state.

  The store also records the evidence digests the investigation actually
  received: the admitted current and baseline summary digests, and every
  `sha256:` digest inside a callback result that fits the output budget. At
  most 64 digests are kept. A refused callback result records nothing.
  `evidence/0` lets the broker bind a finished answer to that record before
  the context is cleared.
  """

  use GenServer

  alias WotexLabWorkbench.{Board, Runs}

  @max_bytes 8 * 1_024
  @tool_output_bytes 16 * 1_024
  @max_evidence 64
  @max_metric_bytes 64 * 1_024
  @digest ~r/\Asha256:[0-9a-f]{64}\z/

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Admits JSON-safe current/baseline summaries for one investigation."
  @spec put(term(), term(), pid() | nil) :: :ok | {:error, :context_too_large | :invalid_context}
  def put(current, baseline, room \\ nil),
    do: GenServer.call(__MODULE__, {:put, current, baseline, room})

  @doc "Returns the server-bound metric source; a cleared context admits no query."
  @spec metric_source() :: :unavailable | :host | {:room, pid(), reference()}
  def metric_source, do: GenServer.call(__MODULE__, :metric_source)

  @doc "Charges a room summary and retains its bounded executed chart atomically."
  @spec charge_metric({pid(), reference()}, term(), map()) :: term()
  def charge_metric(binding, summary, history),
    do: GenServer.call(__MODULE__, {:charge_metric, binding, summary, history})

  @doc "Returns at most eight recorded metric results for the active owner."
  @spec metric_results() :: [map()]
  def metric_results, do: GenServer.call(__MODULE__, :metric_results)

  @doc "Returns one server-selected summary; the only selectors are current and baseline."
  @spec get(String.t()) :: map()
  def get(which), do: GenServer.call(__MODULE__, {:get, which})

  @doc "Returns the two summaries and their deterministic digests."
  @spec compare() :: map()
  def compare, do: GenServer.call(__MODULE__, :compare)

  @doc "Returns only availability/digests for the initial BeamLens snapshot."
  @spec metadata() :: map()
  def metadata, do: GenServer.call(__MODULE__, :metadata)

  @doc "Returns only bounded usage counters for investigation telemetry."
  @spec usage() :: %{context_bytes: non_neg_integer(), tool_calls: non_neg_integer()}
  def usage, do: GenServer.call(__MODULE__, :usage)

  @doc "Charges one JSON-safe callback result against the investigation output budget."
  @spec charge(term()) :: term()
  def charge(value), do: GenServer.call(__MODULE__, {:charge, value})

  @doc "Returns the sorted evidence digests recorded for the active investigation."
  @spec evidence() :: [String.t()]
  def evidence, do: GenServer.call(__MODULE__, :evidence)

  @doc "Forgets all run context."
  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl GenServer
  def init(_), do: {:ok, empty()}

  @impl GenServer
  def handle_call({:put, current, baseline, room}, _, _) do
    case admit(current, baseline) do
      {:ok, admitted} when is_nil(room) or is_pid(room) ->
        source = if room, do: {:room, room, make_ref()}, else: :host
        {:reply, :ok, Map.put(admitted, :metric_source, source)}

      {:ok, _} ->
        {:reply, {:error, :invalid_context}, empty()}

      {:error, reason} ->
        {:reply, {:error, reason}, empty()}
    end
  end

  def handle_call({:get, which}, _, state) do
    result =
      case which do
        "current" -> one(state.current, state.current_digest)
        "baseline" -> one(state.baseline, state.baseline_digest)
        _ -> %{available: false, reason: "unknown_run_selector"}
      end

    {:reply, result, state}
  end

  def handle_call(:compare, _, state) do
    result = %{
      available: state.current != nil and state.baseline != nil,
      current: one(state.current, state.current_digest),
      baseline: one(state.baseline, state.baseline_digest)
    }

    {:reply, result, state}
  end

  def handle_call(:metadata, _, state) do
    result = %{
      current: metadata(state.current, state.current_digest),
      baseline: metadata(state.baseline, state.baseline_digest),
      callback_bytes_remaining: state.callback_bytes_remaining
    }

    {:reply, result, state}
  end

  def handle_call(:usage, _, state) do
    {:reply, Map.take(state, [:context_bytes, :tool_calls]), state}
  end

  def handle_call({:charge, value}, _, state) do
    {reply, state} = charge(value, state)
    {:reply, reply, state}
  end

  def handle_call(:metric_source, _, state), do: {:reply, state.metric_source, state}

  def handle_call(:metric_results, _, state),
    do: {:reply, Enum.reverse(state.metric_results), state}

  def handle_call(
        {:charge_metric, {room, nonce}, summary, history},
        _,
        %{metric_source: {:room, room, nonce}} = state
      ) do
    with {:ok, _} <- Board.change(Board.empty(), {:pin, history}),
         {:ok, bytes} <- Jason.encode(Runs.plain(history)),
         true <-
           length(state.metric_results) < 8 and byte_size(bytes) <= state.metric_bytes_remaining do
      {reply, charged} = charge(summary, state)

      state =
        if reply == summary,
          do: %{
            charged
            | metric_results: [history | charged.metric_results],
              metric_bytes_remaining: charged.metric_bytes_remaining - byte_size(bytes)
          },
          else: charged

      {:reply, reply, state}
    else
      _ ->
        {reply, state} = charge(%{available: false, error: "metric_result_unavailable"}, state)
        {:reply, reply, state}
    end
  end

  def handle_call({:charge_metric, _, _, _}, _, state),
    do: {:reply, %{available: false, error: "context_unavailable"}, state}

  def handle_call(:evidence, _, state),
    do: {:reply, Enum.sort(MapSet.to_list(state.evidence)), state}

  def handle_call(:clear, _, _), do: {:reply, :ok, empty()}

  defp charge(value, state) do
    state = %{state | tool_calls: state.tool_calls + 1}

    with {:ok, encoded} <- Jason.encode(value),
         bytes = byte_size(encoded),
         true <- bytes <= 8 * 1_024 and bytes <= state.callback_bytes_remaining do
      state = %{
        state
        | callback_bytes_remaining: state.callback_bytes_remaining - bytes,
          evidence: record(state.evidence, digests(value))
      }

      {value, state}
    else
      _ ->
        {%{available: false, error: "callback_output_budget_exhausted"}, state}
    end
  end

  defp admit(current, baseline) do
    with {:ok, current, current_json} <- canonical(current),
         {:ok, baseline, baseline_json} <- canonical(baseline),
         true <- byte_size(current_json) + byte_size(baseline_json) <= @max_bytes do
      {:ok,
       %{
         current: current,
         baseline: baseline,
         current_digest: digest(current_json),
         baseline_digest: digest(baseline_json),
         context_bytes:
           context_bytes(current, current_json) + context_bytes(baseline, baseline_json),
         tool_calls: 0,
         callback_bytes_remaining: @tool_output_bytes,
         metric_source: :unavailable,
         metric_results: [],
         metric_bytes_remaining: @max_metric_bytes,
         evidence:
           record(
             MapSet.new(),
             for(
               {value, json} <- [{current, current_json}, {baseline, baseline_json}],
               value != nil,
               do: digest(json)
             )
           )
       }}
    else
      false -> {:error, :context_too_large}
      _ -> {:error, :invalid_context}
    end
  end

  defp canonical(nil), do: {:ok, nil, "null"}

  defp canonical(value) when is_map(value) do
    with {:ok, json} <- Jason.encode(value),
         {:ok, plain} <- Jason.decode(json) do
      {:ok, plain, json}
    end
  end

  defp canonical(_), do: {:error, :invalid_context}

  defp one(nil, _), do: %{available: false, reason: "run_context_not_supplied"}
  defp one(value, digest), do: %{available: true, digest: digest, summary: value}

  defp digest(json),
    do: "sha256:" <> (:crypto.hash(:sha256, json) |> Base.encode16(case: :lower))

  defp metadata(nil, _), do: %{available: false}
  defp metadata(_, digest), do: %{available: true, digest: digest}

  defp context_bytes(nil, _), do: 0
  defp context_bytes(_, json), do: byte_size(json)

  defp empty do
    %{
      current: nil,
      baseline: nil,
      current_digest: nil,
      baseline_digest: nil,
      context_bytes: 0,
      tool_calls: 0,
      callback_bytes_remaining: @tool_output_bytes,
      metric_source: :unavailable,
      metric_results: [],
      metric_bytes_remaining: @max_metric_bytes,
      evidence: MapSet.new()
    }
  end

  defp record(evidence, digests) do
    Enum.reduce(digests, evidence, fn digest, acc ->
      if MapSet.size(acc) < @max_evidence, do: MapSet.put(acc, digest), else: acc
    end)
  end

  defp digests(value) when is_map(value) and not is_struct(value),
    do: Enum.flat_map(value, fn {key, item} -> digest_entry(key, item) ++ digests(item) end)

  defp digests(value) when is_list(value), do: Enum.flat_map(value, &digests/1)
  defp digests(_), do: []

  defp digest_entry(key, item) when key in [:digest, "digest"] and is_binary(item) do
    if Regex.match?(@digest, item), do: [item], else: []
  end

  defp digest_entry(_, _), do: []
end
