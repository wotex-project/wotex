Code.require_file("support/messages.exs", __DIR__)

alias Wotex.CoAP.Bench.Messages
alias Wotex.CoAP.LinkFormat

inputs = Map.new([4, 32, 256], &{"#{&1} links", Messages.links(&1)})

Benchee.run(
  %{
    "decode with default limits" => fn body -> {:ok, [_ | _]} = LinkFormat.decode(body) end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/link_format.md",
     title: "# CoRE Link Format discovery parsing",
     description: """
     `Wotex.CoAP.LinkFormat.decode/2` over `/.well-known/core` bodies of four,
     32 and 256 links (the default link limit), from 334 bytes to about 24 KiB.
     The first link announces a Thing Description (`rt="wot.thing";ct=432`);
     each further link carries quoted relation-type and interface lists, a
     Content-Format, a size, the Observe flag and a quoted title with escaped
     quotes. Every link target and attribute is syntax-checked under the default
     body, link, attribute and token limits.
     """}
  ]
)
