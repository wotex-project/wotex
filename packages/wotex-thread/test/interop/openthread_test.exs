defmodule Wotex.Thread.OpenThreadInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Runtime.{ConsumedThing, Context, Result}
  alias Wotex.{ThingDescription, Thread}

  alias Wotex.Thread.{
    Daemon,
    Dataset,
    Error,
    JoinerAdmission,
    JoinerIdentity,
    RuntimeErrorPort,
    SoftwareNetwork,
    State,
    Transport
  }

  @moduletag :software
  @moduletag :interop
  @moduletag timeout: 180_000

  setup do
    assert match?({:unix, :linux}, :os.type())

    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-thread-network-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "stores"))
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  @tag requirements: ["WTH-S04", "WTH-S05", "WTH-S06", "WTH-N03"],
       vectors: ["WTH-V05", "WTH-V07", "WTH-V08", "WTH-V09", "WTH-V12"]
  test "WTH-N03 WTH-V12 real peers form, commission, join and activate a pending Dataset",
       context do
    leader_options =
      SoftwareNetwork.host_options(:leader, context.root,
        allow_network_creation: true,
        timeout: 10_000
      )

    assert {:ok, leader} = Thread.connect(leader_options)
    leader_pids = SoftwareNetwork.native_pids(leader)

    try do
      assert {:ok, joiner} =
               Thread.connect(SoftwareNetwork.host_options(:joiner, context.root, timeout: 10_000))

      joiner_pids = SoftwareNetwork.native_pids(joiner)

      try do
        active = active_dataset(1)

        assert {:ok, %State{role: :leader, ipv6_enabled: true, thread_enabled: true}} =
                 Thread.form_network(leader, active, 30_000)

        assert {:ok, ^active} = Thread.get_dataset(leader, :active, 2_000)

        assert {:ok, subscription} =
                 Thread.subscribe(joiner, %{type: :state, max_queue_length: 64, timeout: 2_000})

        reference = subscription.reference

        assert_receive {:wotex_thread, ^reference,
                        {:ok, %State{role: :disabled}, %{changed_flags: 0}}},
                       2_000

        assert {:ok, %{state: :active}} = Thread.commissioner_start(leader, timeout: 10_000)
        identity_input = %{discerner: %{length: 12, value: 0xA42}}
        assert {:ok, identity} = JoinerIdentity.new(identity_input)

        assert {:ok, admission} =
                 JoinerAdmission.new(%{
                   identity: identity,
                   pskd: "WTEST123",
                   lifetime: 60
                 })

        assert {:ok, %{identity: ^identity_input, lifetime_s: 60}} =
                 Thread.add_joiner(leader, admission, 2_000)

        wrong = %{pskd: "WTEST124", discerner: identity}

        assert {:error,
                %Error{
                  code: :remote_error,
                  class: :permanent,
                  effect: :unknown,
                  retryable: false,
                  details: %{status: wrong_status}
                }} = Thread.joiner_start(joiner, wrong, 60_000)

        assert is_integer(wrong_status)

        assert {:error, %Error{code: :dataset_not_found}} =
                 Thread.get_dataset(joiner, :active, 2_000)

        assert {:ok, %{joined: true}} =
                 Thread.joiner_start(joiner, %{pskd: "WTEST123", discerner: identity}, 60_000)

        assert {:ok, %State{ipv6_enabled: true, thread_enabled: true}} =
                 Thread.set_enabled(joiner, %{ipv6: true, thread: true}, 10_000)

        assert :ok =
                 SoftwareNetwork.eventually(
                   fn ->
                     match?(
                       {:ok, %State{role: role}} when role in [:child, :router],
                       Thread.inspect_state(joiner, timeout: 2_000)
                     )
                   end,
                   30_000
                 )

        assert_role_report(reference)
        assert {:ok, ^active} = Thread.get_dataset(joiner, :active, 2_000)

        pending = pending_dataset(active, 2, 3, 5_000)

        assert {:ok, %{accepted: true, effective: :not_verified}} =
                 Thread.management_pending_set(leader, %{dataset: pending}, 10_000)

        assert {:ok, ^active} = Thread.get_dataset(leader, :active, 2_000)
        assert {:ok, ^active} = Thread.get_dataset(joiner, :active, 2_000)
        activated = active_dataset(2)
        assert_dataset_on_both(leader, joiner, activated, 20_000)

        late = active_dataset(3)

        assert {:error,
                %Error{
                  code: :timeout,
                  class: :permanent,
                  effect: :unknown,
                  retryable: false
                }} = Thread.management_active_set(leader, %{dataset: late}, 1)

        assert {:error, %Error{code: :busy, class: :rate_limited, effect: :none}} =
                 Thread.management_active_set(leader, %{dataset: active_dataset(4)}, 2_000)

        assert_dataset_on_both(leader, joiner, late, 20_000)

        final = active_dataset(4)

        assert {:ok, %{accepted: true, effective: :not_verified}} =
                 Thread.management_active_set(leader, %{dataset: final}, 10_000)

        assert_dataset_on_both(leader, joiner, final, 20_000)
        assert {:ok, %{state: :disabled}} = Thread.commissioner_stop(leader, timeout: 2_000)
        assert {:ok, %{state: :active}} = Thread.commissioner_start(leader, timeout: 10_000)

        assert {:error, %Error{code: :remote_error, effect: :unknown}} =
                 Thread.remove_joiner(leader, identity, 2_000)

        assert {:ok, %{state: :disabled}} = Thread.commissioner_stop(leader, timeout: 2_000)
        assert :ok = Thread.unsubscribe(joiner, subscription)
      after
        assert :ok = Thread.disconnect(joiner)
        assert_native_cleanup(joiner_pids, "wthjoiner")
      end
    after
      assert :ok = Thread.disconnect(leader)
      assert_native_cleanup(leader_pids, "wthleader")
    end
  end

  @tag requirements: ["WTH-S02", "WTH-I06"], vectors: ["WTH-V03", "WTH-V12"]
  test "WTH-S02 WTH-I06 a borrowed daemon serves the public Runtime and survives disconnect",
       context do
    assert {:ok, daemon} = SoftwareNetwork.start_daemon(context.root)

    try do
      assert {:ok, session} =
               Thread.connect(
                 client: Daemon,
                 socket_path: daemon.socket,
                 timeout: 5_000
               )

      assert {:ok, "disabled"} = Thread.send(session, %{type: :state})
      assert {:ok, version} = Thread.send(session, %{type: :version})
      assert version =~ "OPENTHREAD/"
      assert {:ok, "OpenThread"} = Thread.send(session, %{type: :network_name})
      assert {:ok, nil} = Thread.send(session, %{type: :rloc16})
      assert :ok = Thread.disconnect(session)
      assert SoftwareNetwork.owned_process?(daemon.os_pid, daemon.executable)

      {:ok, td} = ThingDescription.from_map(runtime_td())

      assert {:ok, consumed} =
               ConsumedThing.new(td,
                 profiles: [Thread.profile()],
                 transports: %{
                   thread:
                     {Transport,
                      [
                        client: Daemon,
                        socket_path: daemon.socket,
                        target: "software-daemon",
                        timeout: 5_000
                      ]}
                 },
                 credentials: {RuntimeErrorPort, nil}
               )

      deadline = System.monotonic_time(:millisecond) + 5_000
      runtime_context = Context.new!(request_id: "software-daemon-read", deadline: deadline)

      assert {:ok,
              %Result{
                request_id: "software-daemon-read",
                operation: :readproperty,
                status: :ok,
                payload: "disabled",
                metadata: %{}
              }} = ConsumedThing.read_property(consumed, "state", runtime_context)

      assert SoftwareNetwork.owned_process?(daemon.os_pid, daemon.executable)
    after
      assert :ok = SoftwareNetwork.stop_process(daemon)
      refute File.exists?(daemon.socket)
      refute File.exists?("/sys/class/net/#{daemon.interface}")
    end
  end

  @tag requirements: ["WTH-N02", "WTH-N03"], vectors: ["WTH-V12"]
  test "WTH-N03 sensor and light compose over Thread with the Wotex CoAP client", context do
    leader_options =
      SoftwareNetwork.host_options(:leader, context.root,
        allow_network_creation: true,
        timeout: 10_000
      )

    assert {:ok, leader} = Thread.connect(leader_options)
    leader_pids = SoftwareNetwork.native_pids(leader)

    try do
      active = active_dataset(1)

      assert {:ok, %State{role: :leader}} = Thread.form_network(leader, active, 30_000)
      {:ok, active_bytes} = Dataset.encode(active)
      dataset_path = Path.join(context.root, "application-dataset.tlv")
      :ok = File.write(dataset_path, active_bytes, [:exclusive, :sync])
      :ok = File.chmod(dataset_path, 0o600)

      assert {:ok, sensor} =
               SoftwareNetwork.start_application(context.root, :sensor, :sensor, dataset_path)

      try do
        assert sensor.sleepy

        assert {:ok, light} =
                 SoftwareNetwork.start_application(context.root, :light, :light, dataset_path)

        try do
          refute light.sleepy
          result = run_coap_client(context.root, sensor.address, light.address)

          assert result == %{
                   "format" => "wotex.thread.coap-composition",
                   "version" => 1,
                   "sensor" => %{
                     "code" => 69,
                     "content_format" => 0,
                     "payload" => "21.50"
                   },
                   "light" => %{
                     "before" => %{
                       "code" => 69,
                       "content_format" => 0,
                       "payload" => "0"
                     },
                     "put" => %{
                       "code" => 68,
                       "content_format" => nil,
                       "payload" => ""
                     },
                     "after" => %{
                       "code" => 69,
                       "content_format" => 0,
                       "payload" => "1"
                     }
                   }
                 }
        after
          assert :ok = SoftwareNetwork.stop_process(light)
          assert {:ok, report} = SoftwareNetwork.application_report(light)

          assert report == %{
                   "format" => "wotex.thread.coap-peer",
                   "version" => 1,
                   "mode" => "light",
                   "get_requests" => 2,
                   "put_requests" => 1,
                   "final" => "1"
                 }

          refute File.exists?("/sys/class/net/#{light.interface}")
        end
      after
        assert :ok = SoftwareNetwork.stop_process(sensor)
        assert {:ok, report} = SoftwareNetwork.application_report(sensor)

        assert report == %{
                 "format" => "wotex.thread.coap-peer",
                 "version" => 1,
                 "mode" => "sensor",
                 "get_requests" => 1,
                 "put_requests" => 0,
                 "final" => "21.50"
               }

        refute File.exists?("/sys/class/net/#{sensor.interface}")
      end
    after
      assert :ok = Thread.disconnect(leader)
      assert_native_cleanup(leader_pids, "wthleader")
    end
  end

  defp active_dataset(timestamp) do
    dataset([
      {0, <<0, 0, 15>>},
      {1, <<0x12, 0x37>>},
      {2, <<1, 2, 3, 4, 5, 6, 7, 11>>},
      {3, "wotex-mesh"},
      {4, "0123456789abcdef"},
      {5, "fedcba9876543210"},
      {7, <<0xFD, 1, 2, 3, 4, 5, 6, 10>>},
      {12, <<2, 0xA0, 0xF7, 0xF8>>},
      {14, <<timestamp::48, 0::16>>},
      {53, <<0, 4, 0, 0x1F, 0xFF, 0xE0>>}
    ])
  end

  defp pending_dataset(active, active_timestamp, pending_timestamp, delay_ms) do
    entries =
      Enum.map(active.entries, fn
        {14, _} -> {14, <<active_timestamp::48, 0::16>>}
        entry -> entry
      end) ++ [{51, <<pending_timestamp::48, 0::16>>}, {52, <<delay_ms::32>>}]

    dataset(entries)
  end

  defp dataset(entries) do
    bytes = for {type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>
    {:ok, dataset} = Dataset.decode(bytes)
    dataset
  end

  defp assert_dataset_on_both(leader, joiner, expected, timeout) do
    assert :ok =
             SoftwareNetwork.eventually(
               fn ->
                 Thread.get_dataset(leader, :active, 2_000) == {:ok, expected} and
                   Thread.get_dataset(joiner, :active, 2_000) == {:ok, expected}
               end,
               timeout
             )
  end

  defp assert_role_report(reference) do
    receive do
      {:wotex_thread, ^reference, {:ok, %State{role: role}, %{changed_flags: flags}}}
      when role in [:child, :router] and is_integer(flags) and flags > 0 ->
        :ok

      {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: flags}}}
      when is_integer(flags) and flags > 0 ->
        assert_role_report(reference)
    after
      30_000 -> flunk("no child or router State callback arrived")
    end
  end

  defp assert_native_cleanup(pids, interface) do
    assert :ok =
             SoftwareNetwork.eventually(
               fn -> Enum.all?(pids, &(not File.exists?("/proc/#{&1}"))) end,
               5_000
             )

    refute File.exists?("/sys/class/net/#{interface}")
  end

  defp runtime_td do
    %{
      "@context" => "https://www.w3.org/2022/wot/td/v1.1",
      "title" => "Thread software daemon",
      "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
      "security" => ["none"],
      "properties" => %{
        "state" => %{
          "forms" => [%{"href" => "thread+unix://software-daemon/state"}]
        }
      }
    }
  end

  defp run_coap_client(root, sensor, light) do
    mix = System.find_executable("mix") || flunk("mix executable is unavailable")
    project = Path.expand("../../../wotex-coap", __DIR__)
    script = Path.expand("../support/coap_client.exs", __DIR__)
    result = Path.join(root, "coap-composition.json")

    {output, status} =
      System.cmd(mix, ["run", script, "--", sensor, light, result],
        cd: project,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}, {"WOTEX_PATH_DEPS", "1"}]
      )

    assert status == 0, output
    assert {:ok, bytes} = File.read(result)
    assert {:ok, observation} = Jason.decode(bytes)
    observation
  end
end
