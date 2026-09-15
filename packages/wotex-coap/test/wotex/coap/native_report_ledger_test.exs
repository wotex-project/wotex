defmodule Wotex.CoAP.NativeReportLedgerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP.Native.ReportLedger

  @maximum_counter 0xFFFFFFFFFFFFFFFF

  test "WCO-N03 initial credit opens one exact eight-frame window" do
    assert {:ok, ledger} = ReportLedger.new("subscription", 17)
    assert :error = ReportLedger.account_frame(ledger, "subscription", 17, 1, 1)

    assert {:ok, %{generation: 17, ack_seq: 0}, in_flight} = ReportLedger.next_credit(ledger)
    assert {:ok, nil, ^in_flight} = ReportLedger.next_credit(in_flight)
    assert :error = ReportLedger.credit_accepted(in_flight, 1)
    assert {:ok, started} = ReportLedger.credit_accepted(in_flight, 0)
    assert {:ok, nil, ^started} = ReportLedger.next_credit(started)
    assert :error = ReportLedger.credit_accepted(started, 0)
  end

  test "WCO-N03 report sequences and outstanding frame and byte bounds are exact" do
    ledger = started()

    full =
      Enum.reduce(1..8, ledger, fn sequence, current ->
        assert {:ok, next} =
                 ReportLedger.account_frame(current, "subscription", 17, sequence, 131_072)

        next
      end)

    assert full.last_sequence == 8
    assert full.outstanding_bytes == 1_048_576
    assert map_size(full.records) == 8
    assert :error = ReportLedger.account_frame(full, "subscription", 17, 9, 1)

    assert {:ok, %{ack_seq: 8}, in_flight} = ReportLedger.next_credit(full)
    assert :error = ReportLedger.account_frame(in_flight, "subscription", 17, 9, 1)
    assert {:ok, cleared} = ReportLedger.credit_accepted(in_flight, 8)
    assert cleared.outstanding_bytes == 0 and cleared.records == %{}
    assert {:ok, _} = ReportLedger.account_frame(cleared, "subscription", 17, 9, 1)
  end

  test "WCO-N03 cumulative credit waits for exact report delivery and contiguous accounting" do
    token = make_ref()
    ledger = started()
    assert {:ok, ledger} = ReportLedger.account_frame(ledger, "subscription", 17, 1, 100)
    assert {:ok, ledger} = ReportLedger.retain_report(ledger, "subscription", 17, 2, 200, token)
    assert {:ok, ledger} = ReportLedger.account_frame(ledger, "subscription", 17, 3, 300)

    assert {:ok, %{generation: 17, ack_seq: 1}, in_flight} =
             ReportLedger.next_credit(ledger)

    assert {:ok, ledger} = ReportLedger.credit_accepted(in_flight, 1)
    assert ledger.outstanding_bytes == 500
    assert :ignore = ReportLedger.consume_report(ledger, "subscription", 17, 2, make_ref())
    assert :ignore = ReportLedger.consume_report(ledger, "other", 17, 2, token)
    assert {:ok, ledger} = ReportLedger.consume_report(ledger, "subscription", 17, 2, token)
    assert :ignore = ReportLedger.consume_report(ledger, "subscription", 17, 2, token)

    assert {:ok, %{ack_seq: 3}, in_flight} = ReportLedger.next_credit(ledger)
    assert {:ok, nil, ^in_flight} = ReportLedger.next_credit(in_flight)
    assert {:ok, cleared} = ReportLedger.credit_accepted(in_flight, 3)
    assert cleared.acknowledged_sequence == 3
    assert cleared.outstanding_bytes == 0 and cleared.records == %{}
  end

  test "WCO-N03 at most one complete report waits for public delivery" do
    first = make_ref()
    second = make_ref()
    ledger = started()
    assert {:ok, ledger} = ReportLedger.retain_report(ledger, "subscription", 17, 1, 100, first)
    assert :error = ReportLedger.retain_report(ledger, "subscription", 17, 2, 100, second)
    assert {:ok, ledger} = ReportLedger.consume_report(ledger, "subscription", 17, 1, first)
    assert {:ok, ledger} = ReportLedger.retain_report(ledger, "subscription", 17, 2, 100, second)
    assert ledger.last_sequence == 2 and map_size(ledger.records) == 2
  end

  test "WCO-N-F15 accounts one inline and five streamed report frames" do
    inline = make_ref()
    streamed = make_ref()
    ledger = started()
    frame_bytes = [44_000, 180, 44_000, 160, 100, 300]

    assert {:ok, ledger} =
             ReportLedger.retain_report(ledger, "subscription", 17, 1, hd(frame_bytes), inline)

    assert {:ok, ledger} = ReportLedger.consume_report(ledger, "subscription", 17, 1, inline)

    ledger =
      frame_bytes
      |> Enum.slice(1, 4)
      |> Enum.with_index(2)
      |> Enum.reduce(ledger, fn {bytes, sequence}, current ->
        {:ok, next} =
          ReportLedger.account_frame(current, "subscription", 17, sequence, bytes)

        next
      end)

    assert {:ok, ledger} =
             ReportLedger.retain_report(
               ledger,
               "subscription",
               17,
               6,
               List.last(frame_bytes),
               streamed
             )

    assert {:ok, ledger} = ReportLedger.consume_report(ledger, "subscription", 17, 6, streamed)
    assert ledger.last_sequence == 6 and map_size(ledger.records) == 6
    assert ledger.outstanding_bytes == Enum.sum(frame_bytes)
    assert {:ok, %{ack_seq: 6}, in_flight} = ReportLedger.next_credit(ledger)
    assert {:ok, cleared} = ReportLedger.credit_accepted(in_flight, 6)
    assert cleared.outstanding_bytes == 0 and cleared.records == %{}
  end

  test "WCO-N03 a credit in flight does not hide later consumed frames" do
    ledger = started()
    assert {:ok, ledger} = ReportLedger.account_frame(ledger, "subscription", 17, 1, 10)
    assert {:ok, %{ack_seq: 1}, in_flight} = ReportLedger.next_credit(ledger)
    assert {:ok, in_flight} = ReportLedger.account_frame(in_flight, "subscription", 17, 2, 20)
    assert {:ok, nil, ^in_flight} = ReportLedger.next_credit(in_flight)
    assert {:ok, ledger} = ReportLedger.credit_accepted(in_flight, 1)
    assert ledger.outstanding_bytes == 20
    assert {:ok, %{ack_seq: 2}, _} = ReportLedger.next_credit(ledger)
  end

  test "WCO-N03 the final uint64 sequence is accepted once without wrap" do
    ledger = %{
      started()
      | last_sequence: @maximum_counter - 1,
        acknowledged_sequence: @maximum_counter - 1
    }

    assert {:ok, ledger} =
             ReportLedger.account_frame(
               ledger,
               "subscription",
               17,
               @maximum_counter,
               1
             )

    assert {:ok, %{ack_seq: @maximum_counter}, in_flight} = ReportLedger.next_credit(ledger)
    assert {:ok, ledger} = ReportLedger.credit_accepted(in_flight, @maximum_counter)

    assert :error =
             ReportLedger.account_frame(ledger, "subscription", 17, @maximum_counter, 1)
  end

  test "WCO-N03 identifiers, generations, line sizes and internal calls fail closed" do
    for {id, generation} <- [
          {"", 17},
          {"line\nbreak", 17},
          {String.duplicate("x", 65), 17},
          {"subscription", 0},
          {"subscription", @maximum_counter + 1},
          {:subscription, 17}
        ] do
      assert :error = ReportLedger.new(id, generation)
    end

    ledger = started()

    for {id, generation, sequence, bytes} <- [
          {"other", 17, 1, 1},
          {"subscription", 18, 1, 1},
          {"subscription", 17, 0, 1},
          {"subscription", 17, 2, 1},
          {"subscription", 17, 1, 0},
          {"subscription", 17, 1, 131_073},
          {"subscription", 17, 1.0, 1},
          {"subscription", 17, 1, 1.0}
        ] do
      assert :error = ReportLedger.account_frame(ledger, id, generation, sequence, bytes)
    end

    assert :error = ReportLedger.retain_report(ledger, "subscription", 17, 1, 1, nil)
    assert :error = ReportLedger.next_credit(:invalid)
    assert :error = ReportLedger.credit_accepted(:invalid, 0)
    assert :error = ReportLedger.consume_report(:invalid, "subscription", 17, 1, make_ref())
    refute inspect(ledger) =~ "subscription"
  end

  defp started do
    {:ok, ledger} = ReportLedger.new("subscription", 17)
    {:ok, %{ack_seq: 0}, ledger} = ReportLedger.next_credit(ledger)
    {:ok, ledger} = ReportLedger.credit_accepted(ledger, 0)
    ledger
  end
end
