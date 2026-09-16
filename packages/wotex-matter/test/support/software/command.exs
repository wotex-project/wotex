defmodule Wotex.Matter.SoftwareCommand do
  @moduledoc false

  @maximum_output 16_777_216
  @truncated_log "\n[software peer log truncated]\n"
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
    executable
    |> start(arguments, options)
    |> await()
  end

  @spec start(String.t(), [String.t()], keyword()) :: map()
  def start(executable, arguments, options \\ []) do
    owner = self()
    reference = make_ref()
    timeout = Keyword.get(options, :timeout, 60_000)
    deadline = System.monotonic_time(:millisecond) + timeout

    {worker, monitor} =
      spawn_monitor(fn ->
        owner_monitor = Process.monitor(owner)

        result =
          execute(executable, arguments, options, owner_monitor, {owner, reference}, deadline)

        send(owner, {reference, result})
      end)

    %{owner: owner, pid: worker, monitor: monitor, reference: reference, deadline: deadline}
  end

  @spec await(map()) :: {:ok, binary()} | {:error, atom()}
  def await(%{owner: owner, deadline: deadline} = command) when owner == self(),
    do: await_result(command, deadline + 1_000)

  @spec cancel(map()) :: {:ok, binary()} | {:error, atom()}
  def cancel(%{owner: owner, pid: worker, reference: reference} = command) when owner == self() do
    send(worker, {:cancel, reference})
    await_result(command, System.monotonic_time(:millisecond) + 1_000)
  end

  defp await_result(%{pid: worker, reference: reference, monitor: monitor} = command, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^reference, {kind, _} = result} when kind in [:ok, :error] ->
        Process.demonitor(monitor, [:flush])
        result

      {^reference, _} ->
        await_result(command, deadline)

      {:DOWN, ^monitor, :process, ^worker, _} ->
        {:error, :command_failed}
    after
      remaining ->
        Process.exit(worker, :kill)
        Process.demonitor(monitor, [:flush])
        {:error, :command_timeout}
    end
  end

  defp execute(executable, arguments, options, owner, destination, deadline) do
    path = System.find_executable(executable)
    readiness = readiness(options[:ready])

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
        if readiness do
          {:os_pid, child} = Port.info(port, :os_pid)
          notify(destination, {:started, port, child})
        end

        collect(port, owner, deadline, [], 0, options, destination, readiness)
      after
        terminate(port)
      end
    end
  rescue
    _ -> {:error, :command_failed}
  end

  defp collect(
         port,
         owner,
         deadline,
         chunks,
         size,
         options,
         {_, reference} = destination,
         readiness
       ) do
    case halt_reason(owner, reference, deadline) do
      nil ->
        collect_output(port, owner, deadline, chunks, size, options, destination, readiness)

      reason ->
        persist(chunks, options)
        {:error, reason}
    end
  end

  defp collect_output(
         port,
         owner,
         deadline,
         chunks,
         size,
         options,
         {_, reference} = destination,
         readiness
       ) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))
    truncate? = options[:output_overflow] == :truncate
    limit = if truncate?, do: @maximum_output - byte_size(@truncated_log), else: @maximum_output

    receive do
      {^port, {:data, bytes}} when size + byte_size(bytes) <= limit ->
        readiness = signal_ready(readiness, bytes, destination)

        collect(
          port,
          owner,
          deadline,
          [bytes | chunks],
          size + byte_size(bytes),
          options,
          destination,
          readiness
        )

      {^port, {:data, bytes}} ->
        if truncate? do
          retained =
            if size == @maximum_output,
              do: chunks,
              else: [@truncated_log, binary_part(bytes, 0, limit - size) | chunks]

          collect(
            port,
            owner,
            deadline,
            retained,
            @maximum_output,
            options,
            destination,
            signal_ready(readiness, bytes, destination)
          )
        else
          persist(chunks, options)
          {:error, :command_output_limit}
        end

      {^port, {:exit_status, status}} ->
        output = persist(chunks, options)
        if status == 0, do: {:ok, output}, else: {:error, :command_failed}

      {:DOWN, ^owner, :process, _, _} ->
        persist(chunks, options)
        {:error, :command_owner_down}

      {:cancel, ^reference} ->
        persist(chunks, options)
        {:error, :command_cancelled}
    after
      remaining ->
        persist(chunks, options)
        {:error, :command_timeout}
    end
  end

  defp halt_reason(owner, reference, deadline) do
    receive do
      {:DOWN, ^owner, :process, _, _} -> :command_owner_down
      {:cancel, ^reference} -> :command_cancelled
    after
      0 -> if System.monotonic_time(:millisecond) >= deadline, do: :command_timeout
    end
  end

  defp persist(chunks, options) do
    output =
      chunks
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    if log = options[:log] do
      {:ok, file} = File.open(log, [:write, :exclusive])

      try do
        File.chmod!(log, 0o600)
        :ok = IO.binwrite(file, output)
      after
        File.close(file)
      end
    end

    output
  end

  defp readiness(nil), do: nil
  defp readiness(marker) when is_binary(marker) and byte_size(marker) in 1..256, do: {marker, ""}

  defp signal_ready(nil, _, _), do: nil

  defp signal_ready({marker, tail}, bytes, destination) do
    buffer = tail <> bytes

    case :binary.match(buffer, marker) do
      :nomatch ->
        keep = min(byte_size(buffer), byte_size(marker) - 1)
        {marker, binary_part(buffer, byte_size(buffer) - keep, keep)}

      _ ->
        notify(destination, :ready)
        nil
    end
  end

  defp notify({owner, reference}, event), do: send(owner, {reference, event})

  defp terminate(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        # Closing stdin alone does not terminate tools such as sleep or tar.
        # Docker owns container descendants; the build watcher removes them.
        Wotex.Matter.Native.ProcessCommand.run("kill", ["-KILL", Integer.to_string(pid)],
          stderr_to_stdout: true
        )

        close_port(port)

      nil ->
        :ok
    end
  end

  @doc false
  @spec close_port(port()) :: :ok
  def close_port(port) when is_port(port) do
    Port.close(port)
    :ok
  rescue
    error in ArgumentError ->
      if is_nil(Port.info(port)), do: :ok, else: reraise(error, __STACKTRACE__)
  end

  defp environment(overrides) do
    original = System.get_env()

    selected =
      original
      |> Map.take(@inherited)
      |> Map.merge(Map.new(overrides))

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
