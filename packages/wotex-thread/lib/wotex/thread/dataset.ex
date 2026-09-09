defmodule Wotex.Thread.Dataset do
  @moduledoc """
  Preserves a bounded OpenThread Operational Dataset as ordered Type-Length-Value
  (TLV) entries.

  `decode/1` parses at most 254 bytes, rejects duplicate types and truncated
  values, and validates known field widths and network-name text. Unknown types
  and their raw values remain in order. `encode/1` emits the retained bytes only
  after revalidating the complete value. Because an Operational Dataset may
  contain network credentials, the struct's inspection representation exposes
  only its type list; `encode/1` is the explicit credential-bearing boundary.

  `complete?/2` checks the presence of the fields required for an active or
  pending dataset and the placement of pending-only fields. It does not perform
  the OpenThread Software Development Kit's full semantic validation, install a
  dataset, or assert that a network can be formed.
  """
  alias Wotex.Thread.Error
  @derive {Inspect, only: [:types]}
  @enforce_keys [:entries, :types]
  defstruct [:entries, :types]
  @type t :: %__MODULE__{entries: [{0..255, binary()}], types: [0..255]}
  @widths %{
    0 => [3],
    1 => [2],
    2 => [8],
    4 => [16],
    5 => [16],
    7 => [8],
    12 => [3, 4],
    14 => [8],
    51 => [8],
    52 => [4]
  }

  @doc "Parses at most 254 bytes; rejects duplicates and invalid known field widths."
  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) and byte_size(bytes) <= 254 do
    with {:ok, entries} <- parse(bytes, [], %{}) do
      {:ok, %__MODULE__{entries: entries, types: Enum.map(entries, &elem(&1, 0))}}
    end
  end

  def decode(_), do: {:error, Error.new(:invalid_dataset)}

  @doc "Explicitly serializes raw dataset bytes; returned data may contain credentials."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%__MODULE__{entries: entries, types: types} = dataset)
      when map_size(dataset) == 3 and is_list(entries) do
    if bounded_entries?(entries, 0) and types == Enum.map(entries, &elem(&1, 0)) do
      bytes =
        for {type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>

      with {:ok, _} <- decode(bytes), do: {:ok, bytes}
    else
      {:error, Error.new(:invalid_dataset)}
    end
  end

  def encode(_), do: {:error, Error.new(:invalid_dataset)}

  @doc "Checks required TLV presence only; authoritative semantic validity belongs to OpenThread."
  @spec complete?(term(), term()) :: boolean()
  def complete?(%__MODULE__{} = dataset, context) when context in [:active, :pending] do
    required = [0, 1, 2, 3, 5, 7, 12, 14, 53] ++ if(context == :pending, do: [51, 52], else: [])

    case encode(dataset) do
      {:ok, _bytes} ->
        Enum.all?(required, &(&1 in dataset.types)) and
          (context == :pending or (51 not in dataset.types and 52 not in dataset.types))

      {:error, _error} ->
        false
    end
  end

  def complete?(_, _), do: false

  defp parse(<<>>, acc, _), do: {:ok, Enum.reverse(acc)}

  defp parse(<<type, size, value::binary-size(size), rest::binary>>, acc, seen) do
    cond do
      Map.has_key?(seen, type) -> {:error, Error.new(:duplicate_tlv, nil, %{type: type})}
      not valid?(type, value) -> {:error, Error.new(:invalid_tlv, nil, %{type: type})}
      true -> parse(rest, [{type, value} | acc], Map.put(seen, type, true))
    end
  end

  defp parse(_, _, _), do: {:error, Error.new(:truncated_dataset)}

  defp valid?(3, name),
    do:
      byte_size(name) in 1..16 and String.valid?(name) and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, name)

  defp valid?(type, value), do: not Map.has_key?(@widths, type) or byte_size(value) in @widths[type]
  defp bounded_entries?([], size), do: size <= 254

  defp bounded_entries?([{type, value} | tail], size)
       when is_integer(type) and type in 0..255 and is_binary(value) and
              byte_size(value) <= 252 and size + byte_size(value) + 2 <= 254,
       do: bounded_entries?(tail, size + byte_size(value) + 2)

  defp bounded_entries?(_, _), do: false
end
