defmodule Mix.Tasks.Wotex.Native.Build do
  @shortdoc "Runs a package's native build task in an absolute workspace"

  @moduledoc """
  Dispatches a package's own `native_task` (from `tooling/packages.yaml`)
  with `--workspace <dir>`.

      mix wotex.native.build --package NAME --workspace /abs/dir

  The workspace must be an absolute, disposable directory; a relative path
  is refused. Native builds run only when invoked explicitly.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Native

  @switches [package: :string, workspace: :string]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)

    case Native.build(opts[:package], opts[:workspace]) do
      {:ok, 0} -> :ok
      {:ok, status} -> CLI.fail("native build of #{opts[:package]} exited with status #{status}")
      {:error, message} -> CLI.fail(message)
    end
  end

  @doc "Parses the task's options; both are required."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
    if opts[:package] in [nil, ""], do: Mix.raise("--package NAME is required")
    if opts[:workspace] in [nil, ""], do: Mix.raise("--workspace /abs/dir is required")
    opts
  end
end
