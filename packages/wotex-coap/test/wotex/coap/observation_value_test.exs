defmodule Wotex.CoAP.ObservationValueTest do
  @moduledoc false

  use ExUnit.Case, async: true
  doctest Wotex.CoAP.Observe
  use ExUnitProperties
  alias Wotex.CoAP.{Blockwise, Codec, Error, Message, Observe, Subscription}
  alias Wotex.CoAP.Observation.Report

  test "WCO-C05 WCO-V09 handles are exact local generation-bound redacted values" do
    reference = make_ref()
    generation = make_ref()
    assert {:ok, handle} = Subscription.new(self(), reference, generation)
    assert :ok = Subscription.validate(handle, self())
    assert inspect(handle) == "#Wotex.CoAP.Subscription<opaque>"
    refute inspect(handle) =~ inspect(self())
    other = spawn(fn -> :ok end)
    assert {:error, %Error{code: :invalid_subscription}} = Subscription.validate(handle, other)

    for handle <- [
          nil,
          %{},
          %{handle | pid: nil},
          %{handle | reference: nil},
          %{handle | generation: nil},
          Map.delete(handle, :reference),
          Map.put(handle, :extra, true)
        ] do
      assert {:error, %Error{code: :invalid_subscription}} = Subscription.validate(handle, self())
    end

    for {pid, reference, generation} <- [
          {nil, reference, generation},
          {self(), nil, generation},
          {self(), reference, nil}
        ] do
      assert {:error, %Error{code: :invalid_subscription}} =
               Subscription.new(pid, reference, generation)
    end
  end

  property "WCO-S03 WCO-V05 report metadata preserves exact bounded unsigned values" do
    check all(
            sequence <- integer(0..16_777_215),
            age <- integer(0..4_294_967_295),
            format <- integer(0..65_535),
            tag <- binary(min_length: 1, max_length: 8),
            now <- integer(-1_000_000..1_000_000)
          ) do
      first = %{
        first()
        | options: [
            {4, tag},
            {6, Codec.uint(sequence)},
            {12, Codec.uint(format)},
            {14, Codec.uint(age)}
          ]
      }

      assert {:ok, report} = Report.new(first, now)
      assert report.first == first
      assert report.received_at == now
      assert report.message == nil

      assert report.metadata == %{
               code: 69,
               observe: sequence,
               etag: tag,
               content_format: format,
               max_age: age
             }

      assert :ok = Report.validate(report)
      assert {:ok, complete} = Report.complete(report, first)
      assert complete.message == first
      assert :ok = Report.validate(complete)
    end
  end

  test "WCO-S03 WCO-V06 reports require Observe and reject malformed metadata or status" do
    for invalid <- [
          nil,
          Map.delete(first(), :code),
          %{first() | options: []},
          %{first() | options: [{6, <<0::32>>}]},
          %{first() | options: [{6, <<>>}, {6, <<1>>}]},
          %{first() | options: [{4, "one"}, {4, "two"}, {6, <<>>}]},
          %{first() | options: [{12, <<0::24>>}, {6, <<>>}]},
          %{first() | options: [{14, <<0::40>>}, {6, <<>>}]},
          %{first() | payload: :binary.copy("x", 1153)},
          %{first() | code: 95},
          %{first() | code: 96}
        ] do
      assert {:error, %Error{}} = Report.new(invalid, 0)
    end

    assert {:error, %Error{code: :invalid_observation_response}} = Report.new(first(), nil)

    assert {:error, %Error{code: :remote_response, details: %{code: 159}}} =
             Report.new(%{first() | code: 159}, 0)

    assert {:ok, report} = Report.new(first(), 0)
    assert report.metadata == %{code: 69, observe: 0, etag: nil, content_format: nil, max_age: 60}
  end

  test "WCO-S03 WCO-V06 complete reports retain first identity and reject forged values" do
    first = %{first() | options: [{6, <<1>>}, {23, <<8>>}], payload: :binary.copy("x", 16)}
    assert {:ok, report} = Report.new(first, 0)

    callback = fn request, _ ->
      {{:ok, %{request | type: :ack, code: 69, payload: "last", options: [{23, <<16>>}]}}, :done}
    end

    request = %Message{type: :con, code: 1, message_id: 0, token: "distinct"}
    assert {{:ok, complete}, :done} = Blockwise.continue(request, first, [], nil, callback)
    assert {:ok, report} = Report.complete(report, complete)
    assert :ok = Report.validate(report)

    for forged <- [
          nil,
          %{report | first: nil},
          %{report | metadata: %{}},
          %{report | message: nil, received_at: nil},
          Map.delete(report, :first),
          %{report | message: %{complete | token: "foreign"}},
          %{report | message: %{complete | payload: :binary.copy("x", 1_048_577)}},
          Map.put(report, :extra, true)
        ] do
      assert {:error, %Error{}} = Report.validate(forged)
      assert {:error, %Error{}} = Report.complete(forged, complete)
    end

    for changed <- [
          nil,
          %{complete | token: "foreign"},
          %{complete | code: 68},
          %{complete | message_id: 2},
          %{complete | options: []},
          %{complete | payload: :binary.copy("x", 1_048_577)}
        ] do
      assert {:error, %Error{}} = Report.complete(report, changed)
    end
  end

  test "WCO-S03 WCO-V05 serial arithmetic honors exact half-range and 128-second boundaries" do
    assert Observe.fresh?(16_777_215, 0, 0)
    refute Observe.fresh?(0, 16_777_215, 128_000)
    refute Observe.fresh?(0, 0x800000, 128_000)
    refute Observe.fresh?(0x800000, 0, 128_000)
    refute Observe.fresh?(10, 10, 128_000)
    assert Observe.fresh?(10, 10, 128_001)
    assert Observe.fresh?(11, 10, 128_001)
  end

  defp first,
    do: %Message{type: :con, code: 69, message_id: 1, token: "report", options: [{6, <<>>}]}
end
