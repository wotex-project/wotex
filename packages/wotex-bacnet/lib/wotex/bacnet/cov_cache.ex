defmodule Wotex.BACnet.COVCache do
  @moduledoc """
  Bounded duplicate history for confirmed COV report delivery.

  `Wotex.BACnet.COVOwner` supplies a source, invoke-ID, and report-digest key
  together with monotonic time. Expired entries are removed before lookup. A
  repeat within the window is reported without extending its expiry; adding a
  new key evicts the oldest retained entry when the 1024-entry cache is full.

  This pure helper assumes cache state produced by its own transitions. It
  suppresses duplicate delivery, while acknowledgement remains the listener's
  responsibility. It is not durable replay protection across sessions.

  ## Examples

      iex> {false, cache} = Wotex.BACnet.COVCache.touch([], :report, 100, 50)
      iex> {true, ^cache} = Wotex.BACnet.COVCache.touch(cache, :report, 120, 50)
      iex> Wotex.BACnet.COVCache.touch(cache, :report, 150, 50)
      {false, [{:report, 200}]}

  """

  @doc false
  @spec touch([{term(), integer()}], term(), integer(), 1..60_000) ::
          {boolean(), [{term(), integer()}]}
  def touch(entries, key, now, window) do
    live = Enum.reject(entries, fn {_, expires} -> expires <= now end)

    if List.keymember?(live, key, 0) do
      {true, live}
    else
      retained = if length(live) == 1024, do: tl(live), else: live
      {false, Enum.concat(retained, [{key, now + window}])}
    end
  end
end
