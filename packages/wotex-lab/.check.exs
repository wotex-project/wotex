[
  parallel: false,
  retry: false,
  skipped: false,
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors"},
    # Lab as a consumer without any optional dependency builds it (WLB.08):
    # compiled without them, warnings as errors, in its own build path so the
    # normal build is untouched; bin/check_optional_deps.exs then proves the
    # modules behind those seams are absent and the features that need them
    # answer with their typed errors. The docs environment has the production
    # closure plus ExDoc, none of whose members needs an optional dependency.
    # The build path is absolute: Elixir 1.18 hands MIX_BUILD_PATH unexpanded
    # to rebar3, which runs in the dependency's directory.
    {:optional_deps,
     command:
       "mix do compile --no-optional-deps --warnings-as-errors + " <>
         "run --no-compile --no-deps-check bin/check_optional_deps.exs",
     env: %{
       "MIX_ENV" => "docs",
       "MIX_BUILD_PATH" => Path.expand("_build/no_optional_deps", __DIR__)
     }},
    {:deps_get, command: "mix deps.get --check-locked"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:formatter, command: "mix format --check-formatted"},
    {:mix_audit, command: "mix deps.audit --ignore-file .mix_audit.ignore"},
    {:hex_audit, command: "mix hex.audit"},
    {:credo, command: "mix credo --strict"},
    {:doctor, command: "mix doctor --summary"},
    {:sobelow, false},
    {:ex_doc, command: "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "docs"}},
    {:ex_unit, false},
    {:coverage, command: "mix coveralls", env: %{"MIX_ENV" => "test"}},
    {:dialyzer, command: "mix dialyzer"},
    # First-party C, C++ and Rust code through the root tasks (see
    # tooling/packages.yaml): changed-line formatting, static analysis and the
    # native tests, which build into a cached workspace outside the repository.
    {:native_format,
     command: "mix native.lint --no-clippy --package wotex-lab",
     cd: "../..",
     fix: "mix native.lint --fix --no-clippy --package wotex-lab"},
    {:native_lint,
     command: "mix native.lint --tidy --no-format --package wotex-lab",
     cd: "../..",
     deps: [:native_format]},
    {:native_test,
     command: "mix native.test --package wotex-lab", cd: "../..", deps: [:native_lint]},
    {:contracts, command: "mix run --no-start bin/check_contracts.exs"},
    {:graph, command: "mix run --no-start bin/check_graph.exs"},
    {:api_surface, command: "mix run --no-start bin/generate_api_surface.exs --check"},
    {:compatibility_review,
     command: "mix run --no-start bin/generate_compatibility_review.exs --check",
     deps: [:api_surface]},
    {:nerves_source, command: "elixir bin/check_nerves_source.exs"},
    {:boundary, command: "elixir bin/check_boundary.exs"},
    # The reference hosts are separate Mix projects with their own gates and
    # locks; they inherit WOTEX_PATH_DEPS=1 from this gate. The Workbench's
    # `check` alias fetches its dependencies first. Phoenix Storybook then
    # qualifies the Workbench's tracked production asset graph. The Nerves
    # host runs its host cohort (MIX_TARGET=host) and never needs the rpi4
    # toolchain.
    {:workbench, command: "mix check --no-retry", cd: "hosts/workbench"},
    {:storybook_host,
     command: "mix do deps.get --check-locked + check --no-retry",
     cd: "hosts/storybook",
     deps: [:workbench]},
    {:nerves_host,
     command: "mix do deps.get --check-locked + check --no-retry",
     cd: "hosts/nerves",
     env: %{
       "DOC_SHELL_CANDIDATE" => "",
       "MIX_TARGET" => "host",
       "PHOENIX_ASSETS_CANDIDATE" => ""
     }},
    {:package, command: "mix run --no-start bin/check_package.exs", deps: [coverage: [status: 0]]},
    {:diff, command: "git diff --check"},
    {:gettext, false},
    {:npm_test, false}
  ]
]
