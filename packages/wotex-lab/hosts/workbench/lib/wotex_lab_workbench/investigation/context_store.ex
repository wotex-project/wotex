defmodule WotexLabWorkbench.Investigation.ContextStore do
  @moduledoc """
  Holds the bounded, server-admitted run context for the single active
  investigation. Model text cannot write or select this state.
  """

  use GenServer

  @max_bytes 8 * 1_024
  @tool_output_bytes 16 * 1_024

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Admits JSON-safe current/baseline summaries for one investigation."
  @spec put(term(), term()) :: :ok | {:error, :context_too_large | :invalid_context}
  def put(current, baseline), do: GenServer.call(__MODULE__, {:put, current, baseline})

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

  @doc "Forgets all run context."
  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl GenServer
  def init(_opts), do: {:ok, empty()}

  @impl GenServer
  def handle_call({:put, current, baseline}, _from, _state) do
    case admit(current, baseline) do
      {:ok, admitted} -> {:reply, :ok, admitted}
      {:error, reason} -> {:reply, {:error, reason}, empty()}
    end
  end

  def handle_call({:get, which}, _from, state) do
    result =
      case which do
        "current" -> one(state.current, state.current_digest)
        "baseline" -> one(state.baseline, state.baseline_digest)
        _other -> %{available: false, reason: "unknown_run_selector"}
      end

    {:reply, result, state}
  end

  def handle_call(:compare, _from, state) do
    result = %{
      available: state.current != nil and state.baseline != nil,
      current: one(state.current, state.current_digest),
      baseline: one(state.baseline, state.baseline_digest)
    }

    {:reply, result, state}
  end

  def handle_call(:metadata, _from, state) do
    result = %{
      current: metadata(state.current, state.current_digest),
      baseline: metadata(state.baseline, state.baseline_digest),
      callback_bytes_remaining: state.callback_bytes_remaining
    }

    {:reply, result, state}
  end

  def handle_call(:usage, _from, state) do
    {:reply, Map.take(state, [:context_bytes, :tool_calls]), state}
  end

  def handle_call({:charge, value}, _from, state) do
    state = %{state | tool_calls: state.tool_calls + 1}

    with {:ok, encoded} <- Jason.encode(value),
         bytes = byte_size(encoded),
         true <- bytes <= 8 * 1_024 and bytes <= state.callback_bytes_remaining do
      {:reply, value, %{state | callback_bytes_remaining: state.callback_bytes_remaining - bytes}}
    else
      _denied ->
        {:reply, %{available: false, error: "callback_output_budget_exhausted"}, state}
    end
  end

  def handle_call(:clear, _from, _state), do: {:reply, :ok, empty()}

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
         callback_bytes_remaining: @tool_output_bytes
       }}
    else
      false -> {:error, :context_too_large}
      _invalid -> {:error, :invalid_context}
    end
  end

  defp canonical(nil), do: {:ok, nil, "null"}

  defp canonical(value) when is_map(value) do
    with {:ok, json} <- Jason.encode(value),
         {:ok, plain} <- Jason.decode(json) do
      {:ok, plain, json}
    end
  end

  defp canonical(_value), do: {:error, :invalid_context}

  defp one(nil, _digest), do: %{available: false, reason: "run_context_not_supplied"}
  defp one(value, digest), do: %{available: true, digest: digest, summary: value}

  defp digest(json),
    do: "sha256:" <> (:crypto.hash(:sha256, json) |> Base.encode16(case: :lower))

  defp metadata(nil, _digest), do: %{available: false}
  defp metadata(_value, digest), do: %{available: true, digest: digest}

  defp context_bytes(nil, _json), do: 0
  defp context_bytes(_value, json), do: byte_size(json)

  defp empty do
    %{
      current: nil,
      baseline: nil,
      current_digest: nil,
      baseline_digest: nil,
      context_bytes: 0,
      tool_calls: 0,
      callback_bytes_remaining: @tool_output_bytes
    }
  end
end
