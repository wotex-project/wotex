defmodule Wotex.BACnet.RuntimeFrameTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{COVRequest, Error, RuntimeFrame, Transport}
  alias Wotex.Runtime.Request

  @fixture Path.expand("../../fixtures/runtime_frame_v1.json", __DIR__)
  @external_resource @fixture
  @corpus Jason.decode!(File.read!(@fixture))
  @moduletag corpus_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@fixture)), case: :lower)
  @destination {{127, 0, 0, 1}, 55_834}
  @types %{
    "boolean" => :boolean,
    "unsigned_integer" => :unsigned_integer,
    "null" => :null,
    "octet_string" => :octet_string,
    "real" => :real
  }

  setup do
    association =
      Map.new(@corpus["association"], fn {key, value} -> {String.to_existing_atom(key), value} end)

    {:ok, request} = COVRequest.new(Map.put(association, :type, :cov_property), self())

    {:ok, form} =
      Wotex.Form.new(%{"href" => "bacnet://123/1,7/85", "op" => "observeproperty"})

    runtime = %Request{
      operation: :observeproperty,
      affordance_type: :property,
      affordance_name: "reading",
      form: form,
      resolved_href: "bacnet://123/1,7/85",
      profile: nil,
      request_id: "frame-1",
      deadline: nil,
      input: nil
    }

    %{request: request, runtime: runtime, config: [target: "123", destination: @destination]}
  end

  test "WBA-S05 WBA-V12 WBA-I05 RF01–RF05 preserve false, zero, null and empty values", c do
    for vector <- @corpus["cases"] do
      type = Map.fetch!(@types, vector["type"])
      {:ok, value} = Encoding.create({type, vector["value"]})
      metadata = metadata(value)
      assert :ok = RuntimeFrame.validate(value, metadata, c.request, @destination), vector["id"]

      assert {:ok, payload, projected} =
               Transport.decode_frame({:value, value, metadata}, c.runtime, c.config)

      assert payload === vector["expected"], vector["id"]
      assert projected == Map.put(metadata, :bacnet_type, type)
    end
  end

  test "WBA-S05 WBA-I05 RF06–RF12 reject forged associations and wire integers", c do
    {:ok, value} = Encoding.create({:real, 1.5})
    metadata = metadata(value)

    for vector <- @corpus["reject_mutations"] do
      field = String.to_existing_atom(vector["field"])
      mutated = Map.put(metadata, field, vector["value"])

      assert {:error, %Error{code: :invalid_runtime_frame}} =
               RuntimeFrame.validate(value, mutated, c.request, @destination),
             vector["id"]
    end

    for malformed <- [Map.delete(metadata, :property), Map.put(metadata, :handle, self()), nil],
        do:
          assert(
            {:error, %Error{code: :invalid_runtime_frame}} =
              RuntimeFrame.validate(value, malformed, c.request, @destination)
          )

    assert {:error, %Error{code: :invalid_runtime_frame}} =
             RuntimeFrame.validate(value, metadata, c.request, {{127, 0, 0, 2}, 55_834})
  end

  test "WBA-S05 WBA-I05 projection requires the selected bounded native value", c do
    {:ok, value} = Encoding.create({:real, 1.5})
    {:ok, different} = Encoding.create({:real, 2.5})
    metadata = metadata(value)
    [entry] = metadata.report_values

    for malformed <- [
          nil,
          [%{entry | property: -1}],
          [%{entry | array_index: -1}],
          [%{entry | priority: 17}],
          [Map.put(entry, :handle, :hidden)],
          [%{entry | value: :untyped}],
          [%{entry | value: different}],
          [entry, %{entry | value: different}],
          List.duplicate(entry, 1025)
        ] do
      assert {:error, %Error{}} =
               RuntimeFrame.validate(
                 value,
                 %{metadata | report_values: malformed},
                 c.request,
                 @destination
               )
    end

    assert :ok =
             RuntimeFrame.validate(
               value,
               %{metadata | report_values: [entry, %{entry | property: 111}, entry]},
               c.request,
               @destination
             )

    assert {:error, %Error{}} = RuntimeFrame.validate(self(), metadata, c.request, @destination)
    assert :ignore = Transport.decode_frame(:keepalive, c.runtime, c.config)
    error = {:error, Error.new(:connection_closed)}
    assert ^error = Transport.decode_frame(error, c.runtime, c.config)

    for config <- [[target: "wrong"], [:invalid], [target: "123", target: "123"]] do
      assert {:error, %Error{}} =
               Transport.decode_frame({:value, value, metadata}, c.runtime, config)
    end
  end

  defp metadata(value) do
    %{
      source: @destination,
      device_instance: 123,
      process_identifier: 1,
      object_type: 1,
      instance: 7,
      property: 85,
      array_index: nil,
      time_remaining: 4_294_967_295,
      report_values: [%{property: 85, array_index: nil, priority: nil, value: value}]
    }
  end
end
