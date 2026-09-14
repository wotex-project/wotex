Code.require_file("evidence.exs", __DIR__)

defmodule Wotex.Directory.CheckReleaseEvidence do
  @moduledoc false

  @checks [
    {:deps_get, "mix", ["deps.get", "--check-locked"], %{}},
    {:compiler, "elixir", ["bin/check_compiler.exs"], %{}},
    {:formatter, "mix", ["format", "--check-formatted"], %{}},
    {:credo, "mix", ["credo", "--strict"], %{}},
    {:unused_deps, "mix", ["deps.unlock", "--check-unused"], %{}},
    {:mix_audit, "mix", ["deps.audit"], %{}},
    {:hex_audit, "mix", ["hex.audit"], %{}},
    {:dialyzer, "mix", ["dialyzer"], %{}},
    {:doctor, "mix", ["doctor"], %{}},
    {:docs, "mix", ["docs", "--warnings-as-errors"], %{"MIX_ENV" => "docs"}},
    {:coverage, "mix", ["coveralls"], %{"MIX_ENV" => "test"}},
    {:boundary, "elixir", ["bin/check_boundary.exs"], %{}},
    {:application, "mix", ["run", "--no-start", "bin/check_application_free.exs"], %{}},
    {:archive, "mix", ["package"], %{}},
    {:diff, "git", ["diff", "--check"], %{}}
  ]

  def run do
    root = DirectoryEvidence.begin(evidence_checks())

    Enum.each(@checks, fn {name, executable, arguments, environment} ->
      run_check!(name, executable, arguments, environment, root)
    end)

    DirectoryEvidence.finish!(root)
  end

  defp evidence_checks do
    for {name, executable, arguments, environment} <- @checks do
      {name,
       [
         command: Enum.join([executable | arguments], " "),
         env: environment
       ]}
    end
  end

  defp run_check!(name, executable, arguments, environment, root) do
    environment = Map.put(environment, "WOTEX_EVIDENCE_ROOT", root)

    {output, status} =
      System.cmd(executable, arguments,
        env: Map.to_list(environment),
        stderr_to_stdout: true
      )

    IO.write(output)

    if status != 0,
      do: raise("release evidence check #{name} failed with exit status #{status}")
  end
end

Wotex.Directory.CheckReleaseEvidence.run()
