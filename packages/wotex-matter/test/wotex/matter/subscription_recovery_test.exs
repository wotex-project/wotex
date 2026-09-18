defmodule Wotex.Matter.SubscriptionRecoveryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.{Error, Native, Subscription}

  @path %{fabric_id: 1, node_id: 3, endpoint: 1, cluster: 0x0201, member: 0}

  test "WMA-F09 default subscription loss is terminal once" do
    vector = contract_vector!("WMA-F09")
    assert vector["requirements"] == ["WMA-S04", "WMA-N01"]
    assert vector["input"]["resubscribe"] == false
    expected = vector["expectation"]["value"]

    audit = temporary_path("default-loss")
    executable = native_fixture(audit, "default_loss")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok, %Subscription{} = subscription} =
             Matter.subscribe(session, %{kind: :attribute, paths: [@path]})

    assert_receive {:wotex_matter, reference, {:error, %Error{code: :session_lost}}}, 1_000
    assert reference == subscription.reference
    refute_receive {:wotex_matter, ^reference, _}, 50
    assert eventually(fn -> Matter.unsubscribe(session, subscription) == :ok end)
    assert :ok = Matter.disconnect(session)

    frames = audit_frames(audit)
    subscribe = Enum.find(frames, &(&1["operation"] == "subscribe"))
    assert subscribe["parameters"]["resubscribe"] == false
    assert Enum.count(frames, &(&1["operation"] == "close")) == expected["calls"]["shutdown"]
    assert Enum.count(frames, &(&1["operation"] in ["write", "invoke"])) == 0
    assert expected["terminal_count"] == 1
    assert expected["terminal_code"] == "session_lost"
    assert expected["active_subscriptions"] == 0
    assert expected["deliveries_after_loss"] == 0
  end

  test "WMA-V08 opted-in recovery exposes loss and a fresh delivery generation" do
    audit = temporary_path("recovered")
    executable = native_fixture(audit, "recovered")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok, %Subscription{generation: 1} = subscription} =
             Matter.subscribe(session, %{
               kind: :attribute,
               paths: [@path],
               resubscribe: true
             })

    assert_receive {:wotex_matter, reference,
                    {:status, :resubscribing, %{continuity: :lost, generation: 2, attempt: 1}}},
                   1_000

    assert reference == subscription.reference

    assert_receive {:wotex_matter, ^reference,
                    {:status, :resubscribing, %{continuity: :lost, generation: 2, attempt: 2}}},
                   1_000

    assert_receive {:wotex_matter, ^reference,
                    {:status, :resubscribed,
                     %{
                       continuity: :unknown,
                       generation: 2,
                       attempt: 2,
                       min_interval_s: 3,
                       max_interval_s: 30,
                       sdk_subscription_id: 74
                     }}},
                   1_000

    assert_receive {:wotex_matter, ^reference, {:ok, %{type: :i16, value: 2200}, metadata}},
                   1_000

    assert metadata.initial
    assert metadata.report_id == 1
    assert metadata.data_version == 9
    assert metadata.min_interval_s == 3
    assert metadata.max_interval_s == 30
    assert metadata.sdk_subscription_id == 74

    assert :ok = Matter.unsubscribe(session, subscription)
    assert :ok = Matter.disconnect(session)

    frames = audit_frames(audit)
    subscribe = Enum.find(frames, &(&1["operation"] == "subscribe"))
    unsubscribe = Enum.find(frames, &(&1["operation"] == "unsubscribe"))
    assert subscribe["parameters"]["resubscribe"] == true
    assert unsubscribe["parameters"]["generation"] == 2
    assert Enum.count(frames, &(&1["operation"] in ["write", "invoke"])) == 0
  end

  test "WMA-V08 a report buffered before a completed recovery is discarded, not flushed" do
    audit = temporary_path("early-recovered")
    executable = native_fixture(audit, "early_recovered")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok, %Subscription{} = subscription} =
             Matter.subscribe(session, %{kind: :attribute, paths: [@path], resubscribe: true})

    reference = subscription.reference

    assert_receive {:wotex_matter, ^reference,
                    {:status, :resubscribing, %{continuity: :lost, generation: 2, attempt: 1}}},
                   1_000

    assert_receive {:wotex_matter, ^reference,
                    {:status, :resubscribed, %{continuity: :unknown, generation: 2, attempt: 1}}},
                   1_000

    # The retired first generation's report never follows its loss signal.
    assert_receive {:wotex_matter, ^reference, {:ok, %{type: :i16, value: 2200}, _}}, 1_000
    refute_receive {:wotex_matter, ^reference, _}, 50
    assert :ok = Matter.unsubscribe(session, subscription)
    assert :ok = Matter.disconnect(session)
    assert Enum.count(audit_frames(audit), &(&1["event"] == "report_ack")) >= 1
  end

  test "WMA-V08 recovery accepts at most five attempts then retires" do
    audit = temporary_path("exhausted")
    executable = native_fixture(audit, "exhausted")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok, subscription} =
             Matter.subscribe(session, %{
               kind: :attribute,
               paths: [@path],
               resubscribe: true
             })

    for attempt <- 1..5 do
      assert_receive {:wotex_matter, reference,
                      {:status, :resubscribing,
                       %{continuity: :lost, generation: 2, attempt: ^attempt}}},
                     1_000

      assert reference == subscription.reference
    end

    assert_receive {:wotex_matter, reference, {:error, %Error{code: :session_lost}}}, 1_000
    assert reference == subscription.reference
    refute_receive {:wotex_matter, ^reference, _}, 50
    assert eventually(fn -> Matter.unsubscribe(session, subscription) == :ok end)
    assert :ok = Matter.disconnect(session)
  end

  defp contract_vector!(id) do
    path = Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)

    contract =
      path
      |> File.read!()
      |> Jason.decode!()

    Enum.find(contract["cases"], &(&1["id"] == id)) || flunk("missing #{id}")
  end

  defp eventually(function, attempts \\ 50)
  defp eventually(function, 0), do: function.()

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(10)
      eventually(function, attempts - 1)
    end
  end

  defp audit_frames(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      {:error, :enoent} ->
        []
    end
  end

  defp native_options(executable) do
    paa = temporary_path("paa")
    File.mkdir_p!(paa)
    on_exit(fn -> File.rm_rf(paa) end)

    [
      executable: executable,
      lifecycle: :persistent,
      storage_path: temporary_path("store"),
      storage_mode: :create_new,
      authority: :generate_root,
      vendor_id: 65_521,
      fabric_id: 1,
      controller_node_id: 2,
      paa_trust_store: paa,
      timeout: 3_000
    ]
  end

  defp native_fixture(audit, mode) do
    path = temporary_path("recovery-host")

    script = ~S'''
    #!/usr/bin/env elixir
    audit = System.fetch_env!("WOTEX_MATTER_TEST_AUDIT")
    mode = System.fetch_env!("WOTEX_MATTER_TEST_MODE")

    read = fn ->
      case IO.read(:stdio, :line) do
        :eof -> System.halt(0)
        {:error, _} -> System.halt(1)
        line -> File.write!(audit, line, [:append]); line
      end
    end

    IO.puts(~s({"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"}))
    flow = read.()
    [_, session_generation] = Regex.run(~r/"session_generation":"([0-9a-f]{32})"/, flow)
    read.()
    IO.puts(~s({"version":1,"id":"1","ok":true,"result":{"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521}}))

    status = fn subscription_id, name, continuity, attempt ->
      IO.puts(~s({"version":1,"event":"subscription_status","session_generation":"#{session_generation}","subscription_id":"#{subscription_id}","generation":2,"status":"#{name}","continuity":"#{continuity}","attempt":#{attempt}}))
    end

    retired = fn subscription_id, generation, last ->
      IO.puts(~s({"version":1,"event":"stream_retired","session_generation":"#{session_generation}","subscription_id":"#{subscription_id}","generation":#{generation},"last_report_sequence":#{last}}))
    end

    loop = fn loop, subscription_id, generation, last ->
      line = read.()

      cond do
        String.contains?(line, ~s("event":"report_ack")) ->
          loop.(loop, subscription_id, generation, last)

        mode == "early_recovered" and String.contains?(line, ~s("operation":"subscribe")) ->
          [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)
          [_, current] = Regex.run(~r/"subscription_id":"([0-9a-f]{32})"/, line)
          stream = ~s("session_generation":"#{session_generation}","subscription_id":"#{current}")
          path = ~s("path":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0})

          report = fn generation, sequence, value, intervals ->
            ~s({"version":1,"event":"subscription_report",#{stream},"generation":#{generation},"report_sequence":#{sequence},"kind":"attribute","value":{"tag":"anonymous","type":"i16","value":#{value}},"metadata":{#{path},"data_version":9,"initial":true,"report_id":1,#{intervals}}})
          end

          # One write keeps the recovery frames ahead of the establishment flush.
          IO.binwrite(Enum.map_join([
            report.(1, 1, 2150, ~s("min_interval_s":1,"max_interval_s":60,"sdk_subscription_id":73)),
            ~s({"version":1,"id":"#{id}","ok":true,"result":{"subscription_id":"#{current}","generation":1,"min_interval_s":1,"max_interval_s":60,"sdk_subscription_id":73}}),
            ~s({"version":1,"event":"subscription_status",#{stream},"generation":2,"status":"resubscribing","continuity":"lost","attempt":1}),
            ~s({"version":1,"event":"stream_retired",#{stream},"generation":1,"last_report_sequence":1}),
            ~s({"version":1,"event":"subscription_status",#{stream},"generation":2,"status":"resubscribed","continuity":"unknown","attempt":1,"min_interval_s":3,"max_interval_s":30,"sdk_subscription_id":74}),
            report.(2, 2, 2200, ~s("min_interval_s":3,"max_interval_s":30,"sdk_subscription_id":74))
          ], &(&1 <> "\n")))

          loop.(loop, current, 2, 2)

        String.contains?(line, ~s("operation":"subscribe")) ->
          [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)
          [_, current] = Regex.run(~r/"subscription_id":"([0-9a-f]{32})"/, line)
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":{"subscription_id":"#{current}","generation":1,"min_interval_s":1,"max_interval_s":60,"sdk_subscription_id":73}}))

          case mode do
            "default_loss" ->
              IO.puts(~s({"version":1,"event":"subscription_error","session_generation":"#{session_generation}","subscription_id":"#{current}","generation":1,"error":{"code":"session_lost"}}))
              retired.(current, 1, 0)
              loop.(loop, current, 1, 0)

            "recovered" ->
              status.(current, "resubscribing", "lost", 1)
              retired.(current, 1, 0)
              status.(current, "resubscribing", "lost", 2)
              IO.puts(~s({"version":1,"event":"subscription_status","session_generation":"#{session_generation}","subscription_id":"#{current}","generation":2,"status":"resubscribed","continuity":"unknown","attempt":2,"min_interval_s":3,"max_interval_s":30,"sdk_subscription_id":74}))
              metadata = ~s({"path":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0},"data_version":9,"initial":true,"report_id":1,"min_interval_s":3,"max_interval_s":30,"sdk_subscription_id":74})
              IO.puts(~s({"version":1,"event":"subscription_report","session_generation":"#{session_generation}","subscription_id":"#{current}","generation":2,"report_sequence":1,"kind":"attribute","value":{"tag":"anonymous","type":"i16","value":2200},"metadata":#{metadata}}))
              loop.(loop, current, 2, 1)

            "exhausted" ->
              status.(current, "resubscribing", "lost", 1)
              retired.(current, 1, 0)
              for attempt <- 2..5, do: status.(current, "resubscribing", "lost", attempt)
              IO.puts(~s({"version":1,"event":"subscription_error","session_generation":"#{session_generation}","subscription_id":"#{current}","generation":2,"error":{"code":"session_lost"}}))
              retired.(current, 2, 0)
              loop.(loop, current, 2, 0)
          end

        String.contains?(line, ~s("operation":"unsubscribe")) ->
          [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)
          retired.(subscription_id, generation, last)
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":null}))
          loop.(loop, subscription_id, generation, last)

        String.contains?(line, ~s("operation":"close")) ->
          [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":null}))

        true ->
          System.halt(1)
      end
    end

    loop.(loop, nil, 1, 0)
    '''

    File.write!(path, script)
    File.chmod!(path, 0o700)

    wrapper = temporary_path("recovery-wrapper")

    File.write!(
      wrapper,
      "#!/bin/sh\nWOTEX_MATTER_TEST_AUDIT=#{audit} WOTEX_MATTER_TEST_MODE=#{mode} exec #{path}\n"
    )

    File.chmod!(wrapper, 0o700)

    on_exit(fn ->
      File.rm(path)
      File.rm(wrapper)
      File.rm(audit)
    end)

    wrapper
  end

  defp temporary_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "wotex-matter-p06-#{System.unique_integer([:positive])}-#{suffix}"
    )
  end
end
