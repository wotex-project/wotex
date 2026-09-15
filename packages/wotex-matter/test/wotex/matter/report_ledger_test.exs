defmodule Wotex.Matter.ReportLedgerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Native.ReportLedger

  test "WMA-B02 retirement consumes only its generation and waits for the contiguous prefix" do
    {:ok, ledger} = ReportLedger.open(ReportLedger.new(), {"stream", 1})
    {:ok, ledger} = ReportLedger.open(ledger, {"stream", 2})
    old_token = make_ref()
    new_token = make_ref()
    {:ok, ledger} = ReportLedger.register(ledger, {"stream", 2}, 1, 128, new_token)
    {:ok, ledger} = ReportLedger.register(ledger, {"stream", 1}, 2, 256, old_token)

    assert :error = ReportLedger.retire(ledger, {"stream", 1}, 1)
    assert {:ok, retired} = ReportLedger.retire(ledger, {"stream", 1}, 2)
    assert {nil, ^retired} = ReportLedger.advance(retired)
    refute retired.pending[1].consumed
    assert retired.pending[2].consumed
    assert :error = ReportLedger.retire(retired, {"stream", 1}, 2)
    assert :error = ReportLedger.register(retired, {"stream", 1}, 3, 128, make_ref())
    assert :ignore = ReportLedger.consume(retired, {"stream", 1}, 2, old_token)

    assert {:ok, consumed} = ReportLedger.consume(retired, {"stream", 2}, 1, new_token)

    assert {%{report_sequence: 2, acknowledged_bytes: 384}, advanced} =
             ReportLedger.advance(consumed)

    assert advanced.pending == %{}
    assert advanced.streams == %{{"stream", 2} => 1}
    assert {:ok, empty} = ReportLedger.retire(advanced, {"stream", 2}, 1)
    assert {nil, ^empty} = ReportLedger.advance(empty)
    assert empty.streams == %{}
  end

  test "WMA-B02 consumption binds the exact stream and token and cannot replay credit" do
    {:ok, ledger} = ReportLedger.open(ReportLedger.new(), "stream")
    token = make_ref()
    {:ok, ledger} = ReportLedger.register(ledger, "stream", 1, 128, token)
    assert :ignore = ReportLedger.consume(ledger, "other", 1, token)
    assert :ignore = ReportLedger.consume(ledger, "stream", 1, make_ref())
    assert :ignore = ReportLedger.consume(ledger, "stream", 2, token)
    assert {:ok, consumed} = ReportLedger.consume(ledger, "stream", 1, token)
    assert :ignore = ReportLedger.consume(consumed, "stream", 1, token)

    assert {%{report_sequence: 1, acknowledged_bytes: 128}, advanced} =
             ReportLedger.advance(consumed)

    assert :ignore = ReportLedger.consume(advanced, "stream", 1, token)
    assert {nil, ^advanced} = ReportLedger.advance(advanced)
    assert ledger.acknowledged_sequence == 0
    assert map_size(ledger.pending) == 1
  end

  test "WMA-B02 frame and byte reservations reject excess before retaining a report" do
    {:ok, empty} = ReportLedger.open(ReportLedger.new(), "stream")

    for {count, bytes} <- [{64, 1}, {8, 131_072}] do
      full =
        Enum.reduce(1..count, empty, fn sequence, ledger ->
          {:ok, next} = ReportLedger.register(ledger, "stream", sequence, bytes, make_ref())
          next
        end)

      assert :error = ReportLedger.register(full, "stream", count + 1, 1, make_ref())
      assert {:ok, retired} = ReportLedger.retire(full, "stream", count)

      assert {%{report_sequence: ^count, acknowledged_bytes: total}, cleared} =
               ReportLedger.advance(retired)

      assert total == count * bytes
      assert cleared.pending == %{} and cleared.streams == %{}
    end

    for bytes <- [0, -1, 131_073, "128", 1.5] do
      assert :error = ReportLedger.register(empty, "stream", 1, bytes, make_ref())
    end
  end

  test "WMA-B02 sequence, cumulative byte and stream identity counters remain bounded" do
    {:ok, ledger} = ReportLedger.open(ReportLedger.new(), "stream")
    assert :error = ReportLedger.open(ledger, "stream")
    assert :error = ReportLedger.register(ledger, "absent", 1, 128, make_ref())
    assert :error = ReportLedger.register(ledger, "stream", 2, 128, make_ref())
    assert :error = ReportLedger.register(ledger, "stream", 1, 128, nil)
    maximum = 0xFFFFFFFFFFFFFFFF
    exhausted_sequence = %{ledger | next_sequence: maximum}
    assert :error = ReportLedger.register(exhausted_sequence, "stream", maximum, 1, make_ref())
    nearly_full = %{ledger | acknowledged_bytes: maximum - 10}
    assert {:ok, _} = ReportLedger.register(nearly_full, "stream", 1, 10, make_ref())
    assert :error = ReportLedger.register(nearly_full, "stream", 1, 11, make_ref())

    full =
      Enum.reduce(1..128, ReportLedger.new(), fn stream, current ->
        {:ok, next} = ReportLedger.open(current, stream)
        next
      end)

    assert :error = ReportLedger.open(full, 129)
    assert {:ok, retired} = ReportLedger.retire(full, 1, 0)
    assert {:ok, _} = ReportLedger.open(retired, 129)
  end
end
