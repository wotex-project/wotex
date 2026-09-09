defmodule Wotex.BACnet.Test.CStackPeer do
  @moduledoc false

  import ExUnit.Assertions
  alias Wotex.BACnet
  alias Wotex.BACnet.IPv4

  @doc false
  @spec control(String.t()) :: map()
  def control(command \\ "stats") do
    port = System.fetch_env!("WOTEX_BACNET_CONTROL_PORT") |> String.to_integer()
    nonce = rem(System.unique_integer([:positive]), 4_294_967_296)
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])

    try do
      assert :ok = :gen_udp.send(socket, {127, 0, 0, 1}, port, "#{command} #{nonce}\n")
      assert {:ok, {{127, 0, 0, 1}, ^port, data}} = :gen_udp.recv(socket, 0, 1000)
      assert byte_size(data) <= 2048
      assert %{"version" => 1, "nonce" => ^nonce, "pid" => pid} = decoded = Jason.decode!(data)
      assert is_integer(pid) and pid > 0
      decoded
    after
      :gen_udp.close(socket)
    end
  end

  @doc false
  @spec await((map() -> boolean()), pos_integer()) :: map()
  def await(predicate, timeout \\ 1000) do
    await_until(predicate, System.monotonic_time(:millisecond) + timeout)
  end

  defp await_until(predicate, deadline) do
    snapshot = control()

    cond do
      predicate.(snapshot) ->
        snapshot

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("C peer state: #{inspect(snapshot)}")

      true ->
        Process.sleep(5)
        await_until(predicate, deadline)
    end
  end

  @doc false
  @spec connect(keyword()) :: BACnet.Session.t()
  def connect(options \\ []) do
    assert {:ok, session} = BACnet.connect(options(options))
    session
  end

  @doc false
  @spec options(keyword()) :: keyword()
  def options(options \\ []) do
    port = System.fetch_env!("WOTEX_BACNET_INTEROP_PORT") |> String.to_integer()
    destination = {{127, 0, 0, 1}, port}
    {:ok, reservation} = :gen_udp.open(0, [:binary, active: false])
    {:ok, {_, local_port}} = :inet.sockname(reservation)
    :gen_udp.close(reservation)

    defaults = [
      client: IPv4,
      local_ip: :none,
      local_port: local_port,
      destination: destination,
      timeout: 1000,
      discovery: %{destination: destination, timeout_ms: 100, max_devices: 16}
    ]

    Keyword.merge(defaults, options)
  end

  @doc false
  @spec resources(BACnet.Session.t()) :: %{processes: [pid()], socket: port()}
  def resources(session) do
    state = :sys.get_state(session.handle.owner)

    %{
      processes: [
        session.handle.owner,
        session.handle.stack.owner,
        state.client,
        state.transport,
        state.segmentator,
        state.segments_store
      ],
      socket: elem(state.portal, 0)
    }
  end

  @doc false
  @spec close(BACnet.Session.t(), map()) :: true
  def close(session, resources) do
    monitors = Enum.map(resources.processes, &Process.monitor/1)
    assert :ok = BACnet.disconnect(session)
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 1100)
    assert :erlang.port_info(resources.socket) == :undefined
  end
end
