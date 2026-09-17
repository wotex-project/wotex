defmodule Wotex.BLE.RuntimeIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.{BLE, Form, ThingDescription}
  alias Wotex.BLE.{Error, Mapping, RuntimeClient, RuntimeErrorPort, RuntimeRecordingTransport}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}

  @corpus Path.expand("../../../priv/fixtures/wotex-integration-v1.json", __DIR__)
  @external_resource @corpus
  @vector @corpus
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("cases")
          |> Enum.find(&(&1["id"] == "WBL-I-F01"))

  test "WBL-I02 WBL-I03 WBL-I06 WBL-I-F01 real TD selects native baseline and exact fixture bytes" do
    input = @vector["input"]
    assert input["profile_mode"] == "oneshot"
    assert input["transport_options"]["client"] == "scripted_client"
    assert input["peer_reply"]["kind"] == "client_return"

    {:ok, consumed} =
      consumer(input["thing_description"],
        target: input["transport_options"]["target"],
        timeout: input["transport_options"]["timeout"],
        peer_reply: bytes(input["peer_reply"]["value"])
      )

    origin = System.monotonic_time(:millisecond)
    deadline = origin + input["clock"]["deadline"] - input["clock"]["start"]
    context = Context.new!(request_id: input["request_id"], deadline: deadline)
    assert {:ok, result} = ConsumedThing.read_property(consumed, input["affordance"], context)
    assert_receive {:selected_request, request}
    trace = client_trace()
    assert [{:open, open_budget}, {:request, command, request_budget}, {:close}] = trace
    assert open_budget > 0 and open_budget <= 1000
    assert request_budget > 0 and request_budget <= open_budget
    refute_received {:runtime_client, :request, _, _}
    refute_received {:runtime_client, :open, _}

    actual = %{
      "profile_id" => Atom.to_string(BindingProfile.id(request.profile)),
      "resolved_href" => request.resolved_href,
      "command" => %{
        "type" => Atom.to_string(command.type),
        "service" => command.service,
        "characteristic" => command.characteristic
      },
      "result" => %{
        "request_id" => result.request_id,
        "operation" => Atom.to_string(result.operation),
        "status" => Atom.to_string(result.status),
        "payload" => envelope(result.payload),
        "metadata" => result.metadata
      },
      "extension" => Form.to_map(request.form)["example:extension"],
      "request_count" => Enum.count(trace, &match?({:request, _, _}, &1)),
      "owned_resources_after" =>
        Enum.count(trace, &match?({:open, _}, &1)) - Enum.count(trace, &(&1 == {:close}))
    }

    assert actual == @vector["expectation"]["value"]
  end

  test "WBL-I06 every integration corpus case has an executing owner that compares it" do
    corpus = Jason.decode!(File.read!(@corpus))

    assert Map.take(corpus, ["format", "version"]) ==
             %{"format" => "wotex.protocol.integration", "version" => "1.0.0"}

    ids = Enum.map(corpus["cases"], & &1["id"])
    assert ids == Enum.uniq(ids)

    owners = %{
      "runtime_read" => "test/wotex/ble/runtime_integration_test.exs",
      "error_retry_projection" => "test/wotex/ble/runtime_error_test.exs"
    }

    for fixture <- corpus["cases"] do
      assert owner = owners[fixture["operation"]], "#{fixture["id"]} has an unknown operation"
      assert fixture["expectation"]["operator"] == "exact"
      source = File.read!(Path.expand("../../../" <> owner, __DIR__))

      assert String.contains?(source, fixture["operation"]) or
               String.contains?(source, fixture["id"])

      assert String.contains?(source, ~s(["expectation"]["value"]))
    end
  end

  test "WBL-I02 WBL-I06 two explicit profiles select by Form order and then profile order" do
    oneshot = BLE.profile()
    assert {:ok, gatt} = BLE.profile(:gatt)
    config = [client: RuntimeClient, test_pid: self(), target: "peer", peer_reply: <<42>>]
    {:ok, td} = ThingDescription.from_map(td())

    consumed = fn profiles ->
      ConsumedThing.new(td,
        profiles: profiles,
        transports: %{
          ble: {RuntimeRecordingTransport, config},
          ble_gatt: {RuntimeRecordingTransport, config}
        },
        credentials: {RuntimeErrorPort, nil}
      )
    end

    assert {:ok, first} = consumed.([oneshot, gatt])
    assert {:ok, %Result{payload: <<42>>, status: :ok}} = read(first)
    assert_receive {:selected_request, %{profile: ^oneshot, resolved_href: "ble://peer/180f/2a19"}}
    assert_receive {:runtime_client, :open, _}
    assert_receive {:runtime_client, :request, _, _}
    assert_receive {:runtime_client, :close}

    # The GATT profile admits the same Form first when supplied first; it then
    # requires the persistent backend and fails before any client acquisition.
    assert {:ok, reversed} = consumed.([gatt, oneshot])

    assert {:error, %{details: %{cause: %{code: :unsupported_profile, module: Error}}}} =
             read(reversed)

    assert_receive {:selected_request, %{profile: ^gatt, resolved_href: "ble://peer/180f/2a19"}}
    refute_received {:runtime_client, :open, _}
  end

  test "WBL-I02 baseline profiles are inert and selection preserves omitted media and defaults" do
    assert {:ok, profile} = BLE.profile(:oneshot)
    assert profile == BLE.profile()
    assert profile.schemes == MapSet.new(["ble"])
    assert profile.operations == MapSet.new([:readproperty, :writeproperty])
    assert profile.media_types == MapSet.new()

    for mode <- [nil, "oneshot", :guess, %{}] do
      assert {:error, %Error{code: :unsupported_profile}} = BLE.profile(mode)
    end

    td =
      td(%{"href" => "180f/2a19", "vendor:extension" => %{"nested" => [false, 0, nil]}})
      |> Map.put("base", "ble://peer/")
      |> put_in(["properties", "reading", "readOnly"], true)

    td =
      update_in(
        td["properties"]["reading"]["forms"],
        &[%{"href" => "https://example.test/value"} | &1]
      )

    {:ok, consumed} = consumer(td)
    assert {:ok, %Result{payload: <<42>>, status: :ok}} = read(consumed)
    assert_receive {:selected_request, request}
    assert request.resolved_href == "ble://peer/180f/2a19"
    assert request.affordance_type == :property
    refute Map.has_key?(Form.to_map(request.form), "contentType")
    assert Form.to_map(request.form)["vendor:extension"] == %{"nested" => [false, 0, nil]}
    assert_receive {:runtime_client, :open, _}
    assert_receive {:runtime_client, :request, _, _}
    assert_receive {:runtime_client, :close}
    assert {:error, _} = ConsumedThing.write_property(consumed, "reading", <<0>>, context())
    refute_received {:runtime_client, :open, _}
  end

  test "WBL-S05 WBL-V10 WBL-I03 every named codec is explicit through read and acknowledged write" do
    for {type, value, bytes} <- [
          {"bytes", <<0, 255>>, <<0, 255>>},
          {"utf8", "å", <<195, 165>>},
          {"boolean", false, <<0>>},
          {"uint8", 0, <<0>>},
          {"int8", -1, <<255>>},
          {"uint16", 4660, <<18, 52>>},
          {"int16", -2, <<255, 254>>},
          {"uint32", 42, <<0, 0, 0, 42>>},
          {"int32", -2, <<255, 255, 255, 254>>},
          {"uint64", 42, <<42::64>>},
          {"int64", -2, <<-2::signed-64>>},
          {"float32", 1.5, <<1.5::float-32>>},
          {"float64", 1.5, <<1.5::float-64>>},
          {"utf8", "", <<>>},
          {"bytes", <<>>, <<>>}
        ] do
      form = %{
        "href" => "ble://peer/180f/2a19",
        "wotex:bleValueType" => type,
        "wotex:bleByteOrder" => "big"
      }

      {:ok, consumed} = consumer(td(form), peer_reply: bytes)
      assert {:ok, %Result{payload: ^value}} = read(consumed)
      assert_receive {:runtime_client, :open, _}
      assert_receive {:runtime_client, :request, %{type: :read}, _}
      assert_receive {:runtime_client, :close}
      {:ok, consumed} = consumer(td(form), peer_reply: :written)

      assert {:ok, %Result{payload: :written, status: :ok}} =
               ConsumedThing.write_property(consumed, "reading", value, context())

      assert_receive {:runtime_client, :open, _}
      assert_receive {:runtime_client, :request, %{type: :write, value: ^bytes}, _}
      assert_receive {:runtime_client, :close}
    end
  end

  test "WBL-I03 known invalid selectors, explicit media, credentials and routing acquire nothing" do
    for {fields, code} <- [
          {%{"contentType" => "application/json"}, :unsupported_content_type},
          {%{"contentType" => "application/octet-stream"}, :unsupported_content_type},
          {%{"wotex:bleValueType" => "temperature"}, :invalid_selector},
          {%{"wotex:bleValueType" => nil}, :invalid_selector},
          {%{"wotex:bleByteOrder" => "native"}, :invalid_selector},
          {%{"wotex:bleMode" => "confirmed"}, :invalid_selector},
          {%{"wotex:bleMode" => "notify"}, :invalid_selector},
          {%{"wotex:bleMode" => true}, :invalid_selector}
        ] do
      {:ok, consumed} = consumer(td(Map.merge(%{"href" => "ble://peer/180f/2a19"}, fields)))
      assert {:error, %{details: %{cause: %{code: ^code, class: :permanent}}}} = read(consumed)
      refute_received {:runtime_client, :open, _}
    end

    for {config, code} <- [
          {[target: "other"], :target_mismatch},
          {[security_mode: :authenticated], :unsupported_security},
          {[timeout: 0], :invalid_timeout}
        ] do
      {:ok, consumed} = consumer(td(), config)
      assert {:error, %{details: %{cause: %{code: ^code}}}} = read(consumed)
      refute_received {:runtime_client, :open, _}
    end

    secured = td() |> Map.put("securityDefinitions", %{"none" => %{"scheme" => "basic"}})
    {:ok, consumed} = consumer(secured)
    assert {:error, %{phase: :credentials}} = read(consumed)
    refute_received {:runtime_client, :open, _}
    {:ok, consumed} = consumer(td())

    assert {:error, %{details: %{cause: %{code: :invalid_value}}}} =
             ConsumedThing.write_property(consumed, "reading", nil, context())

    refute_received {:runtime_client, :open, _}
  end

  test "WBL-I03 malformed native replies and unknown write completion fail closed" do
    for value <- [nil, false, 0, [], %{}, :written, :binary.copy(<<0>>, 513)] do
      {:ok, consumed} = consumer(td(), peer_reply: value)
      assert {:error, %{class: :protocol}} = read(consumed)
      assert_receive {:runtime_client, :close}
    end

    for value <- [nil, false, <<>>, true] do
      {:ok, consumed} = consumer(td(), peer_reply: value)

      assert {:error, %{class: :permanent}} =
               ConsumedThing.write_property(consumed, "reading", <<0>>, context())

      assert_receive {:runtime_client, :close}
    end
  end

  test "WBL-I03 contextual applicability and exact URI grammar precede native I/O" do
    {:ok, event} = Form.new(%{"href" => "ble://peer/180f/2a19"}, for: :event)

    for operation <- [:subscribeevent, :unsubscribeevent] do
      assert {:ok, %{mode: :auto}} = Mapping.command(event, operation, nil)
    end

    {:ok, observation} =
      Form.new(%{"href" => "ble://peer/180f/2a19", "op" => "observeproperty"}, for: :property)

    assert {:ok, %{message: %{type: :subscribe}}} =
             Mapping.command(observation, :observeproperty, nil)

    assert {:error, _} = Mapping.command(observation, :subscribeevent, nil)
    assert {:error, _} = Mapping.command(event, :invokeaction, nil)
    assert {:error, _} = Mapping.command(event, :readallproperties, nil)

    for href <- [
          "ble://peer//180f/2a19",
          "ble://peer/180f/2a19/",
          "ble://peer/180f//2a19",
          "ble://user@peer/180f/2a19",
          "ble://peer:12/180f/2a19",
          "ble://peer/180f/2a19?mode=notify",
          "ble://peer/180f/2a19#x"
        ] do
      assert {:error, %Error{code: :invalid_form_address}} =
               Mapping.command(event, :readproperty, nil, href)
    end

    assert {:error, %Error{code: :invalid_form}} =
             Mapping.command(%Form{value: %{"href" => self()}}, :readproperty, nil)
  end

  test "WBL-I04 setup consumes the single deadline and cleanup still runs" do
    {:ok, consumed} = consumer(td(), timeout: 20, connect_delay: 30)
    assert {:error, %{class: :timeout}} = read(consumed)
    assert_receive {:runtime_client, :open, _}
    assert_receive {:runtime_client, :close}
    refute_received {:runtime_client, :request, _, _}

    for deadline <- [DateTime.add(DateTime.utc_now(), -1), System.monotonic_time(:millisecond) - 1] do
      {:ok, consumed} = consumer(td())
      assert {:error, _} = read(consumed, Context.new!(request_id: "expired", deadline: deadline))
      refute_received {:runtime_client, :open, _}
    end
  end

  test "WBL-I06 actual Runtime rejects mismatched result identity and operation" do
    for {id, operation} <- [{"other", :readproperty}, {"runtime-read", :writeproperty}] do
      {:ok, result} = Result.new(id, operation, false)
      {:ok, consumed} = consumer(td(), result_override: result)
      assert {:error, %{code: :mismatched_transport_result}} = read(consumed)
      refute_received {:runtime_client, :open, _}
    end
  end

  defp client_trace(acc \\ []) do
    receive do
      {:runtime_client, :open, budget} ->
        client_trace([{:open, budget} | acc])

      {:runtime_client, :request, command, budget} ->
        client_trace([{:request, command, budget} | acc])

      {:runtime_client, :close} ->
        client_trace([{:close} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp consumer(map, options \\ []) do
    {:ok, td} = ThingDescription.from_map(map)

    config =
      Keyword.merge(
        [client: RuntimeClient, test_pid: self(), target: "peer", peer_reply: <<42>>],
        options
      )

    ConsumedThing.new(td,
      profiles: [BLE.profile()],
      transports: %{ble: {RuntimeRecordingTransport, config}},
      credentials: {RuntimeErrorPort, nil}
    )
  end

  defp td(form \\ %{"href" => "ble://peer/180f/2a19"}) do
    %{
      "@context" => "https://www.w3.org/2022/wot/td/v1.1",
      "title" => "BLE Runtime fixture",
      "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
      "security" => ["none"],
      "properties" => %{"reading" => %{"forms" => [form]}}
    }
  end

  defp context, do: Context.new!(request_id: "runtime-read")

  defp read(consumed, context \\ context()),
    do: ConsumedThing.read_property(consumed, "reading", context)

  defp bytes(%{"type" => "bytes", "base64" => encoded}), do: Base.decode64!(encoded)
  defp envelope(bytes), do: %{"type" => "bytes", "base64" => Base.encode64(bytes)}
end
