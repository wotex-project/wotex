defmodule WotexLabWorkbench.Test.ModbusRoom do
  @moduledoc false

  alias WotexLabWorkbench.Sessions

  @doc false
  @spec profile(map(), String.t()) :: map()
  def profile(peer, id \\ "zone") do
    %{id: id, title: "Zone controller", host: peer.host, port: peer.port, unit_id: 1}
  end

  @doc false
  @spec configure([map()]) :: :ok
  def configure(profiles) do
    supervisor = WotexLabWorkbench.Supervisor
    {:ok, original} = :supervisor.get_childspec(supervisor, Sessions)
    {module, function, [options]} = original.start

    configured = %{
      original
      | start: {module, function, [Keyword.put(options, :room_profiles, profiles)]}
    }

    replace(supervisor, configured)
    ExUnit.Callbacks.on_exit(fn -> replace(supervisor, original) end)
    :ok
  end

  defp replace(supervisor, spec) do
    :ok = Supervisor.terminate_child(supervisor, Sessions)
    :ok = Supervisor.delete_child(supervisor, Sessions)
    {:ok, _} = Supervisor.start_child(supervisor, spec)
    :ok
  end
end
