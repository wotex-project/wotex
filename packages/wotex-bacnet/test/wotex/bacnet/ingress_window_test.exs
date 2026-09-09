defmodule Wotex.BACnet.IngressWindowTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.BACnet.{IngressWindow, IPv4Packet}

  @fixture Jason.decode!(
             File.read!(Path.expand("../../../docs/specs/fixtures/ingress-v1.json", __DIR__))
           )

  test "WBA-IG01 WBA-S03a a full receipt window expires exactly at the fixed deadline" do
    row = fixture("WBA-IG01")
    generation = make_ref()
    initial = IngressWindow.new(generation)
    assert IngressWindow.available(initial) == row["input"]["credit_limit"]
    refute IngressWindow.expired?(initial, 1000)

    window =
      Enum.reduce(1..row["input"]["credit_limit"], initial, fn _, window ->
        assert {:ok, next} = IngressWindow.admit(window, make_ref(), 0)
        next
      end)

    assert window.peak == row["expectation"]["value"]["max_outstanding"]
    assert IngressWindow.available(window) == 0
    assert {:error, :busy} = IngressWindow.admit(window, make_ref(), 99)
    refute IngressWindow.expired?(window, 99)
    assert IngressWindow.expired?(window, 100)

    [receipt | _] = MapSet.to_list(window.outstanding)
    consumed = IngressWindow.consume(window, generation, receipt)
    assert IngressWindow.available(consumed) == 1
    refute IngressWindow.expired?(consumed, 10_000)
    assert {:ok, refilled} = IngressWindow.admit(consumed, make_ref(), 1000)
    refute IngressWindow.expired?(refilled, 1099)
    assert IngressWindow.expired?(refilled, 1100)
  end

  test "WBA-IG02 WBA-S03a only the first matching acknowledgment returns credit" do
    row = fixture("WBA-IG02")
    generation = make_ref()
    receipt = make_ref()
    assert {:ok, window} = IngressWindow.admit(IngressWindow.new(generation), receipt, 0)
    assert {:error, :duplicate_receipt} = IngressWindow.admit(window, receipt, 1)
    assert IngressWindow.available(window) == 7

    consumed = IngressWindow.consume(window, generation, receipt)

    assert IngressWindow.available(consumed) - IngressWindow.available(window) ==
             row["expectation"]["value"]["consumption_credit_returned"]

    replayed =
      consumed
      |> IngressWindow.consume(generation, receipt)
      |> IngressWindow.consume(make_ref(), receipt)
      |> IngressWindow.consume(generation, make_ref())

    assert replayed.counters.ignored_ack == row["expectation"]["value"]["ignored_ack_count"]
    assert MapSet.size(replayed.outstanding) == row["expectation"]["value"]["outstanding"]
    assert IngressWindow.available(replayed) == 8
  end

  test "WBA-IG03 WBA-S03a oversize classification precedes codecs and counters saturate" do
    row = fixture("WBA-IG03")
    initial = IngressWindow.new(make_ref())
    initial = put_in(initial.counters.oversize, row["input"]["counters"]["oversize"])

    result =
      Enum.reduce(row["input"]["events"], initial, fn event, window ->
        assert {:error, :oversize} = IPv4Packet.decode(:binary.copy(<<0>>, event["byte_length"]))
        IngressWindow.count(window, :oversize)
      end)

    assert result.counters.oversize == row["expectation"]["value"]["counters"]["oversize"]
    assert result.outstanding == initial.outstanding
    assert MapSet.size(result.outstanding) == row["expectation"]["value"]["delivered_messages"]
  end

  property "WBA-S03a arbitrary acknowledgments never add capacity beyond eight" do
    check all(count <- integer(0..8), acknowledgments <- list_of(integer(0..12), max_length: 64)) do
      generation = make_ref()
      receipts = for _ <- 1..8, do: make_ref()

      window =
        receipts
        |> Enum.take(count)
        |> Enum.reduce(IngressWindow.new(generation), fn ref, acc ->
          {:ok, next} = IngressWindow.admit(acc, ref, 0)
          next
        end)

      result =
        Enum.reduce(acknowledgments, window, fn index, acc ->
          next = IngressWindow.consume(acc, generation, Enum.at(receipts, index))
          assert IngressWindow.available(next) in (8 - count)..8
          next
        end)

      expected_consumed = Enum.count(Enum.uniq(acknowledgments), &(&1 < count))
      assert IngressWindow.available(result) == 8 - count + expected_consumed
    end
  end

  defp fixture(id), do: Enum.find(@fixture["cases"], &(&1["id"] == id))
end
