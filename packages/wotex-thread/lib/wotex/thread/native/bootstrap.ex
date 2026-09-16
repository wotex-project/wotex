defmodule Wotex.Thread.Native.Bootstrap do
  @moduledoc """
  Compiles the build guardian through an explicit trusted C compiler.

  The guardian cannot supervise its own initial compilation. This bootstrap
  therefore opens the selected compiler directly, clears inherited environment,
  and bounds the caller's wait to 20 seconds and captured output to 1 MiB.
  Every later build command uses `Wotex.Thread.Native.Command` and its process group
  owner. A failed bootstrap closes its direct Port; descendant cleanup is
  explicitly unverified and cannot be reported as guardian lifecycle evidence.

  `compile/4` requires absolute compiler, source, output and working-directory
  paths. It uses a separate argument vector, fixed C11 warning flags and only
  system tool directories in PATH. It runs only during an explicit native build.
  """

  @typedoc "Bounded compiler output; direct bootstrap descendant cleanup is always unverified."
  @type result :: %{output: binary(), descendant_cleanup: :unverified}

  @doc "Compiles the guardian, returning bounded compiler output and the bootstrap cleanup scope."
  @spec compile(term(), term(), term(), term()) ::
          {:ok, result()} | {:error, :invalid_bootstrap | :bootstrap_failed, result()}
  def compile(compiler, source, output, directory) do
    if Enum.all?([compiler, source, output, directory], &absolute?/1) do
      execute(compiler, source, output, directory)
    else
      {:error, :invalid_bootstrap, %{output: <<>>, descendant_cleanup: :unverified}}
    end
  end

  defp absolute?(path) when is_binary(path),
    do:
      String.valid?(path) and byte_size(path) in 1..4096 and Path.type(path) == :absolute and
        not String.contains?(path, <<0>>)

  defp absolute?(_), do: false

  defp execute(compiler, source, output, directory) do
    environment = Map.new(System.get_env(), fn {key, _} -> {key, nil} end)
    explicit = %{"PATH" => Path.dirname(compiler) <> ":/usr/bin:/bin", "LC_ALL" => "C"}

    env =
      environment
      |> Map.merge(explicit)
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), if(is_nil(value), do: false, else: String.to_charlist(value))}
      end)

    port =
      Port.open({:spawn_executable, compiler}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-std=c11", "-Wall", "-Wextra", "-Werror", source, "-o", output],
        cd: directory,
        env: env
      ])

    try do
      collect(port, <<>>, System.monotonic_time(:millisecond) + 20_000)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ in [ArgumentError, ErlangError] ->
      {:error, :bootstrap_failed, %{output: <<>>, descendant_cleanup: :unverified}}
  end

  defp collect(port, bytes, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    if remaining > 0, do: receive_output(port, bytes, deadline, remaining), else: failed(bytes)
  end

  defp receive_output(port, bytes, deadline, remaining) do
    receive do
      {^port, {:data, next}}
      when is_binary(next) and byte_size(bytes) + byte_size(next) <= 1_048_576 ->
        collect(port, bytes <> next, deadline)

      {^port, {:exit_status, 0}} ->
        {:ok, %{output: bytes, descendant_cleanup: :unverified}}

      {^port, _} ->
        {:error, :bootstrap_failed, %{output: bytes, descendant_cleanup: :unverified}}
    after
      remaining -> failed(bytes)
    end
  end

  defp failed(bytes),
    do: {:error, :bootstrap_failed, %{output: bytes, descendant_cleanup: :unverified}}
end
