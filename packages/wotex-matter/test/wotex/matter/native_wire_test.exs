defmodule Wotex.Matter.NativeWireTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.{Address, Error, Native.Wire}

  @path %{"fabric_id" => 1, "node_id" => 2, "endpoint" => 1, "cluster" => 6, "member" => 0}
  @typed_path %{fabric_id: 1, node_id: 2, endpoint: 1, cluster: 6, member: 0}

  test "WMA-S01 result paths enforce concrete identifier widths and reserved values" do
    for {key, value} <- [
          {"fabric_id", 0xFFFFFFFFFFFFFFFF},
          {"node_id", 0xFFFFFFEFFFFFFFFF},
          {"endpoint", 0},
          {"endpoint", 0xFFFE},
          {"cluster", 0},
          {"cluster", 0x7FFF},
          {"cluster", 0x0001FC00},
          {"cluster", 0xFFF4FFFE},
          {"member", 0xFFFFFFFE}
        ] do
      path = Map.put(@path, key, value)
      expected = Map.put(@typed_path, String.to_existing_atom(key), value)

      for {operation, result} <- path_envelopes(path) do
        assert {:ok, decoded} = Wire.decode(operation, result)
        actual = if is_list(decoded), do: hd(decoded).path, else: decoded.path
        assert actual == expected
      end
    end

    for {key, value} <- [
          {"fabric_id", 0},
          {"fabric_id", 0x10000000000000000},
          {"node_id", 0},
          {"node_id", 0xFFFFFFF000000000},
          {"endpoint", -1},
          {"endpoint", 0xFFFF},
          {"cluster", 0x8000},
          {"cluster", 0x0001FBFF},
          {"cluster", 0xFFF4FFFF},
          {"cluster", 0xFFF5FC00},
          {"member", 0xFFFFFFFF},
          {"member", "any"},
          {"member", 0.0}
        ],
        {operation, result} <- path_envelopes(Map.put(@path, key, value)) do
      assert_invalid(Wire.decode(operation, result))
    end
  end

  test "WMA-C02 retains typed integer boundaries, null, false and empty containers" do
    for {name, type, values} <- [
          {"null", :null, [nil]},
          {"boolean", :boolean, [false, true]},
          {"i16", :i16, [-32_768, 0, 32_767]},
          {"u8", :u8, [0, 255]},
          {"u16", :u16, [0, 65_535]},
          {"u32", :u32, [0, 0xFFFFFFFF]},
          {"u64", :u64, [0, 0xFFFFFFFFFFFFFFFF]},
          {"structure", :structure, [[]]},
          {"array", :array, [[]]}
        ],
        value <- values,
        version <- [nil, 0, 0xFFFFFFFF] do
      assert {:ok, %{path: @typed_path, value: typed, data_version: ^version}} =
               Wire.decode(:read, attribute(element(name, value), version))

      assert typed == %{tag: :anonymous, type: type, value: value}
    end

    children = [
      element("u64", 0xFFFFFFFFFFFFFFFF, ["context", 0]),
      element("null", nil, ["context", 255])
    ]

    assert {:ok, %{value: %{tag: :anonymous, type: :structure, value: typed}}} =
             Wire.decode(:read, attribute(element("structure", children)))

    assert typed == [
             %{tag: {:context, 0}, type: :u64, value: 0xFFFFFFFFFFFFFFFF},
             %{tag: {:context, 255}, type: :null, value: nil}
           ]
  end

  test "WMA-C02 rejects malformed tags, unknown types and integers outside their widths" do
    invalid = [
      element("i16", -32_769),
      element("i16", 32_768),
      element("u8", 256),
      element("u16", 65_536),
      element("u32", 0x100000000),
      element("u64", 0x10000000000000000),
      element("u64", -1),
      element("u64", 1.0),
      element("boolean", 0),
      element("null", false),
      element("array", %{}),
      element("structure", [element("u8", 256)]),
      element("untrusted-type-canary", 0),
      element("u8", 0, ["context", -1]),
      element("u8", 0, ["context", 256]),
      element("u8", 0, ["context", 1, 2]),
      element("u8", 0, "profile"),
      Map.put(element("u8", 0), "extra", true),
      %{}
    ]

    for value <- invalid do
      assert_invalid(Wire.decode(:read, attribute(value)))
    end

    for report <- [
          attribute(element("u8", 0), -1),
          attribute(element("u8", 0), 0x100000000),
          attribute(element("u8", 0), "0"),
          Map.put(attribute(element("u8", 0)), "extra", 0),
          Map.put(attribute(element("u8", 0)), "path", Map.delete(@path, "node_id")),
          Map.put(
            attribute(element("u8", 0)),
            "path",
            Map.put(Map.delete(@path, "node_id"), "node", 2)
          ),
          nil
        ] do
      assert_invalid(Wire.decode(:read, report))
    end
  end

  test "WMA-C02 distinguishes successful mutations from malformed success envelopes" do
    assert {:ok, %{path: @typed_path, status: 0}} =
             Wire.decode(:write, %{"path" => @path, "status" => 0})

    assert {:ok, %{path: nil, value: nil, status: 0}} =
             Wire.decode(:invoke, %{"path" => nil, "value" => nil, "status" => 0})

    assert {:ok, %{path: @typed_path, value: %{value: false}, status: 0}} =
             Wire.decode(:invoke, %{
               "path" => @path,
               "value" => element("boolean", false),
               "status" => 0
             })

    for {operation, result} <- [
          {:write, %{"path" => @path, "status" => 1}},
          {:write, %{"path" => @path, "status" => 0, "value" => nil}},
          {:invoke, %{"path" => @path, "value" => nil, "status" => 1}},
          {:invoke, %{"path" => false, "value" => nil, "status" => 0}},
          {:invoke, %{"path" => nil, "value" => false, "status" => 0}},
          {:unknown, %{}}
        ] do
      assert_invalid(Wire.decode(operation, result))
    end
  end

  test "WMA-C02 batch results preserve order, per-path failures and response identity" do
    success = %{"path" => @path, "result" => %{"ok" => attribute(element("boolean", false))}}

    failure = %{
      "path" => @path,
      "result" => %{"error" => %{"code" => "interaction_status", "status" => 0x7E}}
    }

    assert {:ok, [first, second]} = Wire.decode(:read_paths, [success, failure])
    assert %{path: @typed_path, result: {:ok, %{value: %{value: false}}}} = first

    assert %{
             path: @typed_path,
             result: {:error, %Error{code: :interaction_status, details: %{status: 0x7E}}}
           } = second

    assert {:ok, []} = Wire.decode(:read_paths, [])
    assert {:ok, results} = Wire.decode(:read_paths, List.duplicate(success, 1024))
    assert length(results) == 1024
    assert_invalid(Wire.decode(:read_paths, List.duplicate(success, 1025)))

    for bad <- [
          put_in(success, ["result", "ok", "path", "node_id"], 3),
          put_in(success, ["result", "ok", "value"], nil),
          put_in(failure, ["result", "error", "status"], 256),
          Map.put(success, "result", %{"ok" => %{}, "error" => %{}}),
          Map.put(success, "result", false),
          Map.put(success, "extra", 1),
          %{}
        ] do
      assert_invalid(Wire.decode(:read_paths, [success, bad, failure]))
    end

    assert_invalid(Wire.decode(:read_paths, %{}))
  end

  test "WMA-C04 event numbers and timestamp kinds retain their full wire representation" do
    for kind <- ["epoch", "system"], number <- [0, 0xFFFFFFFFFFFFFFFF] do
      result = event(kind, number)

      assert {:ok, [%{result: {:ok, decoded}}]} =
               Wire.decode(:read_events, [%{"path" => @path, "result" => %{"ok" => result}}])

      assert decoded.event_number == number

      assert decoded.timestamp == %{
               kind: if(kind == "epoch", do: :epoch, else: :system),
               value: number
             }

      assert decoded.priority == 255
      assert decoded.value == %{tag: :anonymous, type: :structure, value: []}
    end

    for result <- [
          Map.put(event(), "event_number", -1),
          Map.put(event(), "event_number", 0x10000000000000000),
          Map.put(event(), "priority", 256),
          Map.put(event(), "status", 1),
          put_in(event(), ["timestamp", "kind"], "untrusted-kind-canary"),
          put_in(event(), ["timestamp", "value"], -1),
          put_in(event(), ["timestamp", "value"], 0x10000000000000000),
          Map.put(event(), "timestamp", nil),
          Map.put(event(), "extra", true)
        ] do
      assert_invalid(Wire.decode(:read_events, [%{"path" => @path, "result" => %{"ok" => result}}]))
    end
  end

  test "WMA-C04 subscription metadata retains equal values as distinct reports" do
    for version <- [nil, 0, 0xFFFFFFFF],
        initial <- [false, true],
        id <- [1, 2, 0xFFFFFFFFFFFFFFFF] do
      metadata =
        attribute_metadata()
        |> Map.merge(%{"data_version" => version, "initial" => initial, "report_id" => id})

      assert {:ok, {:ok, %{value: false}, decoded}} =
               Wire.subscription("attribute", element("boolean", false), metadata)

      assert decoded.path == struct!(Address, @typed_path)
      assert decoded.data_version == version
      assert decoded.initial == initial
      assert decoded.report_id == id
      assert decoded.kind == :attribute
      assert decoded.min_interval_s == 0
      assert decoded.max_interval_s == 65_535
      assert decoded.sdk_subscription_id == 0xFFFFFFFF
    end

    for kind <- ["epoch", "system"], id <- [1, 0xFFFFFFFFFFFFFFFF] do
      metadata =
        event_metadata()
        |> put_in(["timestamp", "kind"], kind)
        |> Map.put("report_id", id)

      assert {:ok, {:ok, %{value: []}, %{kind: :event} = decoded}} =
               Wire.subscription("event", element("structure", []), metadata)

      assert decoded.event_number == 0xFFFFFFFFFFFFFFFF
      assert decoded.timestamp.value == 0xFFFFFFFFFFFFFFFF
      assert decoded.path == struct!(Address, @typed_path)
      assert decoded.report_id == id
    end
  end

  test "WMA-C04 rejects invalid report identity, intervals, paths and metadata extensions" do
    for {kind, metadata} <- [{"attribute", attribute_metadata()}, {"event", event_metadata()}],
        {key, value} <- [
          {"initial", 0},
          {"report_id", 0},
          {"report_id", -1},
          {"report_id", 0x10000000000000000},
          {"report_id", "1"},
          {"min_interval_s", -1},
          {"min_interval_s", 65_536},
          {"max_interval_s", 0},
          {"max_interval_s", 65_536},
          {"sdk_subscription_id", -1},
          {"sdk_subscription_id", 0x100000000},
          {"path", Map.put(@path, "node_id", 0)},
          {"path", nil},
          {"extra", 1}
        ] do
      assert_invalid(
        Wire.subscription(kind, element("boolean", false), Map.put(metadata, key, value))
      )
    end

    for {kind, metadata} <- [{"attribute", attribute_metadata()}, {"event", event_metadata()}] do
      assert_invalid(
        Wire.subscription(
          kind,
          element("boolean", false),
          Map.merge(metadata, %{"min_interval_s" => 2, "max_interval_s" => 1})
        )
      )

      assert_invalid(Wire.subscription(kind, nil, metadata))
    end

    for version <- [-1, 0x100000000, "0"] do
      assert_invalid(
        Wire.subscription(
          "attribute",
          element("boolean", false),
          Map.put(attribute_metadata(), "data_version", version)
        )
      )
    end

    for {key, value} <- [
          {"event_number", -1},
          {"event_number", 0x10000000000000000},
          {"priority", 256},
          {"timestamp", %{"kind" => "unknown", "value" => 0}}
        ] do
      assert_invalid(
        Wire.subscription("event", element("structure", []), Map.put(event_metadata(), key, value))
      )
    end

    assert_invalid(Wire.subscription("unknown", element("boolean", false), attribute_metadata()))
  end

  test "WMA-B02 native errors preserve bounded status and make uncertain mutations non-retryable" do
    assert {:ok,
            %Error{
              code: :interaction_status,
              details: %{status: 0, cluster_status: 255, sdk_status: 0xFFFFFFFF}
            }} =
             Wire.error(%{
               "code" => "interaction_status",
               "status" => 0,
               "cluster_status" => 255,
               "sdk_status" => 0xFFFFFFFF
             })

    for code <- [
          "commissioning_timeout",
          "interaction_timeout",
          "window_timeout",
          "subscription_timeout",
          "subscription_cancel_timeout"
        ] do
      assert {:ok, %Error{code: :timeout, effect: :none, class: :timeout, retryable: true}} =
               Wire.error(%{"code" => code})

      assert {:ok, %Error{code: :timeout, effect: :unknown, class: :permanent, retryable: false}} =
               Wire.error(%{"code" => code, "effect" => "unknown"})
    end

    for code <- ["commissioning_busy", "window_busy", "subscription_busy"] do
      assert {:ok, %Error{code: :busy, class: :rate_limited}} = Wire.error(%{"code" => code})
    end

    assert {:ok, %Error{code: :invalid_transport_return, class: :protocol}} =
             Wire.error(%{"code" => "invalid_backend_result"})

    assert {:ok, %Error{code: :invalid_handle, class: :permanent}} =
             Wire.error(%{"code" => "invalid_subscription"})

    assert {:ok, %Error{code: :native_error, details: %{}} = unknown} =
             Wire.error(%{"code" => "untrusted-error-secret-canary"})

    refute inspect(unknown) =~ "canary"
  end

  test "WMA-B02 every native failure identifier maps through the fixed public vocabulary" do
    mappings = %{
      "authority_invalid" => :authority_invalid,
      "controller_already_open" => :controller_already_open,
      "controller_closed" => :controller_closed,
      "controller_start_failed" => :controller_start_failed,
      "controller_start_timeout" => :controller_start_timeout,
      "commissioning_failed" => :commissioning_failed,
      "commissioning_submit_failed" => :commissioning_submit_failed,
      "commissioning_unavailable" => :commissioning_unavailable,
      "fabric_mismatch" => :fabric_mismatch,
      "interaction_busy" => :interaction_busy,
      "interaction_failed" => :interaction_failed,
      "interaction_no_response" => :interaction_no_response,
      "interaction_submit_failed" => :interaction_submit_failed,
      "interaction_unavailable" => :interaction_unavailable,
      "window_failed" => :commissioning_window_failed,
      "window_submit_failed" => :commissioning_window_submit_failed,
      "window_unavailable" => :commissioning_window_unavailable,
      "invalid_attribute_data" => :invalid_attribute_data,
      "invalid_controller_identity" => :invalid_controller_identity,
      "invalid_event_data" => :invalid_event_data,
      "invalid_request" => :invalid_request,
      "invalid_response_path" => :invalid_response_path,
      "missing_path_result" => :missing_path_result,
      "paa_trust_store_invalid" => :paa_trust_store_invalid,
      "response_limit" => :response_limit,
      "receiver_closed" => :receiver_closed,
      "sdk_storage_failed" => :sdk_storage_failed,
      "session_establishment_failed" => :session_establishment_failed,
      "storage_open_failed" => :storage_open_failed,
      "subscription_submit_failed" => :subscription_submit_failed,
      "subscription_unavailable" => :subscription_unavailable,
      "invalid_subscription_report" => :invalid_subscription_report,
      "invalid_subscription_result" => :invalid_subscription_result,
      "unsupported_schema" => :unsupported_schema,
      "unsupported_timestamp" => :unsupported_timestamp
    }

    for {wire, expected} <- mappings do
      assert {:ok, %Error{code: ^expected, details: %{}, effect: :none}} =
               Wire.error(%{"code" => wire})
    end
  end

  test "WMA-B02 native error envelopes reject unbounded diagnostics and ambiguous status" do
    for error <- [
          %{},
          nil,
          %{"code" => :timeout},
          %{"code" => "timeout", "message" => "secret-canary"},
          %{"code" => "interaction_failed", "effect" => "certain"},
          %{"code" => "interaction_failed", "status" => -1},
          %{"code" => "interaction_failed", "status" => 256},
          %{"code" => "interaction_failed", "cluster_status" => "0"},
          %{"code" => "interaction_failed", "sdk_status" => -1},
          %{"code" => "interaction_failed", "sdk_status" => 0x100000000}
        ] do
      assert :error = Wire.error(error)
    end
  end

  test "WMA-C01 commissioning success requires an established CASE result" do
    assert {:ok, %{node_id: 2, fabric_id: 1, case: :established}} =
             Wire.decode(:commission_on_network, %{
               "node_id" => 2,
               "fabric_id" => 1,
               "case" => "established"
             })

    for result <- [
          %{"node_id" => 0, "fabric_id" => 1, "case" => "established"},
          %{"node_id" => 2, "fabric_id" => 0x10000000000000000, "case" => "established"},
          %{"node_id" => 2, "fabric_id" => 1, "case" => "pending"}
        ] do
      assert_invalid(Wire.decode(:commission_on_network, result))
    end

    assert {:ok, %{fabric_id: 0xFFFFFFFFFFFFFFFF}} =
             Wire.decode(:commission_on_network, %{
               "node_id" => 2,
               "fabric_id" => 0xFFFFFFFFFFFFFFFF,
               "case" => "established"
             })

    window = %{
      "node_id" => 2,
      "setup_pin" => 20_202_021,
      "discriminator" => 3840,
      "manual_code" => "34970112332",
      "qr_code" => "MT:Y.K9042C00KA0648G00",
      "expires_in_s" => 180
    }

    assert {:ok, %{node_id: 2, setup_pin: 20_202_021, expires_in_s: 180}} =
             Wire.decode(:open_window, window)

    assert_invalid(Wire.decode(:open_window, Map.put(window, "expires_in_s", "180")))
  end

  defp element(type, value, tag \\ "anonymous"),
    do: %{"tag" => tag, "type" => type, "value" => value}

  defp path_envelopes(path) do
    attribute = Map.put(attribute(element("boolean", false)), "path", path)
    event = Map.put(event(), "path", path)

    [
      {:read, attribute},
      {:write, %{"path" => path, "status" => 0}},
      {:invoke, %{"path" => path, "value" => nil, "status" => 0}},
      {:read_paths, [%{"path" => path, "result" => %{"ok" => attribute}}]},
      {:read_events, [%{"path" => path, "result" => %{"ok" => event}}]},
      {:read_paths,
       [%{"path" => path, "result" => %{"error" => %{"code" => "interaction_status"}}}]}
    ]
  end

  defp attribute(value, version \\ 0),
    do: %{"path" => @path, "value" => value, "data_version" => version}

  defp event(kind \\ "epoch", number \\ 0xFFFFFFFFFFFFFFFF) do
    %{
      "path" => @path,
      "value" => element("structure", []),
      "event_number" => number,
      "priority" => 255,
      "timestamp" => %{"kind" => kind, "value" => number},
      "status" => 0
    }
  end

  defp attribute_metadata do
    %{
      "path" => @path,
      "data_version" => 0,
      "initial" => false,
      "report_id" => 1,
      "min_interval_s" => 0,
      "max_interval_s" => 65_535,
      "sdk_subscription_id" => 0xFFFFFFFF
    }
  end

  defp event_metadata do
    attribute_metadata()
    |> Map.delete("data_version")
    |> Map.merge(%{
      "event_number" => 0xFFFFFFFFFFFFFFFF,
      "priority" => 255,
      "timestamp" => %{"kind" => "epoch", "value" => 0xFFFFFFFFFFFFFFFF}
    })
  end

  defp assert_invalid(result),
    do: assert({:error, %Error{code: :invalid_frame, class: :protocol, retryable: false}} = result)
end
