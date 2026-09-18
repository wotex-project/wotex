defmodule Wotex.CoAP.PeerGuardianTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP.Software.Run

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 120_000
  @support Path.expand("../support", __DIR__)

  # A child BEAM starts each peer through the same test helper the suites use
  # and is then killed with SIGKILL, so no Erlang cleanup runs. The peer's
  # guardian sees its owner pipe close and ends the peer's process group within
  # its two-second grace; afterwards no process names the peer's executable.

  setup_all do
    %{
      libcoap: System.fetch_env!("WOTEX_COAP_LIBCOAP_SERVER"),
      archive: System.fetch_env!("WOTEX_COAP_INDEPENDENT_PEER")
    }
  end

  test "WCO-N05 killing the BEAM that owns a libcoap peer leaves no peer process", c do
    assert {:ok, 0} = Run.processes_naming(c.libcoap, 0)

    owner_killed(
      "libcoap_peer.ex",
      """
      executable = System.fetch_env!("WOTEX_COAP_LIBCOAP_SERVER")
      {:ok, peer} = Wotex.CoAP.Test.LibcoapPeer.start_link({executable, :psk, "server"})
      Wotex.CoAP.Test.LibcoapPeer.endpoint(peer)
      """,
      c.libcoap
    )
  end

  test "WCO-N05 killing the BEAM that owns the independent peer leaves no peer process", c do
    assert {:ok, 0} = Run.processes_naming(c.archive, 0)

    owner_killed(
      "californium_peer.ex",
      """
      java = System.fetch_env!("WOTEX_COAP_JAVA")
      archive = System.fetch_env!("WOTEX_COAP_INDEPENDENT_PEER")
      {:ok, peer} = Wotex.CoAP.Test.CaliforniumPeer.start_link({java, archive})
      Wotex.CoAP.Test.CaliforniumPeer.endpoint(peer)
      """,
      c.archive
    )
  end

  # Runs `start` in a child BEAM that loads the peer helper, prints the peer's
  # workspace once the peer listens, confirms the peer and its guardian run,
  # kills the child and requires every process naming `executable` to end
  # within the grace.
  defp owner_killed(helper, start, executable) do
    code =
      ~s|Code.require_file(#{inspect(Path.join(@support, helper))})\n| <>
        start <>
        """
        IO.puts("peer workspace " <> :sys.get_state(peer).workspace)
        Process.sleep(:infinity)
        """

    arguments =
      Mix.Project.build_path()
      |> Path.join("lib/*/ebin")
      |> Path.wildcard()
      |> Enum.flat_map(&["-pa", &1])

    child =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: arguments ++ ["-e", code]
      ])

    {:os_pid, os_pid} = Port.info(child, :os_pid)
    workspace = await_workspace(child, "", System.monotonic_time(:millisecond) + 60_000)
    on_exit(fn -> File.rm_rf!(workspace) end)

    # The guardian and the peer both name the executable in their arguments.
    assert {:ok, running} = Run.processes_naming(executable, 0)
    assert running >= 2

    {_, 0} = System.cmd("/bin/kill", ["-KILL", Integer.to_string(os_pid)], env: cleared())
    assert_receive {^child, {:exit_status, _}}, 5_000
    assert {:ok, 0} = Run.processes_naming(executable, 5_000)
  end

  defp await_workspace(child, output, deadline) do
    case Regex.run(~r/peer workspace (\S+)\n/, output) do
      [_, workspace] ->
        workspace

      nil ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {^child, {:data, bytes}} ->
            output = output <> bytes
            size = byte_size(output)

            await_workspace(
              child,
              binary_part(output, max(size - 65_536, 0), min(size, 65_536)),
              deadline
            )

          {^child, {:exit_status, status}} ->
            flunk("peer owner exited with #{status}: #{output}")
        after
          remaining -> flunk("peer owner did not report its peer: #{output}")
        end
    end
  end

  defp cleared, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)
end
