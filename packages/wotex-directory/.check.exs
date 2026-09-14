Code.require_file("bin/evidence.exs")

tools = [
  {:deps_get, command: "mix deps.get --check-locked"},
  {:compiler, command: "mix compile --warnings-as-errors"},
  {:unused_deps, command: "mix deps.unlock --check-unused"},
  {:formatter, command: "mix format --check-formatted"},
  {:mix_audit, command: "mix deps.audit"},
  {:credo, command: "mix credo --strict"},
  {:doctor, command: "mix doctor"},
  {:sobelow, false},
  {:ex_doc, command: "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "docs"}},
  {:ex_unit, false},
  {:dialyzer, command: "mix dialyzer"},
  {:gettext, false},
  {:npm_test, false},
  {:coverage, command: "mix coveralls", env: %{"MIX_ENV" => "test"}},
  {:hex_audit, command: "mix hex.audit"},
  {:boundary, command: "elixir bin/check_boundary.exs"},
  {:application, command: "mix run --no-start bin/check_application_free.exs"},
  {:archive, command: "mix run --no-start bin/check_archive.exs"},
  {:diff, command: "git diff --check"}
]

root = DirectoryEvidence.begin(tools)
environment = %{"WOTEX_EVIDENCE_ROOT" => root}

required =
  for {name, options} <- tools, is_list(options), name != :compiler, do: {name, [status: 0]}

tools = Keyword.update!(tools, :archive, &Keyword.put(&1, :env, environment))
tools = Keyword.put(tools, :compiler, command: "elixir bin/check_compiler.exs", env: environment)

[
  parallel: false,
  retry: false,
  skipped: false,
  tools:
    tools ++
      [
        {:evidence,
         command: "mix run --no-start bin/check_evidence.exs", deps: required, env: environment}
      ]
]
