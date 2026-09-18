Code.require_file("support/ledger.exs", __DIR__)

alias Wotex.Thread.Bench.Ledger
alias Wotex.Thread.OpenThread.ReportLedger

Benchee.run(
  %{
    "register transmitted reports" => fn %{opened: ledger, reports: reports} ->
      Ledger.register_all(ledger, reports)
    end,
    "admit delivery of every report" => fn %{registered: ledger, reports: reports} ->
      Ledger.consume_all(ledger, reports)
    end,
    "propose cumulative acknowledgement" => fn %{consumed: ledger, count: count} ->
      {%{report_sequence: ^count}, _} = ReportLedger.advance(ledger)
    end
  },
  inputs: Ledger.inputs(),
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/report_ledger.md",
     title: "# Thread native report credit ledger",
     description: """
     `Wotex.Thread.OpenThread.ReportLedger`, the BEAM side of the native State
     report credit: `register/5` admits each transmitted report in sequence
     under the per-stream and per-session frame and byte bounds, `consume/4`
     records the stream owner's delivery admission with its token, and
     `advance/1` proposes the contiguous cumulative acknowledgement. Windows
     hold 1 report, 16 reports on one stream (the per-stream limit) and 64
     reports over four streams (the session frame limit), each of 212 encoded
     bytes.
     """}
  ]
)
