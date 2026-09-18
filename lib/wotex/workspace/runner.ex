defmodule Wotex.Workspace.Runner do
  @moduledoc """
  Runs a Mix command inside a package directory.

  Every command is a separate OS process (`System.cmd/3`) with the package
  directory as working directory; package code is never loaded into this VM.
  `WOTEX_PATH_DEPS=1` is exported unless the caller passes
  `path_deps: false`, and `MIX_ENV` is exported when `mix_env:` is given.
  `cd:` runs the command in another directory: an absolute one (a root task
  from a package gate) or one relative to the package directory (a host
  application inside it).
  Output streams to the terminal; the exit status is returned.
  """

  alias Wotex.Workspace

  @type option ::
          {:path_deps, boolean()}
          | {:mix_env, String.t() | nil}
          | {:env, [{String.t(), String.t() | nil}]}
          | {:quiet, boolean()}
          | {:cd, Path.t()}

  @doc """
  Runs `mix args...` in `path` and returns the exit status.
  """
  @spec run(Path.t(), [String.t()], [option()]) :: non_neg_integer()
  def run(path, args, opts \\ []) when is_list(args) do
    path = directory(path, opts)
    env = env(opts)
    unless Keyword.get(opts, :quiet, false), do: announce(path, args, env)

    {_stream, status} =
      System.cmd("mix", args, cd: path, env: env, into: IO.stream(), stderr_to_stdout: true)

    status
  end

  @doc """
  The directory a command runs in: `cd:` expanded against `path`, or `path`.
  """
  @spec directory(Path.t(), [option()]) :: Path.t()
  def directory(path, opts \\ []) do
    case Keyword.get(opts, :cd) do
      nil -> path
      cd -> Path.expand(cd, path)
    end
  end

  @doc """
  The environment a command receives. `nil` values unset a variable.
  """
  @spec env([option()]) :: [{String.t(), String.t() | nil}]
  def env(opts \\ []) do
    path_deps = if Keyword.get(opts, :path_deps, true), do: "1", else: nil
    mix_env = Keyword.get(opts, :mix_env)
    extra = Keyword.get(opts, :env, [])

    [{"WOTEX_PATH_DEPS", path_deps}]
    |> Kernel.++(if mix_env, do: [{"MIX_ENV", mix_env}], else: [])
    |> Kernel.++(extra)
    |> Enum.reverse()
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.reverse()
  end

  @doc """
  A one-line description of a command for logs: `packages/x: MIX_ENV=test mix compile`.
  """
  @spec describe(Path.t(), [String.t()], [{String.t(), String.t() | nil}]) :: String.t()
  def describe(path, args, env) do
    exports =
      env
      |> Enum.map_join(" ", fn
        {name, nil} -> "-u #{name}"
        {name, value} -> "#{name}=#{value}"
      end)

    "#{Workspace.relative(path)}: #{exports} mix #{Enum.join(args, " ")}"
  end

  defp announce(path, args, env) do
    Mix.shell().info(["==> ", describe(path, args, env)])
  end
end
