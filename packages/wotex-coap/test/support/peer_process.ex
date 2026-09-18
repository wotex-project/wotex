defmodule Wotex.CoAP.Test.PeerProcess do
  @moduledoc false

  # Starts a software peer under the native command guardian of the software
  # workspace. The guardian's stdin is this BEAM's Port pipe, the peer gets
  # /dev/null stdin and its own process group, and the guardian ends that group
  # when the pipe closes. An owner BEAM that exits, even by SIGKILL, therefore
  # leaves no peer process behind. Closing a peer signals the guardian, which
  # stops the group within its cleanup grace and exits with status 127.
  #
  # Output bound 0 hands the peer the Port pipe itself: a debug-level libcoap
  # peer logs every PDU, more than 16 MiB for a 1 MiB OSCORE body, and each
  # helper keeps only a bounded tail of it. The lifetime is the guardian's
  # ten-minute maximum.
  @lifetime_ms 600_000
  @output_bytes 0
  @cleanup_ms 2_000

  @doc "The guardian's exit status after it stopped the peer on its owner's signal."
  @spec stopped_status() :: 127
  def stopped_status, do: 127

  @spec open(Path.t(), [String.t()], Path.t()) :: {port(), pos_integer()}
  def open(executable, arguments, directory) do
    guardian = System.fetch_env!("WOTEX_COAP_PEER_GUARDIAN")

    port =
      Port.open({:spawn_executable, guardian}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args:
          [
            Integer.to_string(@lifetime_ms),
            Integer.to_string(@output_bytes),
            Integer.to_string(@cleanup_ms),
            directory,
            executable
          ] ++ arguments,
        env: Enum.map(System.get_env(), fn {name, _} -> {String.to_charlist(name), false} end)
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {port, os_pid}
  end
end
