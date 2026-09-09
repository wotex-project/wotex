defmodule Wotex.CoAP.Lifetime do
  @moduledoc """
  Enforces owner-death cleanup when a transport process cannot handle messages.

  A transport explicitly starts this linked guardian with its owner processes
  and a cleanup grace in milliseconds. The guardian monitors its parent and
  every owner. When an owner exits, it allows the parent the supplied grace to
  terminate, then kills that exact parent if it is still alive. The guardian
  exits when its parent exits.

  Connections, datagram adapters, and Runtime relays use this internal lifecycle
  mechanism alongside their normal monitor handling. It owns no socket, retry,
  or protocol cancellation exchange. Loading the module starts no guardian;
  the caller must supply already validated process identities and grace values.
  """

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
