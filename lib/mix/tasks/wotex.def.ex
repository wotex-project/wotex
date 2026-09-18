defmodule Mix.Tasks.Wotex.Def do
  @shortdoc "Prints where a module or function is defined (Dexter lookup)"

  @moduledoc """
  Looks up the definition of `MODULE` or `MODULE.FUN` in the Dexter index
  and prints it as a repository-relative `path:line`. The index is
  refreshed first (`dexter reindex`, changed files only). The root alias is
  `mix def`.

      mix wotex.def MODULE [FUN] [--strict]

  Without `--strict`, Dexter falls back to the module when the function is
  not found. The task fails when nothing is found.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Dexter
  alias Wotex.Workspace.Impact

  @switches [strict: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {module, fun, opts} = parse_args(args)

    with :ok <- Dexter.reindex(),
         {:ok, [_ | _] = locations} <- Dexter.lookup(module, fun, strict: opts[:strict]) do
      Enum.each(locations, &Mix.shell().info(Dexter.format(&1)))
    else
      {:ok, []} -> CLI.fail("#{Impact.target(module, fun)} is not in the Dexter index")
      {:error, message} -> CLI.fail(message)
    end

    :ok
  end

  @doc "Parses `MODULE [FUN]` and the options."
  @spec parse_args([String.t()]) :: {String.t(), String.t() | nil, keyword()}
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    {module, fun} = target!(rest, "mix def MODULE [FUN] [--strict]")
    {module, fun, opts}
  end

  @doc """
  Splits `MODULE [FUN]` positional arguments; also accepts `MODULE.fun`
  and `MODULE.fun/arity`. Raises with `usage` otherwise.
  """
  @spec target!([String.t()], String.t()) :: {String.t(), String.t() | nil}
  def target!(rest, usage) do
    case rest do
      [module] -> split_target(module)
      [module, fun] -> {module, strip_arity(fun)}
      _other -> Mix.raise("usage: " <> usage)
    end
  end

  defp strip_arity(name), do: hd(String.split(name, "/"))

  # `Wotex.Runtime.Request.from_selection/3` names a function: the last
  # segment starts in lower case.
  defp split_target(target) do
    target = strip_arity(target)

    case String.split(target, ".") |> Enum.split(-1) do
      {[_ | _] = parts, [fun]} when fun != "" ->
        if fun =~ ~r/^[a-z_]/, do: {Enum.join(parts, "."), fun}, else: {target, nil}

      _other ->
        {target, nil}
    end
  end
end
