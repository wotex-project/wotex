defmodule Wotex.Matter.ReadPath do
  @moduledoc """
  Represents a bounded Matter attribute-read selector.

  Fabric and operational node identifiers are always concrete. Endpoint,
  cluster, and member may independently be `:any`; those wildcards are valid
  only for reads and are never accepted by `Wotex.Matter.Address`.
  """

  alias Wotex.Matter.{Address, Error}

  @enforce_keys [:fabric_id, :node_id, :endpoint, :cluster, :member]
  defstruct [:fabric_id, :node_id, :endpoint, :cluster, :member]

  @type selector :: non_neg_integer() | :any
  @type t :: %__MODULE__{
          fabric_id: pos_integer(),
          node_id: pos_integer(),
          endpoint: selector(),
          cluster: selector(),
          member: selector()
        }

  @doc "Builds a read path with explicit, read-only wildcard selectors."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = path), do: new(Map.from_struct(path))

  def new(
        %{fabric_id: fabric, node_id: node, endpoint: endpoint, cluster: cluster, member: member} =
          value
      )
      when map_size(value) == 5 do
    with true <- valid_fabric_node?(fabric, node),
         true <- endpoint == :any or valid_endpoint?(fabric, node, endpoint),
         true <- cluster == :any or valid_cluster?(fabric, node, cluster),
         true <- member == :any or valid_member?(fabric, node, member) do
      {:ok,
       %__MODULE__{
         fabric_id: fabric,
         node_id: node,
         endpoint: endpoint,
         cluster: cluster,
         member: member
       }}
    else
      _ -> {:error, Error.new(:invalid_path)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_path)}

  @doc "Returns whether a concrete address is selected by this read path."
  @spec matches?(t(), Address.t()) :: boolean()
  def matches?(%__MODULE__{} = path, %Address{} = address) do
    path.fabric_id == address.fabric_id and path.node_id == address.node_id and
      selected?(path.endpoint, address.endpoint) and selected?(path.cluster, address.cluster) and
      selected?(path.member, address.member)
  end

  @doc "Returns whether the path contains no wildcard selector."
  @spec concrete?(t()) :: boolean()
  def concrete?(%__MODULE__{} = path),
    do: path.endpoint != :any and path.cluster != :any and path.member != :any

  defp valid_fabric_node?(fabric, node) do
    match?(
      {:ok, _},
      Address.new(%{fabric_id: fabric, node_id: node, endpoint: 0, cluster: 0, member: 0})
    )
  end

  defp valid_endpoint?(fabric, node, endpoint) do
    match?(
      {:ok, _},
      Address.new(%{fabric_id: fabric, node_id: node, endpoint: endpoint, cluster: 0, member: 0})
    )
  end

  defp valid_cluster?(fabric, node, cluster) do
    match?(
      {:ok, _},
      Address.new(%{fabric_id: fabric, node_id: node, endpoint: 0, cluster: cluster, member: 0})
    )
  end

  defp valid_member?(fabric, node, member) do
    match?(
      {:ok, _},
      Address.new(%{fabric_id: fabric, node_id: node, endpoint: 0, cluster: 0, member: member})
    )
  end

  defp selected?(:any, _), do: true
  defp selected?(expected, actual), do: expected == actual
end
