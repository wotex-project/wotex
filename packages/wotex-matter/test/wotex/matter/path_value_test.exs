defmodule Wotex.Matter.PathValueTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter

  alias Wotex.Matter.{
    Address,
    AttributeReport,
    Descriptor,
    EndpointCatalogue,
    Error,
    EventReport,
    PathResults,
    ReadPath,
    TestClient,
    TLV
  }

  @fixture_path Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__)
  @fixture_ids ~w(WMA-F01 WMA-F02 WMA-F03 WMA-F04 WMA-F05 WMA-F06 WMA-F10 WMA-F12)
  @fixtures @fixture_path
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")

  test "WMA-N04 executes the P01 pure corpus cases through their public operations" do
    cases = Map.new(@fixtures, &{Map.fetch!(&1, "id"), &1})

    Enum.each(@fixture_ids, fn id ->
      fixture = Map.fetch!(cases, id)
      assert execute_fixture(fixture) == get_in(fixture, ["expectation", "value"]), id
    end)
  end

  test "WMA-S01 WMA-V01 read paths retain concrete identity and explicit read-only wildcards" do
    base = path(1)

    assert {:ok, %ReadPath{} = concrete} = ReadPath.new(base)
    assert ReadPath.concrete?(concrete)

    for field <- [:endpoint, :cluster, :member] do
      assert {:ok, %ReadPath{} = wildcard} = ReadPath.new(Map.put(base, field, :any))
      refute ReadPath.concrete?(wildcard)
    end

    for invalid <- [
          Map.put(base, :fabric_id, :any),
          Map.put(base, :node_id, :any),
          Map.put(base, :endpoint, nil),
          Map.put(base, :cluster, 0x8000),
          Map.put(base, :member, 0xFFFFFFFF),
          Map.put(base, :extra, true),
          nil
        ] do
      assert {:error, %Error{code: :invalid_path, effect: :none}} = ReadPath.new(invalid)
    end

    assert {:error, %Error{code: :invalid_path}} =
             ReadPath.new(%ReadPath{concrete | endpoint: 0xFFFF})

    assert ReadPath.matches?(%ReadPath{concrete | endpoint: :any}, address(55))
    refute ReadPath.matches?(concrete, address(2))
  end

  test "WMA-S01 concrete messages accept exact operation fields and preserve explicit null" do
    read = Map.put(path(1), :type, :read)
    write = Map.put(Map.put(read, :type, :write), :value, nil)
    timed = Map.put(write, :timed_request_timeout_ms, 65_535)

    assert :ok = Address.validate_message(read)
    assert :ok = Address.validate_message(write)
    assert :ok = Address.validate_message(timed)

    assert {:error, %Error{code: :missing_value}} =
             Address.validate_message(Map.delete(%{write | value: nil}, :value))

    for invalid <- [
          Map.put(read, :extra, true),
          Map.put(write, :extra, true),
          %{read | type: :read_paths},
          %{read | endpoint: :any},
          Map.put(read, :timed_request_timeout_ms, 1),
          Map.put(write, :timed_request_timeout_ms, 65_536)
        ] do
      assert {:error, %Error{effect: :none}} = Address.validate_message(invalid)
    end
  end

  test "WMA-S01 manufacturer cluster identifiers use the pinned SDK MEI suffix range" do
    valid = [0, 0x7FFF, 0x0001FC00, 0x0001FFFE, 0xFFF1FC05, 0xFFF4FFFE]
    descriptor = %{path(1) | cluster: 0x001D, member: 1}

    for cluster <- valid do
      assert {:ok, %Address{cluster: ^cluster}} = Address.new(%{path(1) | cluster: cluster})
      assert {:ok, %ReadPath{cluster: ^cluster}} = ReadPath.new(%{path(1) | cluster: cluster})
    end

    assert {:ok, element} = Descriptor.to_element(:attribute, descriptor, :read, valid)
    assert {:ok, ^valid} = Descriptor.from_element(:attribute, descriptor, :read, element)

    for cluster <- [
          0x8000,
          0xFC00,
          0xFFFF,
          0x10000,
          0x1FBFF,
          0x1FFFF,
          0xFFF50000,
          0xFFF5FC00,
          0xFFFFFFFF
        ] do
      assert {:error, %Error{code: :invalid_path}} = Address.new(%{path(1) | cluster: cluster})
      assert {:error, %Error{code: :invalid_path}} = ReadPath.new(%{path(1) | cluster: cluster})
      assert {:error, %Error{}} = Descriptor.to_element(:attribute, descriptor, :read, [cluster])
    end
  end

  test "WMA-S01 WMA-S03 WMA-V05 batch reads retain per-path status and deterministic order" do
    requested = [path(2), %{path(1) | endpoint: :any}]
    denied = Error.new(:unsupported_path, :member, %{status: 134})

    response = [
      error_result(address(3), denied),
      ok_result(address(1), %{tag: :anonymous, type: :boolean, value: false}, nil),
      ok_result(address(2), %{tag: :anonymous, type: :boolean, value: true}, 0)
    ]

    handler = {__MODULE__, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler,
        [:wotex, :matter, :request, :stop],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, session} = Matter.connect(client: TestClient, response: response)
    assert {:ok, results} = Matter.read_paths(session, requested, timeout: 123)

    assert [
             %{path: %{endpoint: 2}, result: {:ok, %AttributeReport{data_version: 0}}},
             %{path: %{endpoint: 1}, result: {:ok, %AttributeReport{data_version: nil}}},
             %{path: %{endpoint: 3}, result: {:error, ^denied}}
           ] = results

    assert_receive {:matter_request, %{type: :read_paths, paths: paths}, 123}
    assert Enum.map(paths, & &1.endpoint) == [2, :any]

    assert_receive {:telemetry, [:wotex, :matter, :request, :stop], %{duration: duration},
                    %{operation: :read_paths, result: :ok}}

    assert is_integer(duration) and duration >= 0
    assert :ok = Matter.disconnect(session)
  end

  test "WMA-S01 WMA-V01 batch replies reject duplicates omissions foreign paths and malformed reports" do
    requested = [path(1)]
    valid = ok_result(address(1), %{tag: :anonymous, type: :u8, value: 1}, nil)

    malformed = [
      [valid, valid],
      [],
      [ok_result(address(2), %{tag: :anonymous, type: :u8, value: 1}, nil)],
      [Map.put(valid, :extra, true)],
      [ok_result(address(1), %{tag: {:context, 1}, type: :u8, value: 1}, nil)],
      [error_result(address(1), %Error{Error.new(:remote_error) | field: "member"})],
      [error_result(address(1), %Error{Error.new(:remote_error) | class: :invalid})],
      [error_result(address(1), %Error{Error.new(:remote_error) | effect: :unknown})],
      [error_result(address(1), Error.new(:remote_error, nil, %{value: :binary.copy("x", 5000)}))]
    ]

    Enum.each(malformed, fn response ->
      assert {:ok, session} = Matter.connect(client: TestClient, response: response)

      assert {:error, %Error{code: :invalid_transport_return}} =
               Matter.read_paths(session, requested)

      assert :ok = Matter.disconnect(session)
    end)
  end

  test "WMA-S01 aggregate result and request limits fail without partial success" do
    wildcard = %{path(0) | endpoint: :any}
    value = %{tag: :anonymous, type: :bytes, value: :binary.copy(<<0>>, 2000)}
    response = Enum.map(0..63, &ok_result(address(&1), value, nil))

    assert {:ok, session} = Matter.connect(client: TestClient, response: response)

    assert {:error, %Error{code: :response_limit, effect: :none}} =
             Matter.read_paths(session, [wildcard])

    assert_receive {:matter_request, %{type: :read_paths}, 5000}
    assert :ok = Matter.disconnect(session)

    assert {:ok, session} = Matter.connect(client: TestClient, response: [])

    for invalid <- [[], List.duplicate(path(1), 65)] do
      assert {:error, %Error{code: :invalid_path_batch, effect: :none}} =
               Matter.read_paths(session, invalid)
    end

    assert {:error, %Error{}} = Matter.read_paths(session, [nil])

    for invalid <- [[timeout: 0], [timeout: 1, timeout: 2], [unknown: true], nil] do
      assert {:error, %Error{code: :invalid_options, effect: :none}} =
               Matter.read_paths(session, [path(1)], invalid)
    end

    refute_received {:matter_request, _, _}
    assert :ok = Matter.disconnect(session)
  end

  test "WMA-C02 batch normalization rejects malformed caller and result envelopes" do
    assert {:error, %Error{code: :invalid_transport_return}} = PathResults.normalize(nil, nil)
    assert {:ok, requested} = ReadPath.new(path(1))

    assert {:error, %Error{code: :invalid_transport_return}} =
             PathResults.normalize([requested], [%{path: address(1), result: :invalid}])

    assert {:error, %Error{code: :invalid_tlv}} = TLV.decode(nil)
  end

  test "WMA-S01 WMA-N02 descriptors convert only admitted numeric recipes" do
    assert {:ok, %{tag: :anonymous, type: :null, value: nil}} =
             Descriptor.to_element(:attribute, path(1, 0x0201, 0x0000), :read, nil)

    assert {:ok, %{type: :i16, value: 2150}} =
             Descriptor.to_element(:attribute, path(1, 0x0201, 0x0000), :read, 2150)

    assert {:ok, %{type: :i16, value: 2000}} =
             Descriptor.to_element(:attribute, path(1, 0x0201, 0x0012), :write, 2000)

    assert {:ok, %{type: :u8, value: 4}} =
             Descriptor.to_element(:attribute, path(1, 0x0201, 0x001C), :write, 4)

    assert {:ok, %{type: :boolean, value: false}} =
             Descriptor.to_element(:attribute, path(1, 0x0006, 0x0000), :read, false)

    assert {:ok, %{type: :structure, value: []}} =
             Descriptor.to_element(:command, path(1, 0x0006, 0x0001), :invoke, %{})

    assert {:ok, %{type: :array, value: [%{type: :u32, value: 6}]}} =
             Descriptor.to_element(:attribute, path(0, 0x001D, 0x0001), :read, [6])

    assert {:ok, %{type: :array, value: [%{type: :structure}]}} =
             Descriptor.to_element(
               :attribute,
               path(0, 0x001D, 0x0000),
               :read,
               [%{device_type: 256, revision: 2}]
             )

    assert {:ok, %{type: :structure, value: [%{type: :boolean, value: true}]}} =
             Descriptor.to_element(:event, path(1, 0x0039, 0x0003), :read, %{reachable: true})

    assert {:error, %Error{code: :not_writable}} =
             Descriptor.validate_element(
               :attribute,
               path(1, 0x0006, 0x0000),
               :write,
               %{tag: :anonymous, type: :boolean, value: true}
             )

    for {address, value} <- [
          {path(1, 0x0201, 0x0000), 32_768},
          {path(1, 0x0201, 0x001C), 256},
          {path(1, 0x0006, 0x0000), 1}
        ] do
      assert {:error, %Error{code: :invalid_value}} =
               Descriptor.to_element(:attribute, address, :read, value)
    end

    assert {:error, %Error{code: :unsupported_schema}} =
             Descriptor.to_element(:attribute, path(1, 0x0006, 99), :read, false)
  end

  test "WMA-S01 WMA-N02 descriptor validation enforces every admitted P01 schema" do
    cases = [
      {:attribute, path(1, 0x0201, 0x0000), :read, %{tag: :anonymous, type: :null, value: nil}},
      {:attribute, path(1, 0x0201, 0x0011), :write, %{tag: :anonymous, type: :i16, value: -32_768}},
      {:attribute, path(1, 0x0201, 0x001C), :read, %{tag: :anonymous, type: :u8, value: 255}},
      {:attribute, path(1, 0x0006, 0x0000), :read,
       %{tag: :anonymous, type: :boolean, value: false}},
      {:command, path(1, 0x0006, 0x0002), :invoke, %{tag: :anonymous, type: :structure, value: []}},
      {:attribute, path(0, 0x001D, 0x0001), :read,
       %{
         tag: :anonymous,
         type: :array,
         value: [%{tag: :anonymous, type: :u32, value: 6}]
       }},
      {:attribute, path(0, 0x001D, 0x0003), :read,
       %{
         tag: :anonymous,
         type: :array,
         value: [%{tag: :anonymous, type: :u16, value: 1}]
       }},
      {:attribute, path(0, 0x001D, 0x0000), :read,
       %{
         tag: :anonymous,
         type: :array,
         value: [
           %{
             tag: :anonymous,
             type: :structure,
             value: [
               %{tag: {:context, 0}, type: :u32, value: 256},
               %{tag: {:context, 1}, type: :u16, value: 2}
             ]
           }
         ]
       }},
      {:event, path(1, 0x0039, 0x0003), :subscribe,
       %{
         tag: :anonymous,
         type: :structure,
         value: [%{tag: {:context, 0}, type: :boolean, value: true}]
       }}
    ]

    Enum.each(cases, fn {kind, member_path, operation, element} ->
      assert {:ok, ^element} = Descriptor.validate_element(kind, member_path, operation, element)
    end)

    assert {:error, %Error{code: :unsupported_operation}} =
             Descriptor.lookup(:command, path(1, 0x0006, 0x0000), :read)

    assert {:error, %Error{code: :unsupported_schema}} =
             Descriptor.lookup(:unknown, path(1), :read)

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.validate_element(
               :attribute,
               path(1, 0x0006, 0x0000),
               :read,
               %{tag: :anonymous, type: :u8, value: 1}
             )

    assert {:error, %Error{code: :invalid_tlv}} =
             Descriptor.validate_element(
               :attribute,
               path(1, 0x0201, 0x0012),
               :write,
               %{tag: {:context, 0}, type: :i16, value: 2000}
             )

    assert {:error, %Error{code: :invalid_tlv}} =
             Descriptor.validate_element(
               :attribute,
               path(1, 0x0006, 0x0000),
               :read,
               %{tag: :anonymous, type: :boolean, value: true, extra: true}
             )

    assert {:ok, %{type: :array, value: [%{type: :u16, value: 0xFFFE}]}} =
             Descriptor.to_element(:attribute, path(0, 0x001D, 0x0003), :read, [0xFFFE])

    for {member, value} <- [
          {0x0000, [%{device_type: 256}]},
          {0x0001, [:not_a_cluster]},
          {0x0001, [0x8000]},
          {0x0003, List.duplicate(0, 1024)}
        ] do
      assert {:error, %Error{code: :invalid_value}} =
               Descriptor.to_element(:attribute, path(0, 0x001D, member), :read, value)
    end

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.to_element(
               :event,
               path(1, 0x0039, 0x0003),
               :read,
               %{reachable: 1}
             )
  end

  test "WMA-S03 report values retain null version event identity and timestamp kind" do
    value = %{tag: :anonymous, type: :null, value: nil}

    assert {:ok, %AttributeReport{data_version: nil, value: ^value}} =
             AttributeReport.new(%{path: path(1), value: value, data_version: nil})

    assert {:ok, %EventReport{event_number: 0, priority: 255, status: 0}} =
             EventReport.new(%{
               path: path(1, 0x0039, 0x0003),
               value: %{tag: :anonymous, type: :structure, value: []},
               event_number: 0,
               priority: 255,
               timestamp: %{kind: :system, value: 0},
               status: 0
             })

    event = %{
      path: path(1, 0x0039, 0x0003),
      value: value,
      event_number: 1,
      priority: 1,
      timestamp: %{kind: 7, value: 10},
      status: 0
    }

    assert {:error, %Error{code: :unsupported_timestamp, field: :timestamp, details: %{kind: 7}}} =
             EventReport.new(event)

    for invalid <- [
          %{path: path(1), value: value, data_version: 0x1_0000_0000},
          %{path: path(1), value: %{value | tag: {:context, 1}}, data_version: 0},
          %{path: path(1), value: value, data_version: 0, extra: true}
        ] do
      assert {:error, %Error{code: :invalid_attribute_report}} = AttributeReport.new(invalid)
    end

    assert {:error, %Error{code: :invalid_event_report}} =
             EventReport.new(%{event | timestamp: %{kind: :unknown, value: 10}})

    assert {:ok, %AttributeReport{} = attribute} =
             AttributeReport.new(%{path: path(1), value: value, data_version: 0})

    assert {:ok, ^attribute} = AttributeReport.new(attribute)

    assert {:ok, %EventReport{} = event_report} =
             EventReport.new(%{event | timestamp: %{kind: :epoch, value: 10}})

    assert {:ok, ^event_report} = EventReport.new(event_report)
    assert {:error, %Error{code: :invalid_event_report}} = EventReport.new(nil)
  end

  test "WMA-N01 endpoint catalogues sort entries and retain versioned descriptor failures" do
    denied = Error.new(:unsupported_path, :member, %{status: 134})

    root = endpoint(0, parts: versioned([1], 10))

    child =
      endpoint(1,
        device_types: versioned([%{device_type: 256, revision: 2}], 11),
        server_clusters: versioned([0x0006, 0x0402], 12),
        client_clusters: {:error, denied}
      )

    assert {:ok, %EndpointCatalogue{} = catalogue} =
             EndpointCatalogue.new(%{fabric_id: 1, node_id: 2, endpoints: [child, root]})

    assert catalogue.root_endpoint == 0
    assert catalogue.consistency == :not_atomic
    assert Enum.map(catalogue.endpoints, & &1.endpoint) == [0, 1]
    assert get_in(catalogue.endpoints, [Access.at(1), :client_clusters]) == {:error, denied}
  end

  test "WMA-N01 endpoint catalogues reject malformed graphs and aggregate overflow" do
    root = endpoint(0, parts: versioned([1], nil))
    child = endpoint(1)

    too_many_clusters =
      [
        endpoint(0,
          parts: versioned([1], nil),
          server_clusters: versioned(List.duplicate(6, 600), nil)
        ),
        endpoint(1, client_clusters: versioned(List.duplicate(6, 425), nil))
      ]

    invalid = [
      [],
      [child],
      [root, root],
      [endpoint(0, parts: versioned([1, 1], nil)), child],
      [endpoint(0, parts: versioned([2], nil)), child],
      [root, endpoint(1, parts: versioned([0], nil))],
      [endpoint(0, server_clusters: versioned([0x8000], nil))],
      [Map.put(endpoint(0), :extra, true)],
      [endpoint(0, device_types: {:error, %Error{Error.new(:failed) | effect: :unknown}})],
      [endpoint(0, device_types: {:error, %Error{Error.new(:failed) | class: :invalid}})],
      too_many_clusters,
      Enum.map(0..64, &endpoint/1)
    ]

    Enum.each(invalid, fn endpoints ->
      assert {:error, %Error{code: :invalid_endpoint_catalogue, effect: :none}} =
               EndpointCatalogue.new(%{fabric_id: 1, node_id: 2, endpoints: endpoints})
    end)
  end

  test "WMA-N01 endpoint catalogue inputs retain failures and reject malformed descriptor values" do
    unavailable = Error.new(:unsupported_path)

    full = %{
      fabric_id: 1,
      node_id: 2,
      root_endpoint: 0,
      consistency: :not_atomic,
      endpoints: [endpoint(0, parts: {:error, unavailable})]
    }

    assert {:ok, %EndpointCatalogue{} = catalogue} = EndpointCatalogue.new(full)
    assert {:ok, ^catalogue} = EndpointCatalogue.new(catalogue)

    invalid = [
      nil,
      %{fabric_id: 1, node_id: 2, endpoints: :not_a_list},
      %{fabric_id: 1, node_id: 2, endpoints: [endpoint(0, device_types: :invalid)]},
      %{
        fabric_id: 1,
        node_id: 2,
        endpoints: [endpoint(0, device_types: versioned(:not_a_list, nil))]
      },
      %{
        fabric_id: 1,
        node_id: 2,
        endpoints: [
          endpoint(0,
            device_types: versioned([%{device_type: :invalid, revision: 1}], nil)
          )
        ]
      },
      %{
        fabric_id: 1,
        node_id: 2,
        endpoints: [endpoint(0, server_clusters: versioned([:invalid], nil))]
      },
      %{
        fabric_id: 1,
        node_id: 2,
        endpoints: [endpoint(0, parts: versioned([:invalid], nil))]
      },
      %{
        fabric_id: 1,
        node_id: 2,
        endpoints: [
          endpoint(0,
            device_types: {:error, Error.new(:failed, nil, %{unencodable: self()})}
          )
        ]
      },
      %{
        fabric_id: 1,
        node_id: 2,
        root_endpoint: 1,
        consistency: :not_atomic,
        endpoints: [endpoint(0)]
      }
    ]

    Enum.each(invalid, fn input ->
      assert {:error, %Error{code: :invalid_endpoint_catalogue}} = EndpointCatalogue.new(input)
    end)
  end

  defp execute_fixture(%{"operation" => "TLV.decode", "input" => %{"bytes_hex" => hex}}) do
    hex
    |> Base.decode16!(case: :mixed)
    |> TLV.decode()
    |> project_result()
  end

  defp execute_fixture(%{"operation" => "TLV.encode", "input" => %{"elements" => elements}}) do
    elements
    |> Enum.map(&fixture_element/1)
    |> TLV.encode()
    |> project_result()
  end

  defp execute_fixture(%{"operation" => "Address.new", "input" => %{"value" => value}}) do
    value
    |> Map.new(fn {key, value} -> {path_field(key), value} end)
    |> Address.new()
    |> project_result()
  end

  defp fixture_element(%{"tag" => tag, "type" => type, "value" => value}) do
    %{tag: fixture_tag(tag), type: fixture_type(type), value: fixture_value(type, value)}
  end

  defp fixture_value(type, values) when type in ["structure", "array", "list"],
    do: Enum.map(values, &fixture_element/1)

  defp fixture_value(_, value), do: value

  defp fixture_tag("anonymous"), do: :anonymous
  defp fixture_tag(["context", id]), do: {:context, id}
  defp fixture_type("boolean"), do: :boolean
  defp fixture_type("null"), do: :null
  defp fixture_type("i16"), do: :i16
  defp fixture_type("structure"), do: :structure

  defp project_result({:ok, bytes}) when is_binary(bytes),
    do: %{"ok" => %{"bytes_hex" => Base.encode16(bytes, case: :lower)}}

  defp project_result({:ok, values}) when is_list(values),
    do: %{"ok" => Enum.map(values, &project_element/1)}

  defp project_result({:error, %Error{} = error}),
    do: %{
      "error" => %{"code" => Atom.to_string(error.code), "effect" => Atom.to_string(error.effect)}
    }

  defp project_element(%{tag: tag, type: type, value: value}) do
    %{
      "tag" => project_tag(tag),
      "type" => Atom.to_string(type),
      "value" => project_value(type, value)
    }
  end

  defp project_value(type, values) when type in [:structure, :array, :list],
    do: Enum.map(values, &project_element/1)

  defp project_value(_, value), do: value

  defp project_tag(:anonymous), do: "anonymous"
  defp project_tag({:context, id}), do: ["context", id]

  defp path_field("fabric_id"), do: :fabric_id
  defp path_field("node_id"), do: :node_id
  defp path_field("endpoint"), do: :endpoint
  defp path_field("cluster"), do: :cluster
  defp path_field("member"), do: :member

  defp path(endpoint, cluster \\ 6, member \\ 0),
    do: %{fabric_id: 1, node_id: 2, endpoint: endpoint, cluster: cluster, member: member}

  defp address(endpoint) do
    {:ok, address} = Address.new(path(endpoint))
    address
  end

  defp ok_result(address, value, version) do
    %{
      path: address,
      result: {:ok, %{path: address, value: value, data_version: version}}
    }
  end

  defp error_result(address, error), do: %{path: address, result: {:error, error}}
  defp versioned(value, version), do: {:ok, %{value: value, data_version: version}}

  defp endpoint(id, overrides \\ []) do
    Map.merge(
      %{
        endpoint: id,
        device_types: versioned([], nil),
        server_clusters: versioned([], nil),
        client_clusters: versioned([], nil),
        parts: versioned([], nil)
      },
      Map.new(overrides)
    )
  end
end
