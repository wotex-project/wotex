defmodule Wotex.Directory.ReferenceClock do
  @moduledoc false

  @behaviour Wotex.Directory.Clock

  @impl Wotex.Directory.Clock
  def now(%{observer: observer, result: result}) do
    send(observer, {:reference_port, :now, self(), []})
    result
  end
end
