defmodule Wotex.BACnet.ValueBoundary do
  @moduledoc """
  Bounds the structure and retained bytes of native BACnet values.

  Traversal admits at most eight nesting levels, 4096 counted nodes, 1024
  members per collection, and 65,536 binary bytes in aggregate. It understands
  SDK tag and Encoding wrappers and the original bytes in
  `Wotex.BACnet.CharacterString`. Unsupported terms or exhausted limits return
  `:value_limit` without retaining the submitted value.

  The traversal is a resource check, not BACnet type validation. Callers also
  use `Wotex.BACnet.Value` to validate the semantic tag and payload before a
  value crosses a request, response, or Runtime boundary.
  """

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{CharacterString, Error}

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(term) do
    case visit(term, 0, {0, 0}) do
      {:ok, _} -> :ok
      :error -> {:error, Error.new(:value_limit)}
    end
  end

  defp visit(_, depth, _) when depth > 8, do: :error
  defp visit(_, _, {nodes, _}) when nodes >= 4096, do: :error

  defp visit(%CharacterString{bytes: bytes}, depth, budget), do: visit(bytes, depth, budget)

  defp visit({:constructed, {_, value, 0}}, depth, {nodes, bytes}),
    do: visit(value, depth + 1, {nodes + 1, bytes})

  defp visit({:tagged, {_, value, _}}, depth, {nodes, bytes}),
    do: visit(value, depth, {nodes + 1, bytes})

  defp visit({tag, value}, depth, {nodes, bytes}) when is_atom(tag),
    do: visit(value, depth, {nodes + 1, bytes})

  defp visit(%Encoding{value: value}, depth, {nodes, bytes}),
    do: visit(value, depth + 1, {nodes + 1, bytes})

  defp visit(value, _, {nodes, bytes}) when is_binary(value) do
    if bytes + byte_size(value) <= 65_536,
      do: {:ok, {nodes + 1, bytes + byte_size(value)}},
      else: :error
  end

  defp visit(value, _, {nodes, bytes}) when is_atom(value) or is_number(value),
    do: {:ok, {nodes + 1, bytes}}

  defp visit(value, depth, {nodes, bytes}) when is_list(value),
    do: elements(value, depth + 1, {nodes + 1, bytes}, 0)

  defp visit(value, depth, budget) when is_tuple(value),
    do: visit(Tuple.to_list(value), depth, budget)

  defp visit(value, depth, budget) when is_map(value) and map_size(value) <= 1024,
    do: visit(Map.to_list(value), depth, budget)

  defp visit(_, _, _), do: :error

  defp elements([], _, budget, _), do: {:ok, budget}

  defp elements([head | tail], depth, budget, count) when count < 1024 do
    with {:ok, next} <- visit(head, depth, budget),
         do: elements(tail, depth, next, count + 1)
  end

  defp elements(_, _, _, _), do: :error
end
