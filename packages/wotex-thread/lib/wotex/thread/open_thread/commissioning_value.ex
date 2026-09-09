defmodule Wotex.Thread.OpenThread.CommissioningValue do
  @moduledoc false

  @doc false
  @spec pskd?(term()) :: boolean()
  def pskd?(value) when is_binary(value) and byte_size(value) in 6..32,
    do: pskd_bytes?(value)

  def pskd?(_), do: false

  @doc false
  @spec text?(term(), pos_integer()) :: boolean()
  def text?(nil, _maximum), do: true

  def text?(value, maximum) when is_binary(value) and byte_size(value) <= maximum,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1f\x7f]/, value)

  def text?(_, _), do: false

  defp pskd_bytes?(<<>>), do: true

  defp pskd_bytes?(<<byte, rest::binary>>)
       when byte in ?0..?9 or (byte in ?A..?Y and byte not in [?I, ?O, ?Q]),
       do: pskd_bytes?(rest)

  defp pskd_bytes?(_), do: false
end
