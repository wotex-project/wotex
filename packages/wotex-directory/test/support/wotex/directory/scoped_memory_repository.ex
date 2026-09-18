defmodule Wotex.Directory.ScopedMemoryRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  alias Wotex.Directory.MemoryRepository

  @impl Wotex.Directory.Repository
  def fetch(state, identifier, context),
    do: MemoryRepository.fetch(Map.fetch!(state, context), identifier, context)

  @impl Wotex.Directory.Repository
  def insert(state, entry, context),
    do: MemoryRepository.insert(Map.fetch!(state, context), entry, context)

  @impl Wotex.Directory.Repository
  def replace(state, entry, expected_version, context),
    do: MemoryRepository.replace(Map.fetch!(state, context), entry, expected_version, context)

  @impl Wotex.Directory.Repository
  def delete(state, identifier, expected_version, context),
    do: MemoryRepository.delete(Map.fetch!(state, context), identifier, expected_version, context)

  @impl Wotex.Directory.Repository
  def list(state, query, cursor, active_at, context),
    do: MemoryRepository.list(Map.fetch!(state, context), query, cursor, active_at, context)

  @impl Wotex.Directory.Repository
  def expire_due(state, cutoff, limit, strategy, context),
    do: MemoryRepository.expire_due(Map.fetch!(state, context), cutoff, limit, strategy, context)
end
