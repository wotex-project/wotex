defmodule Wotex.Directory.TestClock do
  @moduledoc false

  @behaviour Wotex.Directory.Clock

  @impl true
  def now(%DateTime{} = now), do: {:ok, now}
  def now({:error, reason}), do: {:error, reason}
end
