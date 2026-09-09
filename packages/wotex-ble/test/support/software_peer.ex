defmodule Wotex.BLE.SoftwarePeer do
  @moduledoc false

  import ExUnit.Assertions
  alias Wotex.BLE.{Address, BlueZ, Peer}

  @service "9bf00000-4689-4b5b-bdea-8d9f7c1b6000"
  @uuids %{
    value: "9bf00001-4689-4b5b-bdea-8d9f7c1b6000",
    notify: "9bf00002-4689-4b5b-bdea-8d9f7c1b6000",
    indicate: "9bf00003-4689-4b5b-bdea-8d9f7c1b6000",
    duplicate: "9bf00004-4689-4b5b-bdea-8d9f7c1b6000"
  }

  @spec service() :: String.t()
  def service, do: @service

  @spec uuid(atom()) :: String.t()
  def uuid(label), do: Map.fetch!(@uuids, label)

  @spec configure!() :: map()
  def configure! do
    path = System.fetch_env!("WOTEX_BLE_SOFTWARE_CONFIG")
    assert Path.type(path) == :absolute
    assert File.regular?(path)
    config = Jason.decode!(File.read!(path))
    assert is_binary(config["control_socket"])
    config
  end

  @spec command(String.t(), map(), pos_integer()) :: map()
  def command(operation, parameters \\ %{}, timeout \\ 25_000) do
    socket = configure!()["control_socket"]

    assert {:ok, connection} =
             :gen_tcp.connect(
               {:local, String.to_charlist(socket)},
               0,
               [:binary, packet: :line, packet_size: 16_384, active: false],
               1000
             )

    try do
      assert :ok =
               :gen_tcp.send(
                 connection,
                 Jason.encode!(%{operation: operation, parameters: parameters}) <> "\n"
               )

      assert {:ok, response} = :gen_tcp.recv(connection, 0, timeout)
      assert %{"ok" => value} = Jason.decode!(response)
      value
    after
      :gen_tcp.close(connection)
    end
  end

  @spec options(map()) :: keyword()
  def options(config) do
    assert {:ok, peer} =
             Peer.new(%{
               adapter: config["peer"]["adapter"],
               address: config["peer"]["address"],
               address_type: peer_type(config["peer"]["address_type"])
             })

    [
      client: BlueZ,
      lifecycle: :persistent,
      peer: peer,
      connection: :borrowed,
      bus_address: config["bus_address"],
      executable: config["executable"],
      timeout: 5000
    ]
  end

  @spec target(map()) :: Address.t()
  def target(characteristic) do
    assert {:ok, address} =
             Address.new(%{
               service: characteristic.service_uuid,
               characteristic: characteristic.characteristic_uuid,
               object_path: characteristic.object_path,
               handle: characteristic.handle,
               generation: characteristic.generation
             })

    address
  end

  @spec selected(map(), atom()) :: map()
  def selected(page, label) do
    [characteristic] =
      Enum.filter(page.characteristics, fn characteristic ->
        characteristic.service_uuid == @service and
          characteristic.characteristic_uuid == uuid(label)
      end)

    characteristic
  end

  @spec wait_until((-> boolean()), pos_integer()) :: :ok
  def wait_until(predicate, timeout \\ 1000),
    do: wait_before(predicate, System.monotonic_time(:millisecond) + timeout)

  defp wait_before(predicate, deadline) do
    complete = predicate.()
    assert System.monotonic_time(:millisecond) <= deadline

    if complete do
      :ok
    else
      Process.sleep(10)
      wait_before(predicate, deadline)
    end
  end

  @spec released?() :: boolean()
  def released? do
    stats = command("stats", %{}, 1000)

    stats["native_senders"] == [] and stats["agents"] == 0 and
      stats["notification_sessions"] == 0 and stats["pending_controls"] == 0 and
      stats["notifying"] == []
  end

  defp peer_type("public"), do: :public
  defp peer_type("random"), do: :random
end
