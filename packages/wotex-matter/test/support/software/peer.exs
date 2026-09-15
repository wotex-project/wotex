Code.require_file("command.exs", __DIR__)

defmodule Wotex.Matter.SoftwarePeer do
  @moduledoc false

  alias Wotex.Matter.SoftwareCommand

  @spec start(String.t(), [String.t()], keyword()) :: {:ok, map()} | {:error, atom()}
  def start(executable, arguments, options) do
    startup_timeout = Keyword.get(options, :startup_timeout)
    lifetime_timeout = Keyword.get(options, :timeout)
    marker = Keyword.get(options, :ready)

    if is_integer(startup_timeout) and startup_timeout in 1..60_000 and
         is_integer(lifetime_timeout) and lifetime_timeout in startup_timeout..7_200_000 and
         is_binary(marker) and byte_size(marker) in 1..256 do
      deadline = System.monotonic_time(:millisecond) + startup_timeout

      command_options =
        options
        |> Keyword.delete(:startup_timeout)
        |> Keyword.put(:output_overflow, :truncate)

      command = SoftwareCommand.start(executable, arguments, command_options)

      await_ready(command, nil, deadline)
    else
      {:error, :invalid_peer_options}
    end
  end

  @spec stop(map()) :: :ok | {:error, atom()}
  def stop(%{command: command, port: port, os_pid: child}) do
    started = System.monotonic_time(:millisecond)
    result = SoftwareCommand.cancel(command)
    cleaned = reaped?(port, child, started + 1_000)

    cond do
      not cleaned -> {:error, :peer_cleanup_unverified}
      result != {:error, :command_cancelled} -> {:error, :peer_exited}
      true -> :ok
    end
  end

  defp await_ready(
         %{reference: reference, monitor: monitor, pid: worker} = command,
         child,
         deadline
       ) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^reference, {:started, port, pid}} ->
        await_ready(command, %{command: command, port: port, os_pid: pid}, deadline)

      {^reference, :ready} when not is_nil(child) ->
        if System.monotonic_time(:millisecond) < deadline,
          do: {:ok, child},
          else: expire(command, child)

      {^reference, {kind, _}} when kind in [:ok, :error] ->
        Process.demonitor(monitor, [:flush])
        startup_failed(child)

      {:DOWN, ^monitor, :process, ^worker, _} ->
        startup_failed(child)
    after
      remaining ->
        expire(command, child)
    end
  end

  defp expire(%{pid: worker, reference: reference} = command, child) do
    send(worker, {:cancel, reference})
    abandon(command, child, System.monotonic_time(:millisecond) + 1_000)
  end

  defp abandon(%{reference: reference, monitor: monitor, pid: worker} = command, child, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^reference, {:started, port, pid}} ->
        abandon(command, %{command: command, port: port, os_pid: pid}, deadline)

      {^reference, :ready} ->
        abandon(command, child, deadline)

      {^reference, {kind, _}} when kind in [:ok, :error] ->
        Process.demonitor(monitor, [:flush])
        startup_failed(child, deadline)

      {:DOWN, ^monitor, :process, ^worker, _} ->
        startup_failed(child, deadline)
    after
      remaining -> {:error, :peer_cleanup_unverified}
    end
  end

  defp startup_failed(child),
    do: startup_failed(child, System.monotonic_time(:millisecond) + 1_000)

  defp startup_failed(nil, _deadline), do: {:error, :peer_not_ready}

  defp startup_failed(%{port: port, os_pid: child}, deadline) do
    if reaped?(port, child, deadline),
      do: {:error, :peer_not_ready},
      else: {:error, :peer_cleanup_unverified}
  end

  defp reaped?(port, child, deadline) do
    case System.cmd("/bin/kill", ["-0", Integer.to_string(child)], stderr_to_stdout: true) do
      {_, 0} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          reaped?(port, child, deadline)
        else
          false
        end

      _ ->
        is_nil(Port.info(port))
    end
  end
end
