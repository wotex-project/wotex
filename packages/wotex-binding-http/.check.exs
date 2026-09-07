[
  parallel: false,
  skipped: true,
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors --force"},
    {:formatter, command: "mix format --check-formatted"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:credo, command: "mix credo --strict"},
    {:hex_audit, command: "mix hex.audit"},
    {:mix_audit, command: "mix deps.audit"},
    {:doctor, command: "mix doctor --summary"},
    {:dialyzer, command: "mix dialyzer"},
    {:ex_doc, command: "mix docs --warnings-as-errors"},
    {:ex_unit, false},
    {:coveralls, command: "env MIX_ENV=test mix coveralls"},
    {:boundary, command: "elixir bin/check_boundary.exs"},
    {:archive, command: "mix run --no-start bin/check_archive.exs"}
  ]
]
