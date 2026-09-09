defmodule Wotex.Thread.OpenThread.CommissioningValue do
  @moduledoc """
  Checks the scalar credential fields used by Thread commissioning values.

  PSKd admission accepts 6..32 ASCII uppercase letters or digits, excluding
  I, O, Q and Z as required by the pinned OpenThread profile. Optional text may
  be absent; present text must be valid UTF-8, fit the caller's byte limit and
  contain no NUL, ASCII control character or DEL. These checks do not store,
  log, authenticate or submit credentials.

  Joiner configuration and admission constructors compose these predicates
  with identity and lifetime validation. A valid PSKd is only well-formed input;
  it says nothing about a peer's credential or the outcome of commissioning.

  ## Examples

      iex> Wotex.Thread.OpenThread.CommissioningValue.pskd?("WTEST123")
      true
      iex> Wotex.Thread.OpenThread.CommissioningValue.pskd?("INVALID")
      false
  """

  @doc false
  @spec pskd?(term()) :: boolean()
  def pskd?(value) when is_binary(value) and byte_size(value) in 6..32,
    do: pskd_bytes?(value)

  def pskd?(_), do: false

  @doc false
  @spec text?(term(), pos_integer()) :: boolean()
  def text?(nil, _), do: true

  def text?(value, maximum) when is_binary(value) and byte_size(value) <= maximum,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1f\x7f]/, value)

  def text?(_, _), do: false

  defp pskd_bytes?(<<>>), do: true

  defp pskd_bytes?(<<byte, rest::binary>>)
       when byte in ?0..?9 or (byte in ?A..?Y and byte not in [?I, ?O, ?Q]),
       do: pskd_bytes?(rest)

  defp pskd_bytes?(_), do: false
end
