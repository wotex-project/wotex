defmodule Wotex.Directory.ReferenceIdentifier do
  @moduledoc false

  @behaviour Wotex.Directory.Identifier

  @impl true
  def generate(%{observer: observer, next: next}) do
    send(observer, {:reference_port, :generate, self(), []})
    next.()
  end
end
