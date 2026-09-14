defmodule Wotex.Matter.SoftwareCommand do
  @moduledoc false

  @maximum_output 16_777_216
  @inherited ~w(HOME PATH DOCKER_CONFIG DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH WOTEX_PATH_DEPS MIX_ENV MIX_BUILD_PATH MIX_DEPS_PATH)

  @spec run!(String.t(), [String.t()], keyword()) :: binary()
  def run!(executable, arguments, options \\ []) do
    case run(executable, arguments, options) do
      {:ok, output} -> output
      {:error, reason} -> Mix.raise(Atom.to_string(reason))
    end
  end

  @spec run(String.t(), [String.t()], keyword()) :: {:ok, binary()} | {:error, atom()}
  def run(executable, arguments, options \\ []) do
    owner = self()
    reference = make_ref()
    timeout = Keyword.get(options, :timeout, 60_000)

    {worker, monitor} =
      spawn_monitor(fn ->
        owner_monitor = Process.monitor(owner)
        result = execute(executable, arguments, options, owner_monitor, timeout)
        send(owner, {reference, result})
      end)

    receive do
      {^reference, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^worker, _} ->
        {:error, :command_failed}
    after
      timeout + 1_000 ->
        Process.exit(worker, :kill)
        Process.demonitor(monitor, [:flush])
        {:error, :command_timeout}
    end
  end

  defp execute(executable, arguments, options, owner, timeout) do
    path = System.find_executable(executable)

    if is_nil(path) do
      {:error, :required_tool_missing}
    else
      port =
        Port.open({:spawn_executable, String.to_charlist(path)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          {:args, Enum.map(arguments, &String.to_charlist/1)},
          {:cd, String.to_charlist(Keyword.get(options, :cd, File.cwd!()))},
          {:env, environment(Keyword.get(options, :env, []))}
        ])

      try do
        deadline = System.monotonic_time(:millisecond) + timeout
        collect(port, owner, deadline, [], 0, options)
      after
        terminate(port)
      end
    end
  rescue
    _ -> {:error, :command_failed}
  end

  defp collect(port, owner, deadline, chunks, size, options) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, bytes}} when size + byte_size(bytes) <= @maximum_output ->
        collect(port, owner, deadline, [bytes | chunks], size + byte_size(bytes), options)

      {^port, {:data, _}} ->
        persist(chunks, options)
        {:error, :command_output_limit}

      {^port, {:exit_status, status}} ->
        output = persist(chunks, options)
        if status == 0, do: {:ok, output}, else: {:error, :command_failed}

      {:DOWN, ^owner, :process, _, _} ->
        persist(chunks, options)
        {:error, :command_owner_down}
    after
      remaining ->
        persist(chunks, options)
        {:error, :command_timeout}
    end
  end

  defp persist(chunks, options) do
    output = chunks |> Enum.reverse() |> IO.iodata_to_binary()
    if log = options[:log], do: File.write!(log, output, [:exclusive])
    output
  end

  defp terminate(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        # Closing stdin alone does not terminate tools such as sleep or tar.
        # Docker owns container descendants; the build watcher removes them.
        System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
        if Port.info(port), do: Port.close(port)

      nil ->
        :ok
    end
  end

  defp environment(overrides) do
    original = System.get_env()
    selected = original |> Map.take(@inherited) |> Map.merge(Map.new(overrides))

    original
    |> Map.keys()
    |> Kernel.++(Map.keys(selected))
    |> Enum.uniq()
    |> Enum.map(fn key ->
      value =
        case selected[key] do
          nil -> false
          value -> String.to_charlist(value)
        end

      {String.to_charlist(key), value}
    end)
  end
end
