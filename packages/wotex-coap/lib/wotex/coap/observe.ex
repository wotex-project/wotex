defmodule Wotex.CoAP.Observe do
  @moduledoc """
  Evaluates RFC 7641 Observe sequence freshness without reading a clock.

  `fresh?/3` compares a previous 24-bit sequence value with a candidate and
  uses caller-supplied elapsed milliseconds for the RFC freshness rule. Invalid
  sequence numbers and elapsed values return `false`. The function is pure and
  can therefore be tested or replayed with an explicit time observation.

  This module implements only the sequence-arithmetic decision. It does not
  establish a network observation, schedule renewal, receive notifications, or
  own subscriber state. `Wotex.CoAP.Connection` applies the predicate within
  its owned observation lifecycle. `Wotex.CoAP.Observation.Report` validates
  notification metadata separately from the transport state.

  ## Examples

      iex> Wotex.CoAP.Observe.fresh?(10, 11, 100)
      true

      iex> Wotex.CoAP.Observe.fresh?(11, 10, 100)
      false
  """

  import Bitwise

  @doc "Tests 24-bit serial freshness, including wraparound and the 128-second escape."
  @spec fresh?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  def fresh?(previous, current, elapsed_ms)
      when previous in 0..16_777_215 and current in 0..16_777_215 and is_integer(elapsed_ms) and
             elapsed_ms >= 0,
      do:
        elapsed_ms > 128_000 or
          (current != previous and band(current - previous, 0xFFFFFF) < 0x800000)

  def fresh?(_, _, _), do: false
end
