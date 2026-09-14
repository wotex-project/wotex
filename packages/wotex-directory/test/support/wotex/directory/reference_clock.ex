defmodule Wotex.Directory.ReferenceClock do
  @moduledoc false

  @behaviour Wotex.Directory.Clock

  @impl true
  def now(%{observer: observer, result: result}) do
    send(observer, {:reference_port, :now, self(), []})
    result
  end
end
