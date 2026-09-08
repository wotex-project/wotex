defmodule Wotex.Thread.DaemonDeviceTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread
  alias Wotex.Thread.Daemon
  @moduletag :hardware

  test "a real OpenThread daemon reports version and an explicit network state" do
    assert {:ok, session} =
             Thread.connect(
               client: Daemon,
               socket_path: System.fetch_env!("WOTEX_THREAD_DAEMON_SOCKET"),
               timeout: 5000
             )

    try do
      assert {:ok, version} = Thread.send(session, %{type: :version})
      assert version =~ "OPENTHREAD/"
      assert {:ok, state} = Thread.send(session, %{type: :state})
      assert state in ["disabled", "detached", "child", "router", "leader"]
    after
      Thread.disconnect(session)
    end
  end
end
