defmodule Wotex.Matter.StandaloneBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.{Address, EndpointCatalogue, Error, TestClient}

  @heating %{fabric_id: 1, node_id: 3, endpoint: 1, cluster: 0x0201, member: 0x12}
  @on %{fabric_id: 1, node_id: 3, endpoint: 1, cluster: 6, member: 1}
  @event %{fabric_id: 1, node_id: 3, endpoint: 2, cluster: 0x0039, member: 3}
  @value %{tag: :anonymous, type: :i16, value: 0}
  @empty %{tag: :anonymous, type: :structure, value: []}

  test "WMA-C02 named operations reject missing sessions with structured failures" do
    for result <- [
          Matter.read_attribute(nil, @heating),
          Matter.write_attribute(nil, @heating, @value),
          Matter.invoke_command(nil, @on, @empty),
          Matter.read_events(nil, [@event]),
          Matter.discover_endpoints(nil, %{fabric_id: 1, node_id: 3}),
          Matter.subscribe(nil, %{})
        ] do
      assert {:error, %Error{code: :invalid_message, effect: :none}} = result
    end

    assert {:error, %Error{code: :invalid_commissioning_request}} =
             Matter.commission_on_network(nil, %{})

    assert {:error, %Error{code: :invalid_commissioning_window}} =
             Matter.open_commissioning_window(nil, %{})

    assert {:error, %Error{code: :invalid_handle}} = Matter.unsubscribe(nil, nil)
  end

  test "WMA-C02 invalid deadlines mutation versions and event bounds acquire no request" do
    session = session(:unexpected)

    for options <- [
          nil,
          %{},
          [timeout: 0],
          [timeout: 60_001],
          [timeout: :infinity],
          [timeout: 1, timeout: 2],
          [unknown: 1]
        ] do
      assert {:error, %Error{code: :invalid_options}} =
               Matter.read_attribute(session, @heating, options)

      assert {:error, %Error{code: :invalid_options}} =
               Matter.write_attribute(session, @heating, @value, options)

      assert {:error, %Error{code: :invalid_options}} =
               Matter.read_events(session, [@event], options)

      assert {:error, %Error{code: :invalid_options}} =
               Matter.discover_endpoints(session, %{fabric_id: 1, node_id: 3}, options)
    end

    for version <- [-1, 0x100000000, nil, "0"] do
      assert {:error, %Error{code: :invalid_options}} =
               Matter.write_attribute(session, @heating, @value, expected_data_version: version)
    end

    for number <- [-1, 0x10000000000000000, "0"] do
      assert {:error, %Error{code: :invalid_options}} =
               Matter.read_events(session, [@event], min_event_number: number)
    end

    for paths <- [nil, [], List.duplicate(@event, 65)] do
      assert {:error, %Error{code: :invalid_path_batch}} = Matter.read_events(session, paths)
    end

    for maximum <- [0, 65, nil] do
      assert {:error, %Error{code: :invalid_options}} =
               Matter.discover_endpoints(session, %{fabric_id: 1, node_id: 3},
                 max_endpoints: maximum
               )
    end

    for node <- [nil, %{fabric_id: 1, node_id: 0}, %{fabric_id: 1, node_id: 3, extra: true}] do
      assert {:error, %Error{code: :invalid_path}} = Matter.discover_endpoints(session, node)
    end

    refute_receive {:matter_request, _, _}
  end

  test "WMA-C02 malformed keyword lists fail before any client request" do
    session = session(:unexpected)

    for options <- [[false], ["timeout"], [{:timeout, 100}, :untrusted]] do
      assert {:error, %Error{code: :invalid_options}} =
               Matter.read_attribute(session, @heating, options)

      assert {:error, %Error{code: :invalid_options}} =
               Matter.write_attribute(session, @heating, @value, options)

      assert {:error, %Error{code: :invalid_options}} =
               Matter.invoke_command(session, @on, @empty, options)

      assert {:error, %Error{code: :invalid_options}} =
               Matter.read_events(session, [@event], options)

      assert {:error, %Error{code: :invalid_options}} =
               Matter.discover_endpoints(session, %{fabric_id: 1, node_id: 3}, options)
    end

    refute_receive {:matter_request, _, _}
  end

  test "WMA-C02 malformed event entries return errors instead of raising" do
    for entry <- [
          nil,
          false,
          %{},
          %{path: nil},
          %{path: %{}, result: :untrusted},
          %{path: @event, result: :untrusted, extra: true}
        ] do
      assert {:error, %Error{code: :invalid_transport_return}} =
               Matter.read_events(session([entry]), [@event])
    end

    result = %{path: @event, result: {:error, Error.new(:interaction_status)}}
    assert {:ok, typed_path} = Address.new(@event)

    assert {:error, %Error{code: :invalid_transport_return}} =
             Matter.read_events(session([result, %{result | path: typed_path}]), [
               @event,
               %{@event | node_id: 4}
             ])
  end

  test "WMA-S01 a named read retains the requested path and descriptor" do
    for report <- [
          %{path: %{@heating | node_id: 4}, value: @value, data_version: 0},
          %{
            path: @heating,
            value: %{tag: :anonymous, type: :boolean, value: false},
            data_version: 0
          }
        ] do
      assert {:error, %Error{code: :invalid_transport_return, effect: :none}} =
               Matter.read_attribute(session(report), @heating)

      assert_receive {:matter_request, %{type: :read}, _}
    end
  end

  test "WMA-C02 malformed mutation acknowledgments cannot become successful values" do
    for result <- [
          nil,
          false,
          %{},
          %{path: @heating, status: 1},
          %{path: %{@heating | node_id: 4}, status: 0}
        ] do
      assert {:error, %Error{code: :invalid_transport_return}} =
               Matter.write_attribute(session(result), @heating, @value)

      assert_receive {:matter_request, %{type: :write}, _}
    end

    for result <- [
          nil,
          false,
          %{},
          %{path: nil, value: @empty, status: 0},
          %{path: @on, value: nil, status: 0}
        ] do
      assert {:error, %Error{code: :invalid_transport_return}} =
               Matter.invoke_command(session(result), @on, @empty)

      assert_receive {:matter_request, %{type: :invoke}, _}
    end

    result = %{path: @on, value: @empty, status: 0}
    assert {:ok, ^result} = Matter.invoke_command(session(result), @on, @empty)
    assert_receive {:matter_request, %{type: :invoke}, _}
    refute_receive {:matter_request, _, _}
  end

  test "WMA-C04 event batches preserve explicit per-path errors and reject ambiguous results" do
    error = Error.new(:interaction_status, nil, %{status: 0x7E})
    result = %{path: @event, result: {:error, error}}
    assert {:ok, path} = Address.new(@event)

    assert {:ok, [%{path: ^path, result: {:error, ^error}}]} =
             Matter.read_events(session([result]), [@event])

    assert_receive {:matter_request, %{type: :read_events}, _}

    for response <- [
          nil,
          [],
          [result, result],
          [%{result | path: %{@event | node_id: 4}}],
          [%{result | result: {:error, Error.with_effect(error, :unknown)}}],
          [%{result | result: :unexpected}]
        ] do
      assert {:error, %Error{code: :invalid_transport_return}} =
               Matter.read_events(session(response), [@event])

      assert_receive {:matter_request, %{type: :read_events}, _}
    end
  end

  test "WMA-S03 root-only discovery does not invent endpoints or retry duplicated parts" do
    assert {:ok, root_only} =
             Matter.connect(client: Wotex.Matter.CatalogueClient, owner: self(), root_parts: [])

    assert {:ok, %EndpointCatalogue{endpoints: [%{endpoint: 0}]}} =
             Matter.discover_endpoints(root_only, %{fabric_id: 1, node_id: 3})

    assert_receive {:catalogue_request, %{paths: paths}, _}
    assert length(paths) == 4
    refute_receive {:catalogue_request, _, _}

    assert {:ok, duplicate} =
             Matter.connect(client: Wotex.Matter.CatalogueClient, owner: self(), root_parts: [1, 1])

    assert {:error, %Error{code: :invalid_endpoint_catalogue}} =
             Matter.discover_endpoints(duplicate, %{fabric_id: 1, node_id: 3})

    assert_receive {:catalogue_request, _, _}
    refute_receive {:catalogue_request, _, _}

    error = Error.new(:session_lost)

    assert {:error, ^error} =
             Matter.discover_endpoints(session({:error, error}), %{fabric_id: 1, node_id: 3})

    assert_receive {:matter_request, %{type: :read_paths}, _}
    refute_receive {:matter_request, _, _}
  end

  defp session(response) do
    {:ok, session} = Matter.connect(client: TestClient, response: response)
    session
  end
end
