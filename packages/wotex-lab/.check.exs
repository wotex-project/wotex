[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get --check-locked"},
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:formatter, command: "mix format --check-formatted"},
    {:credo, command: "mix credo --strict"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:mix_audit, command: "mix deps.audit --ignore-file .mix_audit.ignore"},
    {:hex_audit, command: "mix hex.audit"},
    {:dialyzer, command: "mix dialyzer"},
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs --warnings-as-errors"},
    {:ex_unit, command: "mix coveralls"},
    {:contracts, command: "mix run --no-start bin/check_contracts.exs"},
    {:source_cohort,
     if(System.get_env("WOTEX_PATH_DEPS") == "1",
       do: [command: "elixir bin/check_source_cohort.exs"],
       else: false
     )},
    {:graph, command: "mix run --no-start bin/check_graph.exs"},
    {:typescript_client, command: "mix run --no-start bin/generate_typescript_client.exs --check"},
    {:oci_source, command: "elixir bin/check_oci_source.exs"},
    {:boundary, command: "elixir bin/check_boundary.exs"},
    {:package, command: "mix run --no-start bin/check_package.exs"},
    {:archive_consumer, command: "mix run --no-start bin/check_archive_consumer.exs"},
    {:workbench_archive, command: "mix run --no-start bin/check_workbench_archive.exs"}
  ]
]
