defmodule Wotex.Matter.Bridge.Path do
  @moduledoc false

  import Bitwise

  @doc false
  @spec valid?(term(), term(), term(), term()) :: boolean()
  def valid?(endpoint, cluster, member, operation) do
    is_integer(endpoint) and endpoint in 3..65_534 and operation in [:read, :write, :invoke] and
      cluster?(cluster) and member?(member, operation)
  end

  defp cluster?(value) when is_integer(value) and value >= 0 and value <= 0xFFF4FFFE,
    do: value <= 0x7FFF or (bsr(value, 16) >= 1 and band(value, 0xFFFF) in 0xFC00..0xFFFE)

  defp cluster?(_), do: false

  defp member?(value, operation) when is_integer(value) and value >= 0 and value <= 0xFFF4FFFF do
    vendor = bsr(value, 16)
    suffix = band(value, 0xFFFF)

    if operation == :invoke,
      do: suffix <= 0xFF and vendor <= 0xFFF4,
      else: (suffix <= 0x4FFF and vendor <= 0xFFF4) or (vendor == 0 and suffix in 0xF000..0xFFFE)
  end

  defp member?(_, _), do: false
end
