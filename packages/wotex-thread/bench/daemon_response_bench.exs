alias Wotex.Thread.Daemon

responses = %{
  "state" => {:state, "state", "leader"},
  "rloc16" => {:rloc16, "rloc16", "4400"},
  "network name" => {:network_name, "networkname", "wotex-bench"},
  "version" =>
    {:version, "version", "OPENTHREAD/thread-reference-20230706; POSIX; Jul  6 2023 00:00:00"}
}

inputs =
  Map.new(responses, fn {label, {type, command, value}} ->
    partial = "#{command}\r\n#{value}\r\n"
    {label, %{type: type, complete: partial <> "Done\r\n> ", partial: partial}}
  end)

Benchee.run(
  %{
    "parse complete response" => fn %{type: type, complete: bytes} ->
      {:ok, _} = Daemon.parse(bytes, type)
    end,
    "detect incomplete response" => fn %{type: type, partial: bytes} ->
      :more = Daemon.parse(bytes, type)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/daemon_response.md",
     title: "# Thread ot-daemon response parsing",
     description: """
     `Wotex.Thread.Daemon.parse/2` over the four read commands of the
     `ot-daemon` client: each complete response carries the command echo, one
     value line, `Done` and the next prompt with CRLF line endings; the
     incomplete response stops before `Done` and must yield `:more`. Parsing
     checks UTF-8, strips the echo and prompt, rejects remote errors and types
     the value (the RLOC16 as an integer).
     """}
  ]
)
