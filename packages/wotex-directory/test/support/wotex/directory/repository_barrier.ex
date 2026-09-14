defmodule Wotex.Directory.RepositoryBarrier do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  @impl true
  def fetch(state, identifier, context), do: invoke(state, :fetch, [identifier, context])

  @impl true
  def insert(state, entry, context), do: invoke(state, :insert, [entry, context])

  @impl true
  def replace(state, entry, version, context),
    do: invoke(state, :replace, [entry, version, context])

  @impl true
  def delete(state, identifier, version, context),
    do: invoke(state, :delete, [identifier, version, context])

  @impl true
  def list(state, query, cursor, active_at, context),
    do: invoke(state, :list, [query, cursor, active_at, context])

  @impl true
  def expire_due(state, cutoff, limit, strategy, context),
    do: invoke(state, :expire_due, [cutoff, limit, strategy, context])

  defp invoke(%{repository: {module, port_state}, observer: observer} = state, name, arguments) do
    send(observer, {:repository_call, self(), name, arguments})

    case checkpoint(state, name, :before, arguments) do
      :continue ->
        result = apply(module, name, [port_state | arguments])

        case checkpoint(state, name, :after, result) do
          :continue -> result
          {:return, replacement} -> replacement
        end

      {:return, replacement} ->
        replacement
    end
  end

  defp checkpoint(state, name, phase, value) do
    if {name, phase} in state.checkpoints do
      reference = make_ref()
      send(state.observer, {:repository_checkpoint, self(), reference, name, phase, value})

      receive do
        {:repository_continue, ^reference, action} -> action
      after
        5_000 -> exit(:repository_checkpoint_timeout)
      end
    else
      :continue
    end
  end
end
