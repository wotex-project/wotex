Code.require_file("peer.exs", __DIR__)

defmodule Wotex.Matter.SoftwareScenarios do
  @moduledoc false

  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Descriptor, Native, SoftwarePeer}

  @peers [
    {:common, :lighting},
    {:oneshot, :all_clusters},
    {:lighting, :lighting},
    {:thermostat, :all_clusters},
    {:bridge, :bridge},
    {:acl, :lighting},
    {:native_attestation, :lighting},
    {:trusted, :lighting},
    {:wrong_pin, :lighting},
    {:attestation_failure, :lighting},
    {:expired_window, :lighting},
    {:acl_denied, :lighting},
    {:timeout, :lighting},
    {:operation_resources, :lighting},
    {:subscription_resources, :lighting},
    {:oneshot_stress, :all_clusters}
  ]
  @controller_keys ~w(executable storage_path vendor_id fabric_id controller_node_id paa_trust_store)a
  @common_cases ~w(CLOSE CONTROL_PUMP INPUT_PRESSURE PENDING_LOSS
                   PENDING_SUBSCRIPTION_LOSS REQUEST_ID RUNTIME_LOSS STARTUP_RESOURCES STREAM_OWNER STRESS STRESS_FAILURES)

  @spec with_fixtures(map(), String.t(), (map() -> term())) :: term()
  def with_fixtures(artifacts, directory, operation) do
    private_directory(directory)
    context = %{artifacts: artifacts, directory: directory}

    own_peers(Enum.with_index(@peers, 1), context, %{}, fn peers ->
      Mix.shell().info("Preparing isolated Matter commissioning and interaction fixtures")
      fixtures = prepare(context, peers)
      operation.(fixtures)
    end)
  end

  defp own_peers([], _context, peers, operation), do: operation.(peers)

  defp own_peers([{name_and_kind, index} | remaining], context, peers, operation) do
    {name, kind} = name_and_kind
    directory = Path.join(context.directory, Atom.to_string(name))
    private_directory(directory)
    pin = setup_pin()
    discriminator = 2400 + index
    control = Path.join(directory, "control.fifo")

    arguments = [
      "--KVS",
      Path.join(directory, "peer.kvs"),
      "--secured-device-port",
      Integer.to_string(5600 + index),
      "--discriminator",
      Integer.to_string(discriminator),
      "--passcode",
      Integer.to_string(pin)
    ]

    arguments =
      if kind in [:all_clusters, :bridge],
        do: arguments ++ ["--app-pipe", control],
        else: arguments

    scenario = %{
      "controller" => controller(context, directory, index),
      "node_id" => 780_000 + index,
      "setup_pin" => pin,
      "discriminator" => discriminator,
      "control_path" => control,
      "endpoint" => 1,
      "timeout" => 30_000,
      "peer" => %{
        "executable" => Map.fetch!(context.artifacts, kind),
        "arguments" => arguments,
        "directory" => directory
      }
    }

    if name in [:common, :oneshot, :expired_window, :acl_denied, :oneshot_stress] do
      with_peer(scenario, fn ->
        own_peers(remaining, context, Map.put(peers, name, Map.delete(scenario, "peer")), operation)
      end)
    else
      own_peers(remaining, context, Map.put(peers, name, scenario), operation)
    end
  end

  @spec with_peer(map(), (-> term())) :: term()
  def with_peer(%{"peer" => descriptor}, operation) do
    directory = Map.fetch!(descriptor, "directory")

    case SoftwarePeer.start(
           Map.fetch!(descriptor, "executable"),
           Map.fetch!(descriptor, "arguments"),
           cd: directory,
           startup_timeout: 30_000,
           timeout: 3_600_000,
           ready: "Server Listening...",
           log: Path.join(directory, "peer.log")
         ) do
      {:ok, peer} ->
        try do
          operation.()
        after
          unless SoftwarePeer.stop(peer) == :ok, do: fail(:software_peer_cleanup_failed)
        end

      {:error, _} ->
        fail(:software_peer_start_failed)
    end
  end

  def with_peer(%{}, operation), do: operation.()

  defp prepare(context, peers) do
    # Start the real expiry interval before preparing the other controller stores.
    expired = commission(peers.expired_window)

    material =
      with_session(expired, fn session ->
        case Matter.open_commissioning_window(session, %{
               node_id: expired["node_id"],
               timeout_s: 180,
               iteration_count: 10_000,
               discriminator: 2611
             }) do
          {:ok, material} -> material
          _ -> fail(:software_window_setup_failed)
        end
      end)

    expiry = System.monotonic_time(:millisecond) + 180_200
    common = commission(peers.common)
    oneshot = commission(peers.oneshot)
    oneshot_stress = commission(peers.oneshot_stress)
    denied = peers.acl_denied |> commission() |> deny_acl()

    environment =
      Map.new(@common_cases, fn name ->
        fixture = Map.put(common, "unreachable_node_id", 0x123456789ABC)

        fixture =
          if name in ["STARTUP_RESOURCES", "STRESS", "STRESS_FAILURES"] do
            directory = Path.join(context.directory, String.downcase(name) <> "-resources")
            private_directory(directory)

            fixture
            |> put_in(["controller", "executable"], context.artifacts.resource_host)
            |> Map.put("resource_directory", directory)
          else
            fixture
          end

        fixture_file(context, "NATIVE_" <> name, fixture)
      end)

    environment =
      Enum.reduce(
        [
          {"NATIVE_LIGHTING", peers.lighting},
          {"NATIVE_THERMOSTAT", peers.thermostat},
          {"NATIVE_BRIDGE", peers.bridge},
          {"NATIVE_ACL", peers.acl},
          {"NATIVE_ONESHOT", oneshot},
          {"NATIVE_ONESHOT_STRESS", resource_fixture(context, oneshot_stress, "oneshot-resources")},
          {"NATIVE_OPERATION_RESOURCES",
           resource_fixture(context, peers.operation_resources, "operation-resources")},
          {"NATIVE_SUBSCRIPTION_RESOURCES",
           resource_fixture(context, peers.subscription_resources, "subscription-resources")},
          {"NATIVE_ATTESTATION", untrusted(context, peers.native_attestation)},
          {"NATIVE_TIMEOUT", wrong_pin(peers.timeout)}
        ],
        environment,
        fn {name, fixture}, acc ->
          {key, path} = fixture_file(context, name, fixture)
          Map.put(acc, key, path)
        end
      )

    flow_directory = Path.join(context.directory, "flow")
    private_directory(flow_directory)

    flow =
      common
      |> put_in(["controller", "executable"], context.artifacts.flow_host)
      |> Map.put("directory", flow_directory)

    window =
      common
      |> Map.put("discriminator", 2601)
      |> Map.put("new_controller", controller(context, context.directory, 101))
      |> Map.put("new_node_id", 780_101)

    expired_attempt = %{
      "controller" => controller(context, context.directory, 102),
      "node_id" => 780_102,
      "setup_pin" => material.setup_pin,
      "discriminator" => material.discriminator,
      "timeout" => 1_000,
      "expected_code" => "timeout",
      "expected_sdk_status" => 0x32,
      "expected_effect" => "none"
    }

    commissioning = %{
      "trusted" =>
        Map.put(peers.trusted, "window", %{
          "timeout_s" => 180,
          "iteration_count" => 10_000,
          "discriminator" => 2608
        }),
      "wrong_pin" => peers.wrong_pin |> wrong_pin() |> failure("timeout", 0x32),
      "attestation_failure" =>
        context |> untrusted(peers.attestation_failure) |> failure("commissioning_failed", 0x20),
      "expired_window" => expired_attempt,
      "acl_denied" => denied
    }

    environment =
      Enum.reduce(
        [{"PROCESS_FLOW", flow}, {"NATIVE_WINDOW", window}, {"COMMISSIONING", commissioning}],
        environment,
        fn {name, fixture}, acc ->
          {key, path} = fixture_file(context, name, fixture)
          Map.put(acc, key, path)
        end
      )

    Mix.shell().info("Waiting for the required 180-second Matter commissioning-window expiry")
    wait_until(expiry)

    with_session(expired, fn session ->
      address = address(expired, 0, 0x003C, 0)

      unless match?(
               {:ok, %AttributeReport{value: %{type: :u8, value: 0}}},
               Matter.read_attribute(session, address)
             ),
             do: fail(:software_window_did_not_expire)
    end)

    Map.merge(environment, %{
      "WOTEX_MATTER_NATIVE_EXECUTABLE" => context.artifacts.host,
      "WOTEX_MATTER_CONTRACT_DRIVER" => context.artifacts.contract_driver,
      "WOTEX_MATTER_CONTROLLER_TEST" => context.artifacts.controller_test
    })
  end

  defp controller(context, directory, index) do
    %{
      "executable" => context.artifacts.host,
      "storage_path" => Path.join(directory, "controller-#{index}"),
      "storage_mode" => "create_new",
      "authority" => "generate_root",
      "vendor_id" => 0xFFF1,
      "fabric_id" => 500 + index,
      "controller_node_id" => 770_000 + index,
      "paa_trust_store" => context.artifacts.paa,
      "timeout" => 60_000
    }
  end

  defp resource_fixture(context, fixture, name) do
    directory = Path.join(context.directory, name)
    private_directory(directory)

    fixture
    |> put_in(["controller", "executable"], context.artifacts.resource_host)
    |> Map.put("resource_directory", directory)
  end

  defp commission(scenario) do
    with_session(scenario, fn session ->
      unless match?(
               {:ok, %{case: :established}},
               Matter.commission_on_network(session, %{
                 node_id: scenario["node_id"],
                 setup_pin: scenario["setup_pin"],
                 discriminator: scenario["discriminator"],
                 timeout: 60_000
               })
             ),
             do: fail(:software_commissioning_setup_failed)
    end)

    scenario
    |> put_in(["controller", "storage_mode"], "open_existing")
    |> put_in(["controller", "authority"], "stored")
  end

  defp deny_acl(scenario) do
    address = address(scenario, 0, 31, 0)
    entries = [%{privilege: 5, auth_mode: 2, subjects: [0xFFFFFFEFFFFFFF04], targets: nil}]
    {:ok, value} = Descriptor.to_element(:attribute, address, :write, entries)

    with_session(scenario, fn session ->
      unless match?({:ok, %{status: 0}}, Matter.write_attribute(session, address, value)),
        do: fail(:software_acl_setup_failed)
    end)

    scenario |> Map.put("address", address) |> Map.put("expected_status", 0x7E)
  end

  defp address(scenario, endpoint, cluster, member) do
    %{
      fabric_id: scenario["controller"]["fabric_id"],
      node_id: scenario["node_id"],
      endpoint: endpoint,
      cluster: cluster,
      member: member
    }
  end

  defp with_session(scenario, operation) do
    controller = scenario["controller"]
    mode = if controller["storage_mode"] == "create_new", do: :create_new, else: :open_existing
    authority = if mode == :create_new, do: :generate_root, else: :stored

    options =
      [
        client: Native,
        lifecycle: :persistent,
        storage_mode: mode,
        authority: authority,
        timeout: 60_000
      ] ++
        Enum.map(@controller_keys, &{&1, Map.fetch!(controller, Atom.to_string(&1))})

    case Matter.connect(options) do
      {:ok, session} ->
        try do
          operation.(session)
        after
          unless Matter.disconnect(session) == :ok, do: fail(:software_controller_cleanup_failed)
        end

      _ ->
        fail(:software_controller_setup_failed)
    end
  end

  defp fixture_file(context, name, fixture) do
    path = Path.join(context.directory, String.downcase(name) <> "-fixture.json")
    result = Path.join(context.directory, String.downcase(name) <> "-result.json")
    {:ok, file} = File.open(path, [:write, :exclusive])

    try do
      File.chmod!(path, 0o600)
      :ok = IO.binwrite(file, Jason.encode!(Map.put(fixture, "result_path", result)))
    after
      File.close(file)
    end

    {"WOTEX_MATTER_" <> name <> "_FIXTURE", path}
  end

  defp untrusted(context, scenario),
    do: put_in(scenario, ["controller", "paa_trust_store"], context.artifacts.untrusted_paa)

  defp wrong_pin(scenario) do
    pin = setup_pin()

    if pin == scenario["setup_pin"],
      do: wrong_pin(scenario),
      else: Map.put(scenario, "setup_pin", pin)
  end

  defp failure(scenario, code, status),
    do:
      Map.merge(scenario, %{
        "expected_code" => code,
        "expected_sdk_status" => status,
        "expected_effect" => "none",
        "timeout" => 10_000
      })

  defp setup_pin do
    <<random::unsigned-64>> = :crypto.strong_rand_bytes(8)
    pin = rem(random, 99_999_998) + 1
    digits = pin |> Integer.to_string() |> String.pad_leading(8, "0")

    if pin in [12_345_678, 87_654_321] or length(Enum.uniq(String.graphemes(digits))) == 1,
      do: setup_pin(),
      else: pin
  end

  defp private_directory(path) do
    File.mkdir!(path)
    File.chmod!(path, 0o700)
  end

  defp wait_until(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      Process.sleep(min(remaining, 1_000))
      wait_until(deadline)
    end
  end

  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
