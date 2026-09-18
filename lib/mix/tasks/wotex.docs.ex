defmodule Mix.Tasks.Wotex.Docs do
  @shortdoc "Builds one package's HexDocs"

  @moduledoc """
  Builds the HexDocs of `packages/NAME` with `mix docs` and
  `WOTEX_PATH_DEPS=1`, in `MIX_ENV=docs` when the package declares a
  `:docs` environment (otherwise the default environment). Further
  arguments are passed to `mix docs`, e.g. `--warnings-as-errors`. The root
  alias is `mix docs.pkg`.

      mix wotex.docs NAME [ARGS...]
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Runner

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {name, extra} = parse_args(args)
    manifest = Manifest.load!()
    CLI.package!(manifest, name)
    path = Manifest.absolute_path(name, manifest)
    env = docs_env(File.read!(Path.join(path, "mix.exs")))

    case Runner.run(path, ["docs" | extra], mix_env: env) do
      0 -> Mix.shell().info("packages/#{name}/doc/index.html")
      status -> CLI.fail("packages/#{name}: mix docs exited with #{status}")
    end

    :ok
  end

  @doc "Splits the package name from the extra `mix docs` arguments."
  @spec parse_args([String.t()]) :: {String.t(), [String.t()]}
  def parse_args([name | extra]) do
    if String.starts_with?(name, "-"), do: Mix.raise("usage: mix docs.pkg NAME [ARGS...]")
    {name, extra}
  end

  def parse_args([]), do: Mix.raise("usage: mix docs.pkg NAME [ARGS...]")

  @doc """
  `"docs"` when a package's `mix.exs` text names a `:docs` environment,
  else `nil` (the default environment).
  """
  @spec docs_env(String.t()) :: String.t() | nil
  def docs_env(mix_exs), do: if(mix_exs =~ ~r/:docs\b/, do: "docs")
end
