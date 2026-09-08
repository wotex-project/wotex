defmodule Wotex.Matter.Address do
  @moduledoc "Concrete fabric-scoped Matter interaction paths; wildcard writes are rejected."
  alias Wotex.Matter.Error
  @enforce_keys [:fabric_id, :node_id, :endpoint, :cluster, :member]
  defstruct [:fabric_id, :node_id, :endpoint, :cluster, :member]

  @type t :: %__MODULE__{
          fabric_id: pos_integer(),
          node_id: pos_integer(),
          endpoint: non_neg_integer(),
          cluster: non_neg_integer(),
          member: non_neg_integer()
        }

  @doc "Validates concrete unicast paths under the SDK identifier width/reservation profile."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{fabric_id: fabric, node_id: node, endpoint: endpoint, cluster: cluster, member: member}) do
    if integer?(fabric, 1, 0xFFFFFFFFFFFFFFFF) and integer?(node, 1, 0xFFFFFFEFFFFFFFFF) and
         integer?(endpoint, 0, 0xFFFE) and qualified?(cluster) and integer?(member, 0, 0xFFFFFFFE),
       do:
         {:ok,
          %__MODULE__{
            fabric_id: fabric,
            node_id: node,
            endpoint: endpoint,
            cluster: cluster,
            member: member
          }},
       else: {:error, Error.new(:invalid_path)}
  end

  def new(_), do: {:error, Error.new(:invalid_path)}

  @doc "Validates a concrete message; write/invoke distinguish missing input from null."
  @spec validate_message(map()) :: :ok | {:error, Error.t()}
  def validate_message(message) do
    with {:ok, _} <- new(message) do
      if message.type in [:write, :invoke] and not Map.has_key?(message, :value),
        do: {:error, Error.new(:missing_value)},
        else: :ok
    end
  end

  defp qualified?(value),
    do:
      integer?(value, 0, 0x7FFF) or
        (integer?(value, 0x00010000, 0xFFF47FFF) and rem(value, 65_536) <= 0x7FFF)

  defp integer?(value, min, max), do: is_integer(value) and value >= min and value <= max
end
