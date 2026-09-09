defmodule Wotex.Lab.Adapters.Runtime.Loopback.Session do
  @moduledoc """
  A linked helper that ties a loopback subscription to the life of its host.

  Real transports link a connection process to the runtime subscription so a
  dead connection surfaces as an exit. The loopback session plays that role: it
  monitors the simulated Thing host and exits with `{:shutdown, :host_down}`
  when the host dies, which the owning subscription reports as
  `:transport_down`. Closing exits normally.

  `start/1` links the helper to its caller and monitors the supplied host PID;
  `close/1` sends the finite shutdown signal. The module carries no payload,
  reconnection policy, credential, or registry name, so lifetime remains visible
  in the consumer's supervision topology.
  """

  @doc "Starts a session linked to the calling subscription process."
  @spec start(pid()) :: pid()
  def start(host) when is_pid(host) do
    spawn_link(fn ->
      monitor = Process.monitor(host)

      receive do
        {:DOWN, ^monitor, :process, ^host, _reason} -> exit({:shutdown, :host_down})
        :close -> :ok
      end
    end)
  end

  @doc "Closes the session; the linked exit is `:normal`."
  @spec close(pid()) :: :ok
  def close(session) when is_pid(session) do
    send(session, :close)
    :ok
  end
end
