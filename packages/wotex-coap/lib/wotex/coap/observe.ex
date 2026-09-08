defmodule Wotex.CoAP.Observe do
  @moduledoc "Pure RFC 7641 notification freshness decisions with caller-supplied elapsed time."

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
