defmodule Wotex.Thread.ReportLedgerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.OpenThread.ReportLedger

  @moduletag requirements: ["WTH-B02"]

  test "WTH-B02 only contiguous consumed reports advance the exact cumulative acknowledgement" do
    {:ok, ledger} = ReportLedger.open(ReportLedger.new(), {"s1", 1}, 64)
    {:ok, ledger} = ReportLedger.open(ledger, {"s2", 1}, 64)
    [a, b, c] = [make_ref(), make_ref(), make_ref()]
    {:ok, ledger} = ReportLedger.register(ledger, {"s1", 1}, 1, 128, a)
    {:ok, ledger} = ReportLedger.register(ledger, {"s2", 1}, 2, 100, b)
    {:ok, ledger} = ReportLedger.register(ledger, {"s1", 1}, 3, 50, c)
    assert {nil, ^ledger} = ReportLedger.advance(ledger)

    # A report consumed out of order waits for the missing prefix.
    {:ok, ledger} = ReportLedger.consume(ledger, {"s2", 1}, 2, b)
    assert {nil, ^ledger} = ReportLedger.advance(ledger)
    assert :ignore = ReportLedger.consume(ledger, {"s2", 1}, 2, b)
    assert :ignore = ReportLedger.consume(ledger, {"s1", 1}, 1, b)
    assert :ignore = ReportLedger.consume(ledger, {"s2", 1}, 1, a)
    assert :ignore = ReportLedger.consume(ledger, {"s1", 1}, 4, a)

    {:ok, ledger} = ReportLedger.consume(ledger, {"s1", 1}, 1, a)
    assert {%{report_sequence: 2, acknowledged_bytes: 228}, ledger} = ReportLedger.advance(ledger)
    assert {nil, ^ledger} = ReportLedger.advance(ledger)
    {:ok, ledger} = ReportLedger.consume(ledger, {"s1", 1}, 3, c)
    assert {%{report_sequence: 3, acknowledged_bytes: 278}, _} = ReportLedger.advance(ledger)
  end

  test "WTH-B02 registration admits only the next sequence within session and stream credit" do
    {:ok, ledger} = ReportLedger.open(ReportLedger.new(), {"s1", 1}, 2)
    token = make_ref()
    assert :error = ReportLedger.register(ledger, {"s1", 1}, 2, 64, token)
    assert :error = ReportLedger.register(ledger, {"s9", 1}, 1, 64, token)
    assert :error = ReportLedger.register(ledger, {"s1", 2}, 1, 64, token)
    assert :error = ReportLedger.register(ledger, {"s1", 1}, 1, 1, token)
    assert :error = ReportLedger.register(ledger, {"s1", 1}, 1, 131_073, token)
    assert :error = ReportLedger.register(ledger, {"s1", 1}, 1, 64, :token)
    assert :error = ReportLedger.register(ledger, {"s1", 1}, 0, 64, token)
    {:ok, ledger} = ReportLedger.register(ledger, {"s1", 1}, 1, 64, token)
    {:ok, ledger} = ReportLedger.register(ledger, {"s1", 1}, 2, 64, make_ref())
    # queue_limit 2 bounds this stream's outstanding reports below the 16-report stream ceiling.
    assert :error = ReportLedger.register(ledger, {"s1", 1}, 3, 64, make_ref())
    {:ok, ledger} = ReportLedger.consume(ledger, {"s1", 1}, 1, token)
    {%{report_sequence: 1}, ledger} = ReportLedger.advance(ledger)
    assert {:ok, _} = ReportLedger.register(ledger, {"s1", 1}, 3, 64, make_ref())

    {:ok, wide} = ReportLedger.open(ReportLedger.new(), {"wide", 1}, 10_000)

    full =
      Enum.reduce(1..16, wide, fn sequence, ledger ->
        {:ok, ledger} = ReportLedger.register(ledger, {"wide", 1}, sequence, 64, make_ref())
        ledger
      end)

    assert :error = ReportLedger.register(full, {"wide", 1}, 17, 64, make_ref())

    sessions =
      Enum.reduce(1..8, ReportLedger.new(), fn index, ledger ->
        {:ok, ledger} = ReportLedger.open(ledger, {"s#{index}", 1}, 16)
        ledger
      end)

    bytes =
      Enum.reduce(1..8, sessions, fn index, ledger ->
        {:ok, ledger} =
          ReportLedger.register(ledger, {"s#{index}", 1}, index, 131_072, make_ref())

        ledger
      end)

    assert :error = ReportLedger.register(bytes, {"s1", 1}, 9, 2, make_ref())

    frames =
      Enum.reduce(1..64, sessions, fn sequence, ledger ->
        stream = {"s#{rem(sequence - 1, 8) + 1}", 1}
        {:ok, ledger} = ReportLedger.register(ledger, stream, sequence, 2, make_ref())
        ledger
      end)

    assert :error = ReportLedger.register(frames, {"s1", 1}, 65, 2, make_ref())
  end

  test "WTH-B02 exact retirement discards validated reports and forbids resurrection" do
    {:ok, ledger} = ReportLedger.open(ReportLedger.new(), {"s1", 1}, 64)
    {:ok, ledger} = ReportLedger.open(ledger, {"s2", 1}, 64)
    token = make_ref()
    {:ok, ledger} = ReportLedger.register(ledger, {"s1", 1}, 1, 128, make_ref())
    {:ok, ledger} = ReportLedger.register(ledger, {"s2", 1}, 2, 128, token)
    assert :error = ReportLedger.retire(ledger, {"s1", 1}, 2)
    assert :error = ReportLedger.retire(ledger, {"s1", 1}, 0)
    assert :error = ReportLedger.retire(ledger, {"unknown", 1}, 0)
    {:ok, retired} = ReportLedger.retire(ledger, {"s1", 1}, 1)
    refute ReportLedger.live?(retired, {"s1", 1})
    assert :error = ReportLedger.retire(retired, {"s1", 1}, 1)
    assert :error = ReportLedger.register(retired, {"s1", 1}, 3, 64, make_ref())
    assert {%{report_sequence: 1, acknowledged_bytes: 128}, retired} = ReportLedger.advance(retired)
    {:ok, retired} = ReportLedger.consume(retired, {"s2", 1}, 2, token)
    assert {%{report_sequence: 2, acknowledged_bytes: 256}, _} = ReportLedger.advance(retired)

    # A stream that never transmitted retires at sequence zero.
    {:ok, empty} = ReportLedger.open(ReportLedger.new(), {"empty", 1}, 1)
    assert {:ok, empty} = ReportLedger.retire(empty, {"empty", 1}, 0)
    assert {:ok, _} = ReportLedger.open(empty, {"empty", 1}, 1)
  end

  test "WTH-B02 stream admission is bounded and exact" do
    ledger =
      Enum.reduce(1..64, ReportLedger.new(), fn index, ledger ->
        {:ok, ledger} = ReportLedger.open(ledger, {"s#{index}", 1}, 1)
        ledger
      end)

    assert :error = ReportLedger.open(ledger, {"s65", 1}, 1)
    assert :error = ReportLedger.open(ledger, {"s1", 1}, 1)
    assert {:ok, _} = ReportLedger.open(ledger |> retire_one(), {"s65", 1}, 1)

    for invalid <- [{"", 1}, {String.duplicate("s", 65), 1}, {"s", 0}, {:s, 1}, "s"] do
      assert :error = ReportLedger.open(ReportLedger.new(), invalid, 1)
    end

    assert :error = ReportLedger.open(ReportLedger.new(), {"s", 1}, 0)
    assert :error = ReportLedger.open(ReportLedger.new(), {"s", 1}, 10_001)
    refute inspect(ReportLedger.new()) =~ "streams"
  end

  defp retire_one(ledger) do
    {:ok, ledger} = ReportLedger.retire(ledger, {"s1", 1}, 0)
    ledger
  end
end
