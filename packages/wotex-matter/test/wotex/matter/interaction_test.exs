defmodule Wotex.Matter.InteractionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.{Address, AttributeReport, EndpointCatalogue, Error, EventReport}
  alias Wotex.Matter.{Descriptor, Native, TestClient}

  @thermostat %{fabric_id: 1, node_id: 3, endpoint: 1, cluster: 0x0201, member: 0}
  @heating %{@thermostat | member: 0x0012}
  @onoff %{@thermostat | cluster: 0x0006, member: 0}
  @on_command %{@onoff | member: 1}
  @reachable %{@thermostat | endpoint: 2, cluster: 0x0039, member: 3}

  test "named reads and writes retain descriptor values DataVersion and timed options" do
    temperature = %{tag: :anonymous, type: :i16, value: 2150}
    {:ok, address} = Address.new(@thermostat)

    session =
      session(%{path: address, value: temperature, data_version: 0})

    assert {:ok, %AttributeReport{path: ^address, value: ^temperature, data_version: 0}} =
             Matter.read_attribute(session, @thermostat, timeout: 321)

    assert_receive {:matter_request, %{type: :read}, 321}

    write_session = session(%{path: @heating, status: 0})
    value = %{tag: :anonymous, type: :i16, value: 2000}

    assert {:ok, %{path: @heating, status: 0}} =
             Matter.write_attribute(write_session, @heating, value,
               timeout: 600,
               expected_data_version: 0xFFFFFFFF,
               timed_request_timeout_ms: 500
             )

    assert_receive {:matter_request,
                    %{
                      type: :write,
                      value: ^value,
                      expected_data_version: 0xFFFFFFFF,
                      timed_request_timeout_ms: 500
                    }, 600}

    assert {:error, %Error{code: :invalid_tlv, effect: :none}} =
             Matter.write_attribute(write_session, @heating, %{value | tag: {:context, 0}})

    refute_receive {:matter_request, _, _}
  end

  test "WMA-F11 OnOff writes fail locally without entering the client" do
    session = session(:unexpected)
    value = %{tag: :anonymous, type: :boolean, value: true}

    assert {:error, %Error{code: :not_writable, effect: :none}} =
             Matter.write_attribute(session, @onoff, value)

    refute_receive {:matter_request, _, _}
  end

  test "command results distinguish status-only replies and never replay invalid timing" do
    status_only = session(%{path: nil, value: nil, status: 0})
    empty = %{tag: :anonymous, type: :structure, value: []}

    assert {:ok, %{path: nil, value: nil, status: 0}} =
             Matter.invoke_command(status_only, @on_command, empty, timed_request_timeout_ms: 1)

    assert_receive {:matter_request, %{type: :invoke, timed_request_timeout_ms: 1}, 5_000}

    assert {:error, %Error{code: :invalid_options, effect: :none}} =
             Matter.invoke_command(status_only, @on_command, empty,
               timeout: 100,
               timed_request_timeout_ms: 101
             )

    refute_receive {:matter_request, _, _}
  end

  test "event reads preserve number priority timestamp kind and per-path status" do
    {:ok, path} = Address.new(@reachable)

    value = %{
      tag: :anonymous,
      type: :structure,
      value: [%{tag: {:context, 0}, type: :boolean, value: false}]
    }

    event = %{
      path: path,
      value: value,
      event_number: 0xFFFFFFFFFFFFFFFF,
      priority: 2,
      timestamp: %{kind: :epoch, value: 17},
      status: 0
    }

    session = session([%{path: path, result: {:ok, event}}])

    assert {:ok,
            [
              %{
                path: ^path,
                result:
                  {:ok,
                   %EventReport{
                     event_number: 0xFFFFFFFFFFFFFFFF,
                     priority: 2,
                     timestamp: %{kind: :epoch, value: 17}
                   }}
              }
            ]} = Matter.read_events(session, [@reachable], min_event_number: 0)

    assert_receive {:matter_request, %{type: :read_events, min_event_number: 0}, 5_000}
  end

  test "endpoint discovery reads root then each reported endpoint once" do
    assert {:ok, session} =
             Matter.connect(client: Wotex.Matter.CatalogueClient, owner: self(), timeout: 1_000)

    assert {:ok,
            %EndpointCatalogue{
              root_endpoint: 0,
              consistency: :not_atomic,
              endpoints: [
                %{endpoint: 0, parts: {:ok, %{value: [1], data_version: 0}}},
                %{endpoint: 1, parts: {:ok, %{value: [], data_version: 1}}}
              ]
            }} = Matter.discover_endpoints(session, %{fabric_id: 1, node_id: 3})

    assert_receive {:catalogue_request, %{paths: root_paths}, _}
    assert Enum.map(root_paths, & &1.endpoint) == [0, 0, 0, 0]
    assert_receive {:catalogue_request, %{paths: child_paths}, _}
    assert Enum.map(child_paths, & &1.endpoint) == [1, 1, 1, 1]
    refute_receive {:catalogue_request, _, _}
  end

  test "endpoint discovery admits 64 endpoints in bounded batches and rejects 65 locally" do
    parts = Enum.to_list(1..63)

    assert {:ok, session} =
             Matter.connect(
               client: Wotex.Matter.CatalogueClient,
               owner: self(),
               root_parts: parts,
               timeout: 1_000
             )

    assert {:ok, %EndpointCatalogue{endpoints: endpoints}} =
             Matter.discover_endpoints(session, %{fabric_id: 1, node_id: 3})

    assert Enum.map(endpoints, & &1.endpoint) == Enum.to_list(0..63)
    assert_receive {:catalogue_request, %{paths: root}, _}
    assert length(root) == 4

    child_sizes =
      for _ <- 1..4 do
        assert_receive {:catalogue_request, %{paths: paths}, _}
        length(paths)
      end

    assert child_sizes == [64, 64, 64, 60]
    refute_receive {:catalogue_request, _, _}

    assert {:ok, oversized} =
             Matter.connect(
               client: Wotex.Matter.CatalogueClient,
               owner: self(),
               root_parts: Enum.to_list(1..64),
               timeout: 1_000
             )

    assert {:error, %Error{code: :endpoint_limit}} =
             Matter.discover_endpoints(oversized, %{fabric_id: 1, node_id: 3})

    assert_receive {:catalogue_request, %{paths: rejected_root}, _}
    assert length(rejected_root) == 4
    refute_receive {:catalogue_request, _, _}
  end

  test "native wire reconstructs known results without creating atoms from input" do
    result = %{
      "path" => string_path(@thermostat),
      "value" => %{"tag" => "anonymous", "type" => "null", "value" => nil},
      "data_version" => nil
    }

    assert {:ok, %{value: %{type: :null, value: nil}, data_version: nil}} =
             Native.Wire.decode(:read, result)

    assert {:ok, %Error{code: :interaction_status, details: %{status: 126}}} =
             Native.Wire.error(%{
               "code" => "interaction_status",
               "effect" => "none",
               "status" => 126
             })

    assert :error =
             Native.Wire.error(%{"code" => "new-#{System.unique_integer()}", "effect" => "invalid"})
  end

  test "native client transmits and reconstructs a batch read" do
    audit = temporary_path("interaction-audit")
    executable = native_fixture(audit)

    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok,
            [
              %{
                path: %Address{} = path,
                result: {:ok, %AttributeReport{value: %{type: :i16, value: 2150}}}
              }
            ]} = Matter.read_paths(session, [@thermostat], timeout: 800)

    assert Map.from_struct(path) == @thermostat
    assert :ok = Matter.disconnect(session)

    request =
      audit
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.find(&(&1["operation"] == "read_paths"))

    assert request["timeout_ms"] == 800
    assert request["parameters"]["paths"] == [string_path(@thermostat)]
  end

  test "a native deadline expires the generation before a delayed response" do
    audit = temporary_path("late-audit")
    executable = native_fixture(audit, 100)

    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))
    monitor = Process.monitor(session.handle.pid)

    assert {:error, %Error{code: :timeout, effect: :none}} =
             Matter.read_paths(session, [@thermostat], timeout: 10)

    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    assert :ok = Matter.disconnect(session)
  end

  test "WMA-S05 native ACL writes preserve nested context tags and unsigned subjects" do
    audit = temporary_path("acl-audit")
    executable = native_fixture(audit)
    address = %{@onoff | endpoint: 0, cluster: 0x001F}
    entry = %{privilege: 5, auth_mode: 2, subjects: [0xFFFFFFEFFFFFFFFF], targets: nil}
    assert {:ok, value} = Descriptor.to_element(:attribute, address, :write, [entry])
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    try do
      assert {:ok, %{path: ^address, status: 0}} = Matter.write_attribute(session, address, value)
    after
      assert :ok = Matter.disconnect(session)
    end

    request =
      audit
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.find(&(&1["operation"] == "write"))

    assert request["parameters"]["value"] == %{
             "tag" => "anonymous",
             "type" => "array",
             "value" => [
               %{
                 "tag" => "anonymous",
                 "type" => "structure",
                 "value" => [
                   %{"tag" => ["context", 1], "type" => "u8", "value" => 5},
                   %{"tag" => ["context", 2], "type" => "u8", "value" => 2},
                   %{
                     "tag" => ["context", 3],
                     "type" => "array",
                     "value" => [
                       %{"tag" => "anonymous", "type" => "u64", "value" => 0xFFFFFFEFFFFFFFFF}
                     ]
                   },
                   %{"tag" => ["context", 4], "type" => "null", "value" => nil}
                 ]
               }
             ]
           }
  end

  defp session(response) do
    assert {:ok, session} = Matter.connect(client: TestClient, response: response)
    session
  end

  defp string_path(path), do: Map.new(path, fn {key, value} -> {Atom.to_string(key), value} end)

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

  defp native_fixture(audit, delay_ms \\ 0) do
    path = temporary_path("interaction-host")

    script = ~S'''
    #!/usr/bin/env elixir
    audit = System.fetch_env!("WOTEX_MATTER_TEST_AUDIT")
    delay_ms = System.fetch_env!("WOTEX_MATTER_TEST_DELAY") |> String.to_integer()

    read = fn ->
      case IO.read(:stdio, :line) do
        :eof -> System.halt(0)
        {:error, _} -> System.halt(1)
        line -> File.write!(audit, line, [:append]); line
      end
    end

    IO.puts(~s({"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"}))
    read.()
    read.()
    IO.puts(~s({"version":1,"id":"1","ok":true,"result":{"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521}}))

    loop = fn loop ->
      line = read.()
      [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)

      cond do
        String.contains?(line, ~s("operation":"close")) ->
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":null}))

        String.contains?(line, ~s("operation":"write")) ->
          result = ~s({"path":{"fabric_id":1,"node_id":3,"endpoint":0,"cluster":31,"member":0},"status":0})
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":#{result}}))
          loop.(loop)

        String.contains?(line, ~s("operation":"read_paths")) ->
          Process.sleep(delay_ms)
          if delay_ms > 0, do: System.halt(0)
          result = ~s([{"path":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0},"result":{"ok":{"path":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0},"value":{"tag":"anonymous","type":"i16","value":2150},"data_version":0}}}])
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":#{result}}))
          loop.(loop)

        true ->
          IO.puts(~s({"version":1,"id":"#{id}","ok":false,"error":{"code":"not_supported"}}))
          loop.(loop)
      end
    end

    loop.(loop)
    '''

    File.write!(path, script)
    File.chmod!(path, 0o700)

    on_exit(fn ->
      File.rm(path)
      File.rm(audit)
    end)

    wrapper = temporary_path("interaction-wrapper")

    File.write!(
      wrapper,
      "#!/bin/sh\nWOTEX_MATTER_TEST_AUDIT=#{audit} WOTEX_MATTER_TEST_DELAY=#{delay_ms} exec #{path}\n"
    )

    File.chmod!(wrapper, 0o700)

    on_exit(fn -> File.rm(wrapper) end)
    wrapper
  end

  defp temporary_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "wotex-matter-p04-#{System.unique_integer([:positive])}-#{suffix}"
    )
  end
end
