Benchee.run(
  %{"version/0" => fn -> "0.1.0" = Wotex.Routines.version() end},
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/version.md",
     title: "# Wotex Routines entry point",
     description: "`Wotex.Routines.version/0`, the generated entry point."}
  ]
)
