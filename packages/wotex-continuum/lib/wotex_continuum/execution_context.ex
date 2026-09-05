defmodule WotexContinuum.ExecutionContext do
  @moduledoc """
  Identifies one execution location and its observed deployment mode.

  Caller-owned execution and node IDs are paired with explicit mode and
  normalized observation time. Carrying the context makes disconnected or
  replayed work explainable without reading ambient application configuration.

  It is context data, not a process handle, identity grant, or scheduler.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Mode, Validation}

  @kind "execution_context"

  @enforce_keys [:execution_id, :node_id, :mode, :observed_at]
  defstruct [:execution_id, :node_id, :mode, :observed_at, extensions: %{}]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          node_id: String.t(),
          mode: Mode.t(),
          observed_at: String.t(),
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def new(%__MODULE__{} = value), do: new(Map.from_struct(value))

  def new(data) do
    fields = [:execution_id, :node_id, :mode, :observed_at, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, execution_id} <- Validation.required(data, :execution_id),
         {:ok, execution_id} <- Validation.string(execution_id, ["execution_id"]),
         {:ok, node_id} <- Validation.required(data, :node_id),
         {:ok, node_id} <- Validation.string(node_id, ["node_id"]),
         {:ok, mode} <- Validation.required(data, :mode),
         {:ok, mode} <- Validation.nested(mode, ["mode"], Mode),
         {:ok, observed_at} <- Validation.required(data, :observed_at),
         {:ok, observed_at} <- Validation.timestamp(observed_at, ["observed_at"]),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
      {:ok,
       %__MODULE__{
         execution_id: execution_id,
         node_id: node_id,
         mode: mode,
         observed_at: observed_at,
         extensions: extensions
       }}
    end
  end

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("execution_id", value.execution_id)
    |> Map.put("node_id", value.node_id)
    |> Map.put("mode", Mode.to_map(value.mode))
    |> Map.put("observed_at", value.observed_at)
    |> Map.put("extensions", value.extensions)
  end
end
