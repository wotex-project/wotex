defmodule Wotex.BACnet.RuntimeIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.{CharacterString, Error, Mapping, Value}
  alias Wotex.BACnet.Test.{IntegrationClient, IntegrationTransport, RuntimeCredentials}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context}

  @corpus Path.expand("../../../docs/specs/fixtures/wotex-integration-v1.json", __DIR__)
  @external_resource @corpus
  @vector Enum.find(Jason.decode!(File.read!(@corpus))["cases"], &(&1["id"] == "WBA-I-F01"))
  @moduletag corpus_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)

  test "WBA-I02 WBA-I03 WBA-I06 WBA-I-F01 actual Runtime selects, executes and closes the fixture profile" do
    input = @vector["input"]
    assert input["profile_mode"] == "ip"
    assert input["peer_reply"]["kind"] == "bacnet_application_value"
    assert input["peer_reply"]["tag"] == "real"
    {:ok, value} = Encoding.create({:real, input["peer_reply"]["value"]})
    configured = input["transport_options"]
    assert configured["client"] == "scripted_client"

    destination =
      {List.to_tuple(configured["destination"]["ipv4"]), configured["destination"]["port"]}

    consumed =
      consumed(input["thing_description"], BACnet.profile(), {:ok, value},
        target: configured["target"],
        timeout: configured["timeout"],
        destination: destination
      )

    clock = input["clock"]
    assert clock["kind"] == "monotonic_ms"
    deadline = System.monotonic_time(:millisecond) + clock["deadline"] - clock["start"]
    {:ok, context} = Context.new(request_id: input["request_id"], deadline: deadline)

    assert {:ok, result} = ConsumedThing.read_property(consumed, input["affordance"], context)
    assert_receive {:runtime_request, request}
    assert_receive {:native_opened, pid}
    assert_receive {:native_request, ^pid, command, timeout}
    assert timeout > 0 and timeout <= configured["timeout"]
    assert_receive {:native_closed, ^pid}
    refute Process.alive?(pid)
    refute_receive {:native_request, _, _, _}, 0

    projection = %{
      "profile_id" => Atom.to_string(BindingProfile.id(request.profile)),
      "resolved_href" => request.resolved_href,
      "command" =>
        json(Map.take(command, [:type, :object_type, :instance, :property, :array_index])),
      "result" =>
        result
        |> Map.from_struct()
        |> Map.take([:request_id, :operation, :status, :payload, :metadata])
        |> json(),
      "extension" => Wotex.Form.to_map(request.form)["example:extension"],
      "request_count" => 1,
      "owned_resources_after" => if(Process.alive?(pid), do: 1, else: 0)
    }

    assert projection == @vector["expectation"]["value"]
    refute Map.has_key?(Wotex.Form.to_map(request.form), "contentType")
    assert command.priority == nil
  end

  test "WBA-I02 profile factories have exact static schemes, operations and native media wildcard" do
    assert {:ok, baseline} = BACnet.profile(:ip)
    assert baseline == BACnet.profile()

    for {mode, id, operations} <- [
          {:ip, :bacnet, [:readproperty, :writeproperty]},
          {:ip_cov, :bacnet_cov,
           [:readproperty, :writeproperty, :observeproperty, :unobserveproperty]}
        ] do
      assert {:ok, profile} = BACnet.profile(mode)
      assert BindingProfile.id(profile) == id
      assert profile.schemes == MapSet.new(["bacnet"])
      assert profile.operations == MapSet.new(operations)
      assert profile.media_types == MapSet.new()
      assert BindingProfile.supports_scheme?(profile, "BACNET")
      refute BindingProfile.supports_scheme?(profile, "bacnets")

      for operation <- Wotex.Runtime.operations() do
        assert BindingProfile.supports_operation?(profile, operation) == operation in operations
      end
    end

    for mode <- [nil, "ip", :who_is, :readmultipleproperties, :event, %{}, [:ip]] do
      assert {:error, %Error{code: :unsupported_profile, class: :permanent}} = BACnet.profile(mode)
    end

    refute_receive {:native_opened, _}, 0
  end

  test "WBA-I03 WBA-I06 explicit media, invalid selectors and route mismatch reject before native acquisition" do
    for mode <- [:ip, :ip_cov] do
      {:ok, profile} = BACnet.profile(mode)

      for {changes, code} <- [
            {%{"contentType" => "application/json"}, :unsupported_content_type},
            {%{"contentType" => "application/octet-stream"}, :unsupported_content_type},
            {%{"contentType" => "application/xml"}, :unsupported_content_type},
            {%{"bacv:hasDataType" => %{"@type" => "vendor:Unknown"}}, :invalid_value_type},
            {%{"bacv:hasDataType" => nil}, :invalid_value_type},
            {%{"href" => "bacnet://1235/2,1/85"}, :target_mismatch},
            {%{"href" => "bacnet://1234/+2,1/85"}, :invalid_form_address},
            {%{"href" => "bacnet://1234/2,+1/85"}, :invalid_form_address},
            {%{"href" => "bacnet://1234/2,1/+85"}, :invalid_form_address}
          ] do
        consumed = consumed(td(changes), profile, {:ok, nil})
        {:ok, context} = Context.new(request_id: "rejected")
        assert {:error, failure} = ConsumedThing.read_property(consumed, "reading", context)
        assert failure.details.cause.code == code
        assert failure.class == :permanent
        assert_receive {:runtime_request, _}
        refute_receive {:native_opened, _}, 0
        refute_receive {:native_request, _, _, _}, 0
      end
    end
  end

  test "WBA-I03 selectors validate on reads and observations without losing unknown extension members" do
    for name <- ["Null", "Boolean", "Signed", "Unsigned", "Real", "Double", "String", "OctetString"],
        operation <- [:readproperty, :observeproperty] do
      selector = %{"@type" => "bacv:" <> name, "example:future" => [false, 0, nil]}
      assert :ok = Value.validate_type(selector)

      raw = %{
        "href" => "bacnet://1234/2,1/85",
        "op" => Atom.to_string(operation),
        "bacv:hasDataType" => selector,
        "example:future" => %{"nested" => false}
      }

      {:ok, form} = Wotex.Form.new(raw)
      assert {:ok, mapping} = Mapping.command(form, operation, nil)
      assert mapping.form == raw
    end

    for invalid <- [nil, "bacv:Real", %{}, %{"@type" => "unknown"}] do
      assert {:error, %Error{code: :invalid_value_type}} = Value.validate_type(invalid)
    end

    assert {:error, _} = Wotex.Form.new(%{"href" => "bacnet://1234/2,1/85", "contentType" => nil})
    form = %Wotex.Form{value: %{"href" => "bacnet://1234/2,1/85", "contentType" => nil}}

    assert {:error, %Error{code: :unsupported_content_type}} =
             Mapping.command(form, :readproperty, nil)
  end

  test "WBA-I03 WBA-I06 native false, zero, empty string, empty list and null remain successful values" do
    for {native, payload, metadata} <- [
          {encoded(:boolean, false), false, %{bacnet_type: :boolean}},
          {encoded(:unsigned_integer, 0), 0, %{bacnet_type: :unsigned_integer}},
          {encoded(:character_string, %CharacterString{character_set: 0, bytes: ""}), "",
           %{bacnet_type: :character_string, character_set: 0}},
          {[], [], %{}},
          {encoded(:null, nil), nil, %{bacnet_type: :null}}
        ] do
      consumed = consumed(td(), BACnet.profile(), {:ok, native})
      {:ok, context} = Context.new(request_id: "empty-value")
      assert {:ok, result} = ConsumedThing.read_property(consumed, "reading", context)
      assert result.payload === payload
      assert result.metadata == metadata
      assert_receive {:runtime_request, _}
      assert_receive {:native_opened, pid}
      assert_receive {:native_request, ^pid, _, _}
      assert_receive {:native_closed, ^pid}
      refute Process.alive?(pid)
    end
  end

  defp consumed(td, profile, reply, options \\ []) do
    {:ok, td} = Wotex.ThingDescription.from_map(td)

    config =
      Keyword.merge(
        [client: IntegrationClient, observer: self(), reply: reply, target: "1234", timeout: 1000],
        options
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{BindingProfile.id(profile) => {IntegrationTransport, config}},
        credentials: {RuntimeCredentials, []}
      )

    consumed
  end

  defp td(changes \\ %{}) do
    td = @vector["input"]["thing_description"]
    update_in(td, ["properties", "reading", "forms"], fn [form] -> [Map.merge(form, changes)] end)
  end

  defp encoded(type, value),
    do: %Encoding{encoding: :primitive, type: type, value: value, extras: []}

  defp json(value), do: Jason.decode!(Jason.encode!(value))
end
