defmodule WotexLabWorkbench.CheckRunner do
  @moduledoc false

  @checks [
    {:deps_get, "mix", ["deps.get", "--check-locked"], "test"},
    {:frontend_dependencies, "mix", ["assets.setup"], "test"},
    {:compiler, "mix", ["compile", "--warnings-as-errors"], "test"},
    {:frontend, "mix", ["assets.check"], "test"},
    {:formatter, "mix", ["format", "--check-formatted"], "test"},
    {:credo, "mix", ["credo", "--strict"], "test"},
    {:unused_deps, "mix", ["deps.unlock", "--check-unused"], "test"},
    {:mix_audit, "mix", ["deps.audit"], "test"},
    {:hex_audit, "mix", ["hex.audit"], "test"},
    {:dialyzer, "mix", ["dialyzer"], "test"},
    {:doctor, "mix", ["doctor"], "test"},
    {:ex_doc, "mix", ["docs", "--warnings-as-errors"], "docs"},
    {:ex_unit, "mix", ["coveralls"], "test"},
    {:boundary, "elixir", ["bin/check_boundary.exs"], "test"}
  ]

  @doc false
  @spec run([String.t()]) :: :ok
  def run(args) do
    refuse_unknown_args(args)
    root = Path.expand("..", __DIR__)

    Enum.each(@checks, fn {name, executable, command, environment} ->
      Mix.shell().info("=> running #{name}")

      {_, status} =
        System.cmd(executable, command,
          cd: root,
          env: [{"MIX_ENV", environment}],
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise("#{name} failed with exit status #{status}")
    end)

    Mix.shell().info("=> all #{length(@checks)} workbench checks passed")
  end

  defp refuse_unknown_args(args) do
    case args -- ["--no-retry"] do
      [] -> :ok
      unknown -> Mix.raise("unknown check options: #{Enum.join(unknown, " ")}")
    end
  end
end
