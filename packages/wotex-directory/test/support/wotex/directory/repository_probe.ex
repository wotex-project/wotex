defmodule Wotex.Directory.RepositoryProbe do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  @impl Wotex.Directory.Repository
  def fetch(state, identifier, context), do: invoke(state, :fetch, [identifier, context])

  @impl Wotex.Directory.Repository
  def insert(state, entry, context), do: invoke(state, :insert, [entry, context])

  @impl Wotex.Directory.Repository
  def replace(state, entry, version, context),
    do: invoke(state, :replace, [entry, version, context])

  @impl Wotex.Directory.Repository
  def delete(state, identifier, version, context),
    do: invoke(state, :delete, [identifier, version, context])

  @impl Wotex.Directory.Repository
  def list(state, query, cursor, active_at, context),
    do: invoke(state, :list, [query, cursor, active_at, context])

  @impl Wotex.Directory.Repository
  def expire_due(state, cutoff, limit, strategy, context),
    do: invoke(state, :expire_due, [cutoff, limit, strategy, context])

  defp invoke(%{repository: {module, state}, observer: observer, faults: faults}, name, arguments) do
    send(observer, {:repository_callback, name, arguments})

    case Map.fetch(faults, name) do
      {:ok, result} -> result
      :error -> apply(module, name, [state | arguments])
    end
  end
end
