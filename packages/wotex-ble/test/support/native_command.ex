defmodule Wotex.BLE.NativeCommand do
  @moduledoc false

  @limit 16_777_216
  @type result :: {:ok, binary(), non_neg_integer()} | {:error, atom(), :unverified}

  @spec bootstrap(binary(), binary(), binary(), keyword()) :: result()
  def bootstrap(compiler, source, target, options \\ []) do
    arguments = ["-std=c11", "-O1", "-Wall", "-Wextra", "-Werror", source, "-o", target]
    timeout = Keyword.get(options, :timeout, 5000)
    command(compiler, arguments, timeout, @limit, options)
  end

  @spec run(binary(), binary(), [binary()], keyword()) :: result()
  def run(guardian, executable, arguments, options \\ []) do
    port = open(guardian, executable, arguments, options)
    timeout = Keyword.get(options, :timeout, 5000) + Keyword.get(options, :cleanup, 1000) + 500
    await(port, timeout, Keyword.get(options, :limit, @limit))
  rescue
    ArgumentError -> {:error, :command_unavailable, :unverified}
  end

  @spec open(binary(), binary(), [binary()], keyword()) :: port()
  def open(guardian, executable, arguments, options) do
    timeout = Keyword.get(options, :timeout, 5000)
    limit = Keyword.get(options, :limit, @limit)
    cleanup = Keyword.get(options, :cleanup, 1000)
    directory = Keyword.fetch!(options, :cd)

    native_arguments =
      Enum.map([timeout, limit, cleanup], &Integer.to_string/1) ++
        [directory, executable | arguments]

    spawn_port(guardian, native_arguments, options)
  end

  @spec await(port(), non_neg_integer(), pos_integer(), binary()) :: result()
  def await(port, timeout, limit \\ @limit, initial \\ "") do
    try do
      collect(
        port,
        [initial],
        byte_size(initial),
        limit,
        System.monotonic_time(:millisecond) + timeout
      )
    after
      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end
  end

  defp command(executable, arguments, timeout, limit, options) do
    port = spawn_port(executable, arguments, options)
    await(port, timeout, limit)
  rescue
    ArgumentError -> {:error, :command_unavailable, :unverified}
  end

  defp spawn_port(executable, arguments, options) do
    Port.open({:spawn_executable, executable}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: arguments,
      env: environment(Keyword.get(options, :env, []))
    ])
  end

  defp collect(port, output, count, limit, deadline) do
    receive do
      {^port, {:data, bytes}} when byte_size(bytes) + count <= limit ->
        collect(port, [bytes | output], count + byte_size(bytes), limit, deadline)

      {^port, {:data, _}} ->
        {:error, :command_output_limit, :unverified}

      {^port, {:exit_status, code}} ->
        {:ok, IO.iodata_to_binary(Enum.reverse(output)), code}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :command_deadline, :unverified}
    end
  end

  defp environment(values) do
    Enum.map(values, fn
      {key, nil} -> {String.to_charlist(key), false}
      {key, value} -> {String.to_charlist(key), String.to_charlist(value)}
    end)
  end
end
