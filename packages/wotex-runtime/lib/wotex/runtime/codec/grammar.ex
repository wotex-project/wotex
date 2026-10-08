defmodule Wotex.Runtime.Codec.Grammar do
  @moduledoc false

  alias Wotex.Runtime.Implementation.JSON
  @safe 9_007_199_254_740_991
  @doc false
  @spec flat?(term()) :: boolean()
  def flat?(value) when is_map(value) and not is_struct(value) and map_size(value) <= 16 do
    Enum.all?(value, fn {key, v} -> text?(key, 1, 128) and primitive?(v) end) and
      match?(
        {:ok, _},
        JSON.encode(value, %{bytes: 4096, depth: 1, nodes: 17, entries: 16, string: 256})
      )
  end

  def flat?(_), do: false
  defp primitive?(nil), do: true
  defp primitive?(value) when is_boolean(value), do: true
  defp primitive?(value) when is_integer(value), do: abs(value) <= @safe
  defp primitive?(value), do: text?(value, 0, 256)

  defp text?(value, min, max),
    do:
      is_binary(value) and byte_size(value) >= min and byte_size(value) <= max and
        String.valid?(value)
end
