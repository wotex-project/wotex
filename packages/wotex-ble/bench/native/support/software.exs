defmodule Wotex.BLE.Bench.Software do
  @moduledoc false

  # The software lane's environment for the SDK-path benchmarks, as
  # test/support/software_peer.ex reads it for the interoperability tests: the
  # GATT peer's configuration and control socket (WOTEX_BLE_SOFTWARE_CONFIG,
  # written by test/interop/virtual/public_peer.py once the private D-Bus bus,
  # bluetoothd and the two virtual controllers are up), and the native host and
  # runtime guardian of the native build (WOTEX_BLE_NATIVE_WORKSPACE, the
  # benchmark's --workspace). The service and characteristics are the peer's.

  alias Wotex.BLE.{Address, BlueZ, Peer}

  @service "9bf00000-4689-4b5b-bdea-8d9f7c1b6000"
  @uuids %{
    value: "9bf00001-4689-4b5b-bdea-8d9f7c1b6000",
    notify: "9bf00002-4689-4b5b-bdea-8d9f7c1b6000",
    indicate: "9bf00003-4689-4b5b-bdea-8d9f7c1b6000"
  }

  @doc false
  @spec control_socket!() :: charlist()
  def control_socket! do
    path = System.get_env("WOTEX_BLE_SOFTWARE_CONFIG")

    unless is_binary(path) and Path.type(path) == :absolute and File.regular?(path) do
      raise "WOTEX_BLE_SOFTWARE_CONFIG must name the GATT peer's configuration: run this " <>
              "benchmark on a Linux host with the software lane's private bus, bluetoothd, " <>
              "virtual controllers and GATT peer (test/interop/virtual)"
    end

    %{"control_socket" => socket} = Jason.decode!(File.read!(path))
    String.to_charlist(socket)
  end

  @doc false
  @spec command(charlist(), String.t(), map()) :: map()
  def command(socket, operation, parameters \\ %{}) do
    options = [:binary, packet: :line, packet_size: 16_384, active: false]
    {:ok, connection} = :gen_tcp.connect({:local, socket}, 0, options, 1000)

    try do
      request = Jason.encode!(%{operation: operation, parameters: parameters}) <> "\n"
      :ok = :gen_tcp.send(connection, request)
      {:ok, response} = :gen_tcp.recv(connection, 0, 25_000)
      %{"ok" => value} = Jason.decode!(response)
      value
    after
      :gen_tcp.close(connection)
    end
  end

  @doc false
  @spec options(map()) :: keyword()
  def options(%{"peer" => peer, "bus_address" => bus_address}) do
    {:ok, peer} =
      Peer.new(%{
        adapter: peer["adapter"],
        address: peer["address"],
        address_type: address_type(peer["address_type"])
      })

    [
      client: BlueZ,
      lifecycle: :persistent,
      peer: peer,
      connection: :borrowed,
      bus_address: bus_address,
      timeout: 5000
    ] ++ native()
  end

  @doc false
  @spec target(map(), atom()) :: Address.t()
  def target(page, label) do
    uuid = Map.fetch!(@uuids, label)

    [characteristic] =
      Enum.filter(
        page.characteristics,
        &(&1.service_uuid == @service and &1.characteristic_uuid == uuid)
      )

    {:ok, address} =
      Address.new(%{
        service: characteristic.service_uuid,
        characteristic: characteristic.characteristic_uuid,
        object_path: characteristic.object_path,
        handle: characteristic.handle,
        generation: characteristic.generation
      })

    address
  end

  @doc false
  @spec formatters() :: [module() | {module(), keyword()}]
  def formatters do
    [
      Benchee.Formatters.Console,
      {Benchee.Formatters.Markdown,
       file: System.fetch_env!("WOTEX_BENCH_OUTPUT"),
       title: "# " <> System.fetch_env!("WOTEX_BENCH_TITLE"),
       description: System.fetch_env!("WOTEX_BENCH_DESCRIPTION")}
    ]
  end

  # The native host and runtime guardian the native build recorded.
  defp native do
    workspace = System.fetch_env!("WOTEX_BLE_NATIVE_WORKSPACE")
    manifest = Jason.decode!(File.read!(Path.join(workspace, "native-manifest.json")))
    %{"schema" => "wotex.native-build", "package" => "wotex_ble"} = manifest
    binaries = Map.new(manifest["binaries"], &{&1["purpose"], &1})
    %{"sdk_host" => host, "runtime_guardian" => guardian} = binaries

    [
      executable: Path.join(workspace, host["path"]),
      executable_sha256: host["sha256"],
      guardian: Path.join(workspace, guardian["path"]),
      guardian_sha256: guardian["sha256"]
    ]
  end

  defp address_type("public"), do: :public
  defp address_type("random"), do: :random
end
