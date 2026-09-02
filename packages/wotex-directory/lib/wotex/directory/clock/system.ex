defmodule Wotex.Directory.Clock.System do
  @moduledoc """
  Stateless UTC system-clock implementation.
  """

  @behaviour Wotex.Directory.Clock

  @impl true
  def now(_state), do: {:ok, DateTime.utc_now()}
end
