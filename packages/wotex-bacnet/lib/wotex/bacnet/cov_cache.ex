defmodule Wotex.BACnet.COVCache do
  @moduledoc false

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
