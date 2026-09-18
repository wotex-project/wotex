defmodule Wotex.BLE.Native.Bootstrap do
  @moduledoc """
  Compiles the native command guardian with an explicit trusted C compiler.

  The guardian cannot supervise its own compilation, so this one step opens the
  selected compiler directly. It clears the inherited environment, uses fixed
  C11 warning flags and bounds the caller's wait to 60 seconds and captured
  output to 1 MiB. Every later build command runs through the compiled guardian.
  Descendant cleanup of this direct bootstrap is always reported as unverified.
  """

  @typedoc "Bounded compiler output and the explicit bootstrap cleanup scope."
  @type result :: %{output: binary(), descendant_cleanup: :unverified}

  @doc "Compiles the guardian source to an absolute output path."
  @spec compile(term(), term(), term(), term()) ::
          {:ok, result()} | {:error, :invalid_bootstrap | :bootstrap_failed, result()}
  def compile(compiler, source, output, directory) do
    if Enum.all?([compiler, source, output, directory], &absolute?/1),
      do: execute(compiler, source, output, directory),
      else: {:error, :invalid_bootstrap, result(<<>>)}
  end

  defp absolute?(path) do
    is_binary(path) and String.valid?(path) and byte_size(path) in 1..4096 and
      Path.type(path) == :absolute and not String.contains?(path, <<0>>)
  end

  defp execute(compiler, source, output, directory) do
    env =
      System.get_env()
      |> Map.new(fn {key, _} -> {key, nil} end)
      |> Map.merge(%{"PATH" => Path.dirname(compiler) <> ":/usr/bin:/bin", "LC_ALL" => "C"})
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), if(is_nil(value), do: false, else: String.to_charlist(value))}
      end)

    port =
      Port.open({:spawn_executable, compiler}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", source, "-o", output],
        cd: directory,
        env: env
      ])

    try do
      collect(port, <<>>, System.monotonic_time(:millisecond) + 60_000)
    after
      close_if_open(port)
    end
  rescue
    _ in [ArgumentError, ErlangError] -> {:error, :bootstrap_failed, result(<<>>)}
  end

  defp collect(port, bytes, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, next}} when byte_size(bytes) + byte_size(next) <= 1_048_576 ->
        collect(port, bytes <> next, deadline)

      {^port, {:exit_status, 0}} ->
        {:ok, result(bytes)}

      {^port, _} ->
        {:error, :bootstrap_failed, result(bytes)}
    after
      remaining -> {:error, :bootstrap_failed, result(bytes)}
    end
  end

  defp result(bytes), do: %{output: bytes, descendant_cleanup: :unverified}

  # The child can exit between a liveness check and the close, so closing an
  # already closed Port counts as closed.
  defp close_if_open(port) do
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end
end
