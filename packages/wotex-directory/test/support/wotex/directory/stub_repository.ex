defmodule Wotex.Directory.StubRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  @impl Wotex.Directory.Repository
  def fetch(state, _, _), do: Map.fetch!(state, :fetch)

  @impl Wotex.Directory.Repository
  def insert(state, _, _), do: Map.fetch!(state, :insert)

  @impl Wotex.Directory.Repository
  def replace(state, _, _, _), do: Map.fetch!(state, :replace)

  @impl Wotex.Directory.Repository
  def delete(state, _, _, _), do: Map.fetch!(state, :delete)

  @impl Wotex.Directory.Repository
  def list(state, _, _, _, _), do: Map.fetch!(state, :list)

  @impl Wotex.Directory.Repository
  def expire_due(state, _, _, _, _),
    do: Map.fetch!(state, :expire_due)
end
