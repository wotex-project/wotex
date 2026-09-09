defmodule Wotex.CoAP.Lifetime do
  @moduledoc false

  @doc false
  @spec start([pid()], non_neg_integer()) :: pid()
  def start(owners, grace) do
    parent = self()
    spawn_link(fn -> monitor(parent, owners, grace) end)
  end

  defp monitor(parent, owners, grace) do
    Process.flag(:trap_exit, true)
    parent_monitor = Process.monitor(parent)
    monitors = Map.new(owners, &{Process.monitor(&1), true})

    receive do
      {:DOWN, ^parent_monitor, :process, _, _} ->
        :ok

      {:EXIT, ^parent, _} ->
        :ok

      {:DOWN, monitor, :process, _, _} when is_map_key(monitors, monitor) ->
        finish(parent, parent_monitor, grace)
    end
  end

  defp finish(parent, parent_monitor, grace) do
    receive do
      {:DOWN, ^parent_monitor, :process, _, _} -> :ok
      {:EXIT, ^parent, _} -> :ok
    after
      grace -> Process.exit(parent, :kill)
    end
  end
end
