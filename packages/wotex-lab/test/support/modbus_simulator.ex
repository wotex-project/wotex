defmodule Wotex.Lab.Test.ModbusSimulator do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 2]

  alias Testcontainers.{Container, LogWaitStrategy, PullPolicy}
  alias Wotex.Lab.Test.ChildEnvironment

  @server __MODULE__
  @source Path.expand("../containers/modbus-simulator", __DIR__)

  @spec prepare() :: String.t()
  def prepare do
    previous_pool = Application.fetch_env(:hackney, :use_default_pool)
    # Docker's Unix socket needs Hackney's direct connection path. Each request
    # owns its connection; no pooled hostname lookup interprets the socket path.
    Application.put_env(:hackney, :use_default_pool, false)

    ExUnit.Callbacks.on_exit(fn ->
      case previous_pool do
        {:ok, value} -> Application.put_env(:hackney, :use_default_pool, value)
        :error -> Application.delete_env(:hackney, :use_default_pool)
      end
    end)

    {:ok, _} = Application.ensure_all_started(:testcontainers)

    owner =
      ExUnit.Callbacks.start_supervised!(
        Supervisor.child_spec({Testcontainers, name: @server}, restart: :temporary)
      )

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(owner), do: GenServer.stop(owner, :normal, 10_000)
    end)

    digest =
      ~w(Dockerfile requirements.txt server.py)
      |> Enum.map(&File.read!(Path.join(@source, &1)))
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    image = "wotex-lab-modbus-simulator:" <> String.slice(digest, 0, 16)

    {log, status} =
      System.cmd("docker", ["build", "--quiet", "--tag", image, @source],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    assert status == 0, log
    image
  end

  @spec start(String.t()) :: map()
  def start(image) do
    model = %{
      "coils" => List.duplicate(false, 16),
      "discrete_inputs" => [true | List.duplicate(false, 15)],
      "holding_registers" => [0x41A8, 0 | List.duplicate(0, 14)],
      "input_registers" => [0x41AC, 0, 0x43D2, 0 | List.duplicate(0, 12)]
    }

    definition =
      image
      |> Container.new()
      |> Container.with_pull_policy(PullPolicy.never_pull())
      |> Container.with_exposed_port(5020)
      |> Container.with_copy_to("/lab/model.json", JSON.encode!(model))
      |> Container.with_label("wotex.lab.peer", "modbus-zone-controller")
      |> Container.with_waiting_strategy(LogWaitStrategy.new(~r/WOTEX_LAB_MODBUS_READY/, 10_000))

    {:ok, container} = Testcontainers.start_container(definition, @server)
    live = :atomics.new(1, [])
    :atomics.put(live, 1, 1)

    peer = %{
      container: container,
      live: live,
      port: Testcontainers.get_port(container, 5020, @server)
    }

    ExUnit.Callbacks.on_exit(fn -> stop(peer) end)

    host = Testcontainers.get_host(container, @server)
    address = if host == "localhost", do: ~c"127.0.0.1", else: String.to_charlist(host)
    {:ok, ip} = :inet.parse_address(address)
    Map.put(peer, :host, ip)
  end

  @spec stop(map()) :: :ok
  def stop(peer) do
    if :atomics.compare_exchange(peer.live, 1, 1, 0) == :ok do
      :ok = Testcontainers.stop_container(peer.container.container_id, @server)
    end

    :ok
  end

  @spec connect(map()) :: Wotex.Modbus.Session.t()
  def connect(peer) do
    {:ok, session} =
      Wotex.Modbus.connect(host: peer.host, port: peer.port, unit_id: 1, timeout: 1_000)

    ExUnit.Callbacks.on_exit(fn -> Wotex.Modbus.disconnect(session) end)
    session
  end

  @spec consumed(map()) :: Wotex.Runtime.ConsumedThing.t()
  def consumed(peer) do
    base = "modbus+tcp://#{:inet.ntoa(peer.host)}:#{peer.port}/1/"

    float = fn entity, operation, address ->
      %{
        "href" => base <> "#{address}?quantity=2",
        "op" => operation,
        "modv:entity" => entity,
        "modv:type" => "xsd:float"
      }
    end

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:wotex:lab:simulator:zone-controller",
        "title" => "Simulated zone controller",
        "security" => ["none"],
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "properties" => %{
          "temperature" => %{
            "type" => "number",
            "unit" => "Cel",
            "readOnly" => true,
            "forms" => [float.("InputRegister", ["readproperty"], 1)]
          },
          "power" => %{
            "type" => "number",
            "unit" => "W",
            "readOnly" => true,
            "forms" => [float.("InputRegister", ["readproperty"], 3)]
          },
          "target" => %{
            "type" => "number",
            "unit" => "Cel",
            "minimum" => 5,
            "maximum" => 35,
            "forms" => [float.("HoldingRegister", ["readproperty", "writeproperty"], 1)]
          }
        },
        "actions" => %{
          "setTarget" => %{
            "input" => %{"type" => "number", "unit" => "Cel", "minimum" => 5, "maximum" => 35},
            "forms" => [
              float.("HoldingRegister", ["invokeaction"], 1)
              |> Map.put("modv:function", "writeMultipleHoldingRegisters")
            ]
          }
        }
      })

    {:ok, consumed} =
      Wotex.Runtime.ConsumedThing.new(td,
        profiles: [Wotex.Modbus.profile()],
        transports: %{modbus: {Wotex.Modbus.Transport, [timeout: 1_000]}},
        credentials: {Wotex.Lab.Adapters.Runtime.NoSec, nil}
      )

    consumed
  end
end
