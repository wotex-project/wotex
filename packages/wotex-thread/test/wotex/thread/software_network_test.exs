defmodule Wotex.Thread.SoftwareNetworkTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Thread.SoftwareNetwork

  test "peer cleanup preserves a replacement socket at the same path" do
    root =
      Path.join(
        System.tmp_dir!(),
        "wth-socket-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "daemon.sock")
    {:ok, original} = :gen_tcp.listen(0, [:binary, active: false, ifaddr: {:local, path}])
    stat = File.lstat!(path)
    File.rm!(path)
    {:ok, replacement} = :gen_tcp.listen(0, [:binary, active: false, ifaddr: {:local, path}])

    on_exit(fn ->
      :gen_tcp.close(original)
      :gen_tcp.close(replacement)
    end)

    process =
      Map.merge(completed_process(), %{
        socket: path,
        socket_identity: {stat.major_device, stat.inode}
      })

    assert {:error, :daemon_socket_changed} = SoftwareNetwork.stop_process(process)
    assert File.exists?(path)
    assert {:ok, _} = :inet.sockname(replacement)
  end

  defp completed_process do
    port =
      Port.open({:spawn_executable, ~c"/bin/sh"}, [
        :binary,
        :exit_status,
        args: [~c"-c", ~c"printf ready; read -r finish"]
      ])

    assert_receive {^port, {:data, "ready"}}, 1_000
    {:os_pid, pid} = Port.info(port, :os_pid)
    Port.command(port, "finish\n")
    assert_receive {^port, {:exit_status, 0}}, 1_000
    %{port: port, os_pid: pid, executable: "/bin/sh", pids: [pid]}
  end
end
