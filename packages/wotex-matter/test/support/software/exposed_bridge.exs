defmodule Wotex.Matter.SoftwareExposedBridge do
  @moduledoc false

  use GenServer

  alias Wotex.Matter.Bridge.Connection
  alias Wotex.Matter.Native.ProcessCommand
  alias Wotex.Runtime.ExposedThing
  alias Wotex.ThingDescription

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  @spec call(pid(), term()) :: term()
  def call(owner, request), do: GenServer.call(owner, request, 6000)

  @spec fixture!(map(), String.t()) :: String.t()
  def fixture!(artifacts, root) do
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    value = %{
      "bridge" => artifacts.bridge_host,
      "material" => artifacts.bridge_material,
      "controller" => artifacts.host,
      "peer" => artifacts.peer,
      "paa" => artifacts.paa,
      "root" => root,
      "interface" => "eth0"
    }

    value =
      Enum.reduce(~w(bridge material controller peer), value, fn key, result ->
        Map.put(result, key <> "_sha256", digest(Map.fetch!(result, key)))
      end)

    path = Path.join(root, "fixture.json")
    File.write!(path, Jason.encode!(value))
    File.chmod!(path, 0o600)
    path
  end

  @spec prepare!(map(), String.t()) :: String.t()
  def prepare!(fixture, name) do
    root = Path.join(fixture["root"], name)
    true = digest(fixture["material"]) == fixture["material_sha256"]

    {"private bridge fixture material written\n", 0} =
      ProcessCommand.run(fixture["material"], ["material", root], stderr_to_stdout: true)

    path = Path.join(root, "configuration")

    value =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("interface", fixture["interface"])
      |> Map.put("commissioning_window_seconds", 180)

    File.write!(path, Jason.encode!(value))
    root
  end

  @spec peer(map(), String.t(), [String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def peer(fixture, root, arguments, options \\ []) do
    true = digest(fixture["peer"]) == fixture["peer_sha256"]
    fabric = Keyword.get(options, :fabric, 55)
    subject = Keyword.get(options, :subject, 770_001)
    directory = Path.join(root, "peer-#{fabric}")
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)

    common = [
      "--storage-directory",
      directory,
      "--paa-trust-store-path",
      fixture["paa"],
      "--commissioner-name",
      Integer.to_string(fabric),
      "--commissioner-nodeid",
      Integer.to_string(subject)
    ]

    ProcessCommand.run("/usr/bin/timeout", ["20", fixture["peer"] | arguments ++ common],
      cd: directory,
      stderr_to_stdout: true
    )
  end

  @spec controller_options(map(), String.t(), boolean()) :: keyword()
  def controller_options(fixture, root, reopen \\ false) do
    [
      client: Wotex.Matter.Native,
      lifecycle: :persistent,
      storage_mode: if(reopen, do: :open_existing, else: :create_new),
      authority: if(reopen, do: :stored, else: :generate_root),
      executable: fixture["controller"],
      executable_sha256: fixture["controller_sha256"],
      storage_path: Path.join(root, "controller"),
      vendor_id: 0xFFF1,
      fabric_id: 55,
      controller_node_id: 770_001,
      paa_trust_store: fixture["paa"],
      timeout: 15_000
    ]
  end

  @spec reopen!(String.t()) :: :ok
  def reopen!(root) do
    path = Path.join(root, "configuration")

    value =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("store_mode", "reopen")

    File.write!(path, Jason.encode!(value))
  end

  @spec digest(String.t()) :: String.t()
  def digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  @impl GenServer
  def init(options) do
    {:unix, :linux} = :os.type()
    # Use the OS clock sample itself, not ERTS's frequency-corrected clock.
    _ = now()
    owner = self()
    parent = options[:parent]

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Explicit exposed bridge software consumer",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" =>
          Map.new(
            [
              {"value", "boolean"},
              {"temperature", "integer"},
              {"duration", "integer"},
              {"identify", "integer"},
              {"wait", "integer"},
              {"startup", "integer"}
            ],
            fn
              {name, type} ->
                {name, %{"type" => type, "forms" => [%{"href" => "https://example.test/" <> name}]}}
            end
          ),
        "actions" => %{
          "set" => %{
            "input" => %{"type" => "boolean"},
            "forms" => [%{"href" => "https://example.test/set"}]
          },
          "protocol" => %{
            "input" => %{"type" => "string", "maxLength" => 131_072},
            "forms" => [%{"href" => "https://example.test/protocol"}]
          }
        }
      })

    handlers =
      for {operation, name} <- [
            {:readproperty, "value"},
            {:readproperty, "temperature"},
            {:readproperty, "duration"},
            {:writeproperty, "duration"},
            {:readproperty, "identify"},
            {:writeproperty, "identify"},
            {:readproperty, "wait"},
            {:writeproperty, "wait"},
            {:readproperty, "startup"},
            {:writeproperty, "startup"},
            {:invokeaction, "set"},
            {:invokeaction, "protocol"}
          ],
          into: %{} do
        {{operation, name},
         fn input, context ->
           {value, delay} = call(owner, {:handler, operation, name, input, context})
           if delay > 0, do: Process.sleep(delay)
           {:ok, value}
         end}
      end

    {:ok, exposed} = ExposedThing.new(td, handlers)

    routes =
      for {thing, endpoint, cluster, member, native, operation, name, input} <- [
            {<<0, 1>>, 3, 6, 0, :read, :readproperty, "value", fn nil, _ -> {:ok, nil} end},
            {<<0, 2>>, 4, 0x0402, 0, :read, :readproperty, "temperature",
             fn nil, _ -> {:ok, nil} end},
            {<<0, 1>>, 3, 6, 0x4001, :read, :readproperty, "duration", fn nil, _ -> {:ok, nil} end},
            {<<0, 1>>, 3, 6, 0x4001, :write, :writeproperty, "duration",
             fn {:u16, value}, _ -> {:ok, value} end},
            {<<0, 1>>, 3, 3, 0, :read, :readproperty, "identify", fn nil, _ -> {:ok, nil} end},
            {<<0, 1>>, 3, 3, 0, :write, :writeproperty, "identify",
             fn {:u16, value}, _ -> {:ok, value} end},
            {<<0, 1>>, 3, 6, 0x4002, :read, :readproperty, "wait", fn nil, _ -> {:ok, nil} end},
            {<<0, 1>>, 3, 6, 0x4002, :write, :writeproperty, "wait",
             fn {:u16, value}, _ -> {:ok, value} end},
            {<<0, 1>>, 3, 6, 0x4003, :read, :readproperty, "startup", fn nil, _ -> {:ok, nil} end},
            {<<0, 1>>, 3, 6, 0x4003, :write, :writeproperty, "startup",
             fn {:nullable_enum8, value}, _ -> {:ok, value} end},
            {<<0, 1>>, 3, 6, 1, :invoke, :invokeaction, "set",
             fn {:tlv, <<0x15, 0x18>>}, _ -> {:ok, true} end},
            {<<0, 1>>, 3, 6, 0, :invoke, :invokeaction, "set",
             fn {:tlv, <<0x15, 0x18>>}, _ -> {:ok, false} end}
          ],
          into: %{} do
        {{thing, endpoint, cluster, member, native},
         %{
           exposed: exposed,
           operation: operation,
           name: name,
           input: input,
           result: fn {:ok, value}, context ->
             if name in ["identify", "duration", "wait", "startup"] do
               :completed
             else
               call(owner, {:approved, thing, endpoint, value, context})
             end
           end
         }}
      end

    # Explicit protocol-bookkeeping Action. It publishes no physical observation.
    protocol_paths =
      for {cluster, members} <- [
            {3, [0, 64]},
            {4, 0..5},
            {6, [0, 1, 2, 64, 65, 66]},
            {98, [0, 1, 2, 3, 4, 5, 6, 64]}
          ],
          member <- members,
          do: {<<0, 1>>, 3, cluster, member, :invoke}

    protocol_paths = [{<<0, 2>>, 4, 3, 0, :invoke} | protocol_paths]

    protocol =
      Map.new(protocol_paths, fn key ->
        {key,
         %{
           exposed: exposed,
           operation: :invokeaction,
           name: "protocol",
           input: fn {:tlv, bytes}, _ -> {:ok, Base.encode16(bytes, case: :lower)} end,
           result: fn {:ok, nil}, _ -> :completed end
         }}
      end)

    routes = Map.merge(protocol, routes)

    configuration = [
      owner: owner,
      executable: options[:fixture]["bridge"],
      executable_sha256: options[:fixture]["bridge_sha256"],
      arguments: ["--configuration", Path.join(options[:root], "configuration")],
      clock: &now/0,
      minimum_rate: {1, 1},
      policy: fn request, context -> call(owner, {:policy, request, context}) end,
      routes: routes,
      timeout: 5000
    ]

    case Connection.start_link(configuration) do
      {:ok, connection} ->
        {:ok,
         %{
           connection: connection,
           parent: parent,
           value: false,
           temperature: 2100,
           controls: %{},
           allowed: true,
           principals: Keyword.get(options, :principals, [{55, 770_001, 780_001}]),
           denied_fabrics: MapSet.new(),
           delay: 0
         }}

      {:error, _} = error ->
        {:stop, error}
    end
  end

  @impl GenServer
  def handle_call({:policy, request, context}, _, state) do
    send(state.parent, {:bridge_policy, request, context})

    valid =
      request.principal.auth_mode == :case and not request.principal.is_commissioning and
        Enum.any?(state.principals, fn {fabric, subject, bridge} ->
          request.principal.subject == subject and request.fabric_scope.fabric_id == fabric and
            request.fabric_scope.bridge_node == bridge
        end) and not MapSet.member?(state.denied_fabrics, request.fabric_scope.fabric_id) and
        context.deadline > now()

    {:reply, if(valid and state.allowed, do: :allow, else: :deny), state}
  end

  def handle_call({:handler, operation, name, input, context}, {worker, _}, state) do
    send(state.parent, {:bridge_handler, worker, operation, name, context})

    {value, state} =
      case {operation, name} do
        {:readproperty, "value"} -> {state.value, state}
        {:readproperty, "temperature"} -> {state.temperature, state}
        {:readproperty, name} -> {Map.get(state.controls, name, 0), state}
        {:writeproperty, name} -> {nil, %{state | controls: Map.put(state.controls, name, input)}}
        {:invokeaction, "set"} -> {input, %{state | value: input}}
        {:invokeaction, "protocol"} -> {nil, state}
      end

    {:reply, {value, state.delay}, state}
  end

  def handle_call({:approved, thing, endpoint, value, context}, _, state) do
    observation = %{
      thing: thing,
      endpoint: endpoint,
      reachable: true,
      on_off: nil,
      temperature: nil
    }

    observation =
      if endpoint == 3,
        do: %{observation | on_off: value},
        else: %{observation | temperature: value}

    result = Connection.observe(state.connection, observation, min(context.deadline, now() + 500))
    send(state.parent, {:bridge_approved, context.request_id, result})
    {:reply, if(result == {:ok, :applied}, do: :completed, else: :failed), state}
  end

  def handle_call({:observe, observation}, _, state) do
    {:reply, Connection.observe(state.connection, observation, now() + 500), state}
  end

  def handle_call({:allowed, allowed}, _, state), do: {:reply, :ok, %{state | allowed: allowed}}

  def handle_call({:deny_fabric, fabric}, _, state),
    do: {:reply, :ok, %{state | denied_fabrics: MapSet.put(state.denied_fabrics, fabric)}}

  def handle_call({:allow_fabric, fabric}, _, state),
    do: {:reply, :ok, %{state | denied_fabrics: MapSet.delete(state.denied_fabrics, fabric)}}

  def handle_call({:delay, delay}, _, state), do: {:reply, :ok, %{state | delay: delay}}
  def handle_call(:connection, _, state), do: {:reply, state.connection, state}
  def handle_call(:status, _, state), do: {:reply, Connection.status(state.connection), state}

  def handle_call(:close, _, state) do
    result = Connection.close(state.connection)
    {:stop, :normal, result, %{state | connection: nil}}
  end

  @impl GenServer
  def handle_info({:wotex_matter_bridge_closed, connection, generation, error}, state) do
    send(state.parent, {:bridge_lost, connection, generation, error})
    {:noreply, %{state | connection: nil}}
  end

  @impl GenServer
  def terminate(_, %{connection: connection}) when is_pid(connection) do
    if Process.alive?(connection), do: Connection.close(connection)
    :ok
  end

  def terminate(_, _), do: :ok

  defp now do
    source = :erlang.system_info(:os_monotonic_time_source)
    :clock_gettime = source[:function]
    :CLOCK_MONOTONIC = source[:clock_id]
    :no = source[:extended]
    1_000_000_000 = source[:used_resolution]
    time = source[:time]
    true = is_integer(time) and time >= 0
    :erlang.convert_time_unit(time, :native, :millisecond)
  end
end
