defmodule Wotex.BACnet.BatchTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Batch, Error}

  @corpus Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__)
  @external_resource @corpus
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @moduletag corpus_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)

  test "WBA-N03 WBA-F08 validates the complete batch and rejects normalized duplicates" do
    vector = Enum.find(@cases, &(&1["id"] == "WBA-F08"))
    input = vector["input"]

    properties =
      Enum.map(input["properties"], fn
        "present_value" -> :present_value
        value -> value
      end)

    assert {:error, %Error{code: code, effect: effect}} =
             Batch.new(input["object_type"], input["instance"], properties)

    assert %{"code" => Atom.to_string(code), "effect" => Atom.to_string(effect)} ==
             vector["expectation"]["value"]["error"]

    for properties <- [nil, [], Enum.to_list(0..64), [85 | :improper]],
        do: assert({:error, %Error{code: :invalid_properties}} = Batch.new(1, 0, properties))

    for {object, instance, properties} <- [
          {1024, 0, [85]},
          {1, 4_194_303, [85]},
          {1, 0, [85, -1]},
          {1, 0, [:unknown]}
        ],
        do:
          assert({:error, %Error{code: :invalid_address}} = Batch.new(object, instance, properties))

    assert {:ok, requests} = Batch.new(:analog_output, 0, [:present_value, :object_name])
    assert Enum.map(requests, & &1.property) == [85, 77]

    assert Enum.all?(
             requests,
             &(&1.object_type == 1 and &1.array_index == nil and &1.priority == nil)
           )

    assert {:ok, requests} = Batch.new(1, 0, Enum.to_list(0..63))
    assert length(requests) == 64
  end

  test "WBA-N03 WBA-F09 shared clock produces the exact fail-fast transcript" do
    vector = Enum.find(@cases, &(&1["id"] == "WBA-F09"))
    input = vector["input"]
    [success, failure] = input["events"]
    assert {:ok, requests} = Batch.new(input["object_type"], input["instance"], input["properties"])
    state = Batch.start(requests, input["session_timeout_ms"])
    assert {:ok, first, timeout1} = Batch.current(state, 0)
    assert first.property == success["property"]
    assert {:ok, encoded} = Encoding.create({:real, success["value"]["value"]})
    assert {:continue, state} = Batch.accept(state, {:ok, encoded}, success["at_ms"])
    assert {:ok, second, timeout2} = Batch.current(state, success["at_ms"])
    assert second.property == failure["property"]

    error =
      Error.new(:remote_error, nil, %{class: failure["error_class"], code: failure["error_code"]})

    assert {:error, error} = Batch.accept(state, {:error, error}, failure["at_ms"])

    assert %{
             "code" => Atom.to_string(error.code),
             "effect" => Atom.to_string(error.effect),
             "details" =>
               Map.new(error.details, fn {key, value} -> {Atom.to_string(key), value} end)
           } == vector["expectation"]["value"]["error"]

    assert [
             %{
               "service" => "read_property",
               "property" => first.property,
               "timeout_ms" => timeout1
             },
             %{
               "service" => "read_property",
               "property" => second.property,
               "timeout_ms" => timeout2
             }
           ] ==
             vector["expectation"]["value"]["sent_services"]

    refute Map.has_key?(error.details, :values)
  end

  test "WBA-N03 batch completion preserves typed values and expires at equality" do
    {:ok, requests} = Batch.new(1, 0, [85, 77])
    state = Batch.start(requests, 100)
    {:ok, value} = Encoding.create({:boolean, false})
    assert {:continue, next} = Batch.accept(state, {:ok, value}, 99)
    assert {:done, %{85 => ^value, 77 => ^value}} = Batch.accept(next, {:ok, value}, 99)

    assert {:error,
            %Error{
              code: :deadline_exceeded,
              details: %{batch_index: 1, completed_count: 1, property: 77}
            }} = Batch.current(next, 100)

    assert {:error, %Error{code: :deadline_exceeded}} = Batch.accept(next, {:ok, value}, 100)
    assert {:error, %Error{code: :invalid_transport_return}} = Batch.accept(state, :unexpected, 1)
    assert {:error, %Error{code: :invalid_value}} = Batch.accept(state, {:ok, :untyped}, 1)

    error = %{
      Error.new(:remote_error, nil, %{class: 2, code: 32, secret: "canary"})
      | effect: :unknown
    }

    assert %Error{
             effect: :none,
             details: %{class: 2, code: 32, batch_index: 0, property: 85, completed_count: 0}
           } = Batch.failure(error, 0, 85)
  end
end
