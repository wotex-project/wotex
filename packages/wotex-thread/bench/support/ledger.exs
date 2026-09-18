defmodule Wotex.Thread.Bench.Ledger do
  @moduledoc false

  # Report windows for `Wotex.Thread.OpenThread.ReportLedger`: State report
  # sequences distributed round-robin over live streams, each report the size
  # of an encoded State snapshot line. Each input carries the ledger with its
  # streams open, with every report registered and with every report consumed.

  alias Wotex.Thread.OpenThread.ReportLedger

  @report_bytes 212

  @spec inputs() :: %{String.t() => map()}
  def inputs do
    %{
      "1 report on 1 stream" => input(1, 1),
      "16 reports on 1 stream" => input(16, 1),
      "64 reports on 4 streams" => input(64, 4)
    }
  end

  @spec register_all(ReportLedger.t(), [tuple()]) :: ReportLedger.t()
  def register_all(ledger, reports) do
    Enum.reduce(reports, ledger, fn {stream, sequence, token}, ledger ->
      {:ok, ledger} = ReportLedger.register(ledger, stream, sequence, @report_bytes, token)
      ledger
    end)
  end

  @spec consume_all(ReportLedger.t(), [tuple()]) :: ReportLedger.t()
  def consume_all(ledger, reports) do
    Enum.reduce(reports, ledger, fn {stream, sequence, token}, ledger ->
      {:ok, ledger} = ReportLedger.consume(ledger, stream, sequence, token)
      ledger
    end)
  end

  defp input(count, stream_count) do
    streams = Enum.map(1..stream_count, &{"s#{&1}", 1})

    opened =
      Enum.reduce(streams, ReportLedger.new(), fn stream, ledger ->
        {:ok, ledger} = ReportLedger.open(ledger, stream, 1000)
        ledger
      end)

    reports =
      Enum.map(1..count, fn sequence ->
        {Enum.at(streams, rem(sequence - 1, stream_count)), sequence, make_ref()}
      end)

    registered = register_all(opened, reports)

    %{
      count: count,
      reports: reports,
      opened: opened,
      registered: registered,
      consumed: consume_all(registered, reports)
    }
  end
end
