Code.require_file("../../support/bridge_process_fixture.ex", __DIR__)

defmodule Wotex.Matter.BridgePortProcessTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Bridge.PortProcess
  alias Wotex.Matter.{BridgeProcessFixture, Error}

  test "digest admission refuses missing, nonexecutable and symlink artifacts" do
    directory = BridgeProcessFixture.directory()
    on_exit(fn -> File.rm_rf!(directory) end)
    executable = BridgeProcessFixture.create(directory)

    configuration = %{
      executable: executable,
      executable_sha256: BridgeProcessFixture.digest(executable)
    }

    assert :ok = PortProcess.verify(configuration)
    File.chmod!(executable, 0o600)
    assert {:error, %Error{code: :incompatible_backend}} = PortProcess.verify(configuration)
    File.chmod!(executable, 0o700)
    link = Path.join(directory, "link")
    File.ln_s!(executable, link)

    assert {:error, %Error{code: :incompatible_backend}} =
             PortProcess.verify(%{configuration | executable: link})

    assert {:error, %Error{code: :incompatible_backend}} =
             PortProcess.verify(%{configuration | executable: link <> "-absent"})
  end

  test "a native pipe that stops reading refuses output without suspending its owner" do
    Process.flag(:trap_exit, true)
    directory = BridgeProcessFixture.directory()
    on_exit(fn -> File.rm_rf!(directory) end)
    executable = BridgeProcessFixture.create(directory, before_ready: "while :; do :; done")
    assert {:ok, port} = PortProcess.open(%{executable: executable, arguments: [directory]})
    on_exit(fn -> PortProcess.close(port) end)
    started = System.monotonic_time(:millisecond)
    bytes = String.duplicate("x", 511) <> "\n"

    refused = Enum.find(1..2000, fn _ -> not PortProcess.send_frame(port, bytes) end)
    assert is_integer(refused)
    assert System.monotonic_time(:millisecond) - started < 1000
    assert :ok = PortProcess.close(port)
    assert Port.info(port) == nil
    assert not PortProcess.send_frame(port, bytes)
  end
end
