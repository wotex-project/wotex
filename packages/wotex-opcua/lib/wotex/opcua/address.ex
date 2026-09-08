defmodule Wotex.OPCUA.Address do
  @moduledoc "Typed OPC UA NodeId values; string identifiers retain reserved characters verbatim."
  alias Wotex.OPCUA.Error
  @enforce_keys [:namespace, :kind, :identifier]
  defstruct [:namespace, :kind, :identifier]

  @type t :: %__MODULE__{
          namespace: 0..65_535,
          kind: :numeric | :string | :guid | :opaque,
          identifier: non_neg_integer() | binary()
        }

  @doc "Validates a NodeId without creating atoms from input."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{namespace: ns, kind: kind, identifier: id}) do
    if is_integer(ns) and ns in 0..65_535 and valid_id?(kind, id),
      do: {:ok, %__MODULE__{namespace: ns, kind: kind, identifier: id}},
      else: {:error, Error.new(:invalid_node_id)}
  end

  def new({ns, id}),
    do:
      new(%__MODULE__{
        namespace: ns,
        kind: if(is_integer(id), do: :numeric, else: :string),
        identifier: id
      })

  def new(text) when is_binary(text) and byte_size(text) <= 8192 do
    case Regex.run(~r/^(?:ns=([0-9]+);)?([isgb])=(.*)$/s, text) do
      [_, namespace, kind, id] -> parse(namespace, kind, id)
      _ -> {:error, Error.new(:invalid_node_id)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_node_id)}

  @doc "Serializes a NodeId in standard text notation."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = node) do
    suffix =
      case node.kind do
        :numeric ->
          "i=#{node.identifier}"

        :string ->
          "s=" <> node.identifier

        :opaque ->
          "b=" <> Base.encode64(node.identifier)

        :guid ->
          hex = Base.encode16(node.identifier, case: :lower)

          <<a::binary-size(8), rest::binary>> = hex
          <<b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary>> = rest

          "g=#{a}-#{b}-#{c}-#{d}-#{e}"
      end

    "ns=#{node.namespace};" <> suffix
  end

  @doc "Validates operation targets and explicit write/call input."
  @spec validate_message(map()) :: :ok | {:error, Error.t()}
  def validate_message(message) do
    with {:ok, _} <- new(Map.get(message, :node_id)) do
      if message.type in [:write, :call] and not Map.has_key?(message, :value),
        do: {:error, Error.new(:missing_value)},
        else: :ok
    end
  end

  defp parse(namespace, kind, id) do
    ns = if namespace == "", do: 0, else: String.to_integer(namespace)

    parsed = parse_id(kind, id)

    case parsed do
      {kind, value} -> new(%__MODULE__{namespace: ns, kind: kind, identifier: value})
      _ -> {:error, Error.new(:invalid_node_id)}
    end
  end

  defp valid_id?(:numeric, id), do: is_integer(id) and id in 0..4_294_967_295
  defp valid_id?(:string, id), do: is_binary(id) and byte_size(id) <= 4096 and String.valid?(id)
  defp valid_id?(:guid, id), do: is_binary(id) and byte_size(id) == 16
  defp valid_id?(:opaque, id), do: is_binary(id) and byte_size(id) <= 4096
  defp valid_id?(_, _), do: false

  defp parse_id("i", id) do
    case Integer.parse(id) do
      {n, ""} -> {:numeric, n}
      _ -> :invalid
    end
  end

  defp parse_id("s", id), do: {:string, id}

  defp parse_id("b", id) do
    case Base.decode64(id) do
      {:ok, bytes} -> {:opaque, bytes}
      _ -> :invalid
    end
  end

  defp parse_id("g", id) do
    if Regex.match?(~r/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/, id) do
      {:ok, bytes} = Base.decode16(String.replace(id, "-", ""), case: :mixed)
      {:guid, bytes}
    else
      :invalid
    end
  end
end
