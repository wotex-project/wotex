defmodule Wotex.Workspace.Exec do
  @moduledoc """
  Runs a non-Mix command (clang-format, cargo, cmake, a test executable)
  as a separate OS process.

  `run/2` streams the command's output to the terminal and returns its exit
  status; with `stdout:` it writes standard output to that file instead and
  leaves standard error on the terminal. A command whose executable cannot
  be found returns status 127 with a message, as a shell would.
  """

  alias Wotex.Workspace

  @type option ::
          {:cd, Path.t()}
          | {:env, [{String.t(), String.t() | nil}]}
          | {:stdout, Path.t() | nil}
          | {:quiet, boolean()}

  @doc "Runs `[executable | args]` and returns its exit status."
  @spec run([String.t()], [option()]) :: non_neg_integer()
  def run([executable | args] = argv, opts \\ []) do
    cd = Keyword.get(opts, :cd, File.cwd!())
    env = Keyword.get(opts, :env, [])
    unless Keyword.get(opts, :quiet, false), do: announce(cd, argv, env)

    case resolve(executable, cd) do
      nil ->
        Mix.shell().error("#{executable}: command not found")
        127

      path ->
        execute(path, args, cd, env, Keyword.get(opts, :stdout))
    end
  end

  @doc "A one-line description: `packages/x: A=1 cmake -S ...`."
  @spec describe(Path.t(), [String.t()], [{String.t(), String.t() | nil}]) :: String.t()
  def describe(cd, argv, env) do
    exports = Enum.map(env, fn {name, value} -> "#{name}=#{value}" end)
    "#{Workspace.relative(cd)}: #{Enum.join(exports ++ argv, " ")}"
  end

  @doc "The absolute path of `executable`, looked up on `PATH` unless it contains a `/`."
  @spec resolve(String.t(), Path.t()) :: Path.t() | nil
  def resolve(executable, cd) do
    if String.contains?(executable, "/") do
      path = Path.expand(executable, cd)
      if File.regular?(path), do: path
    else
      System.find_executable(executable)
    end
  end

  defp execute(path, args, cd, env, nil) do
    {_stream, status} =
      System.cmd(path, args, cd: cd, env: env, into: IO.stream(), stderr_to_stdout: true)

    status
  end

  defp execute(path, args, cd, env, stdout) do
    {output, status} = System.cmd(path, args, cd: cd, env: env)
    File.mkdir_p!(Path.dirname(stdout))
    File.write!(stdout, output)
    status
  end

  defp announce(cd, argv, env), do: Mix.shell().info(["==> ", describe(cd, argv, env)])
end
