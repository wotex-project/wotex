defmodule Wotex.CoAP.Native.BuildCommand do
  @moduledoc """
  Executes explicit native-build commands with finite output and process budgets.

  Normal build steps run through the checked-in command guardian, which owns the
  child process group and combines stdout/stderr without interpreting command
  text. `direct/5` exists only to compile that guardian before it is available.
  """

  @maximum_output 16_777_216
  @maximum_timeout 600_000

  @type result :: %{output: binary(), exit_status: non_neg_integer()}

  @doc "Runs one argv-only command through the native-build guardian."
  @spec run(String.t(), String.t(), [String.t()], String.t(), keyword()) ::
          {:ok, result()} | {:error, atom(), result()}
  def run(guardian, executable, arguments, cwd, options \\ []) do
    timeout = Keyword.get(options, :timeout, @maximum_timeout)
    output = Keyword.get(options, :output, @maximum_output)
    cleanup = Keyword.get(options, :cleanup, 1_000)

    with :ok <- limits(timeout, output, cleanup),
         :ok <- absolute_file(guardian),
         :ok <- absolute_file(executable),
         :ok <- absolute_directory(cwd),
         :ok <- arguments(arguments),
         {:ok, port} <-
           open(
             guardian,
             [
               Integer.to_string(timeout),
               Integer.to_string(output),
               Integer.to_string(cleanup),
               cwd,
               executable | arguments
             ],
             cwd,
             Keyword.get(options, :env, []),
             false
           ) do
      await(port, timeout + cleanup + 1_000, output, "")
    else
      :error -> {:error, :invalid_build_command, %{output: "", exit_status: 126}}
    end
  end

  @doc "Compiles the command guardian with a finite direct process budget."
  @spec direct(String.t(), [String.t()], String.t(), keyword()) ::
          {:ok, result()} | {:error, atom(), result()}
  def direct(executable, arguments, cwd, options \\ []) do
    timeout = Keyword.get(options, :timeout, 30_000)
    output = Keyword.get(options, :output, 1_048_576)

    with :ok <- limits(timeout, output, 1_000),
         :ok <- absolute_file(executable),
         :ok <- absolute_directory(cwd),
         :ok <- arguments(arguments),
         {:ok, port} <-
           open(executable, arguments, cwd, Keyword.get(options, :env, []), true) do
      await(port, timeout, output, "")
    else
      :error -> {:error, :invalid_build_command, %{output: "", exit_status: 126}}
    end
  end

  defp open(executable, arguments, cwd, environment, merge_stderr) do
    options = [
      :binary,
      :exit_status,
      :use_stdio,
      {:args, Enum.map(arguments, &String.to_charlist/1)},
      {:cd, String.to_charlist(cwd)},
      {:env, environment(environment)}
    ]

    options = if merge_stderr, do: [:stderr_to_stdout | options], else: options
    {:ok, Port.open({:spawn_executable, String.to_charlist(executable)}, options)}
  rescue
    _ in [ArgumentError, ErlangError] -> :error
  end

  defp await(port, timeout, limit, output) do
    deadline = System.monotonic_time(:millisecond) + timeout
    receive_output(port, deadline, limit, output)
  end

  defp receive_output(port, deadline, limit, output) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      close(port)
      {:error, :build_command_deadline, %{output: output, exit_status: 124}}
    else
      receive do
        {^port, {:data, bytes}} ->
          if byte_size(bytes) <= limit - byte_size(output) do
            receive_output(port, deadline, limit, output <> bytes)
          else
            close(port)
            {:error, :build_command_output_limit, %{output: output, exit_status: 125}}
          end

        {^port, {:exit_status, 0}} ->
          {:ok, %{output: output, exit_status: 0}}

        {^port, {:exit_status, status}} ->
          code =
            case status do
              124 -> :build_command_deadline
              125 -> :build_command_output_limit
              126 -> :build_command_setup
              127 -> :build_command_owner_lost
              128 -> :build_command_signal
              129 -> :build_command_cleanup
              _ -> :build_command_failed
            end

          {:error, code, %{output: output, exit_status: status}}
      after
        remaining ->
          close(port)
          {:error, :build_command_deadline, %{output: output, exit_status: 124}}
      end
    end
  end

  defp close(port) do
    close_if_open(port)
  rescue
    _ in [ArgumentError, ErlangError] -> :ok
  end

  defp environment(values) when is_list(values) do
    Enum.map(values, fn
      {name, false} when is_binary(name) ->
        {String.to_charlist(name), false}

      {name, value} when is_binary(name) and is_binary(value) ->
        {String.to_charlist(name), String.to_charlist(value)}
    end)
  end

  defp limits(timeout, output, cleanup)
       when is_integer(timeout) and timeout in 1..@maximum_timeout and is_integer(output) and
              output in 1..@maximum_output and is_integer(cleanup) and cleanup in 1..5_000,
       do: :ok

  defp limits(_, _, _), do: :error

  defp absolute_file(path) when is_binary(path) do
    if Path.type(path) == :absolute and File.regular?(path), do: :ok, else: :error
  end

  defp absolute_file(_), do: :error

  defp absolute_directory(path) when is_binary(path) do
    if Path.type(path) == :absolute and File.dir?(path), do: :ok, else: :error
  end

  defp absolute_directory(_), do: :error

  defp arguments(values) when is_list(values) do
    if Enum.all?(values, fn value ->
         is_binary(value) and String.valid?(value) and not String.contains?(value, <<0>>)
       end),
       do: :ok,
       else: :error
  end

  defp arguments(_), do: :error

  # The child can exit between a liveness check and the close, so closing an
  # already closed Port counts as closed.
  defp close_if_open(port) do
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end
end
