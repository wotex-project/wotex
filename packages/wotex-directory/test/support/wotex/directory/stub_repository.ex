defmodule Wotex.Directory.StubRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  @impl Wotex.Directory.Repository
  def fetch(state, _identifier, _context), do: Map.fetch!(state, :fetch)

  @impl Wotex.Directory.Repository
  def insert(state, _entry, _context), do: Map.fetch!(state, :insert)

  @impl Wotex.Directory.Repository
  def replace(state, _entry, _expected_version, _context), do: Map.fetch!(state, :replace)

  @impl Wotex.Directory.Repository
  def delete(state, _identifier, _expected_version, _context), do: Map.fetch!(state, :delete)

  @impl Wotex.Directory.Repository
  def list(state, _query, _cursor, _active_at, _context), do: Map.fetch!(state, :list)

  @impl Wotex.Directory.Repository
  def expire_due(state, _cutoff, _limit, _strategy, _context),
    do: Map.fetch!(state, :expire_due)
end
