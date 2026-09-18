Code.require_file("support/messages.exs", __DIR__)

alias Wotex.CoAP.Bench.Messages
alias Wotex.CoAP.{Blockwise, Codec, Message, Observe}
alias Wotex.CoAP.Observation.Report

size = 512
peer = Messages.peer(23)

# Each notification pairs a representation size with one RFC 7641 freshness
# case; every case is fresh, so the predicate evaluates its full expression.
cases = [
  {"64-byte report, in order", 64, {10, 11, 250}},
  {"512-byte report, 24-bit wraparound", 512, {16_777_215, 3, 250}},
  {"16 KiB blockwise report, 128 s escape", 16_384, {700, 500, 129_000}}
]

inputs =
  Map.new(cases, fn {label, total, {previous, current, elapsed}} ->
    replies = Messages.download_replies(Messages.body(total), size)
    %Message{options: options} = first = Map.fetch!(replies, 0)
    first = %{first | options: [{6, Codec.uint(current)} | options]}
    continuation = %{Messages.request(1, [{11, "properties"}, {11, "log"}]) | token: "cont"}
    {:ok, report} = Report.new(first, 0)
    {{:ok, message}, _} = Blockwise.continue(continuation, first, [], replies, peer)
    {:ok, complete} = Report.complete(report, message)

    {label,
     %{
       sequence: {previous, current, elapsed},
       first: first,
       continuation: continuation,
       replies: replies,
       report: report,
       complete: complete
     }}
  end)

Benchee.run(
  %{
    "decide freshness" => fn %{sequence: {previous, current, elapsed}} ->
      true = Observe.fresh?(previous, current, elapsed)
    end,
    "validate first report" => fn %{first: first} -> {:ok, _} = Report.new(first, 0) end,
    "continue and complete body" => fn context ->
      %{continuation: continuation, first: first, replies: replies, report: report} = context
      {{:ok, message}, _} = Blockwise.continue(continuation, first, [], replies, peer)
      {:ok, _} = Report.complete(report, message)
    end,
    "revalidate completed report" => fn %{complete: complete} ->
      :ok = Report.validate(complete)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/observe.md",
     title: "# Observe freshness and report admission",
     description: """
     `Wotex.CoAP.Observe.fresh?/3` 24-bit serial arithmetic for an in-order
     sequence, a wraparound and the 128-second escape, and
     `Wotex.CoAP.Observation.Report` over notifications of 64 bytes, 512 bytes
     and 16 KiB. `Report.new/2` validates the first datagram and decodes its
     metadata; the completion job continues the representation with
     `Wotex.CoAP.Blockwise.continue/5` against a pure in-process exchange
     function (none for the single-datagram cases, 31 exchanges for 16 KiB in
     512-byte blocks) and admits the body with `Report.complete/2`;
     `Report.validate/1` rechecks a retained completed report.
     """}
  ]
)
