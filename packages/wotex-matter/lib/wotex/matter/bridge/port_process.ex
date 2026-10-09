defmodule Wotex.Matter.Bridge.PortProcess do
  @moduledoc false

  alias Wotex.Matter.Error
  alias Wotex.Matter.Native.ProcessCommand

  @doc false
  @spec verify(map()) :: :ok | {:error, Error.t()}
  def verify(configuration) do
    with {:ok, %{type: :regular, mode: mode, size: size}} <- File.lstat(configuration.executable),
         true <- Bitwise.band(mode, 0o111) != 0 and size in 1..1_073_741_824,
         digest <-
           configuration.executable
           |> File.stream!(65_536)
           |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
           |> :crypto.hash_final()
           |> Base.encode16(case: :lower),
         true <- digest == configuration.executable_sha256 do
      :ok
    else
      _ -> {:error, Error.new(:incompatible_backend, :executable)}
    end
  rescue
    _ -> {:error, Error.new(:incompatible_backend, :executable)}
  end

  @doc false
  @spec open(map()) :: {:ok, port()} | {:error, Error.t()}
  def open(configuration) do
    {:ok, %{type: :regular, mode: mode}} = File.stat("/bin/kill")
    true = Bitwise.band(mode, 0o111) != 0
    environment = for {key, _} <- System.get_env(), do: {String.to_charlist(key), false}

    {:ok,
     Port.open({:spawn_executable, String.to_charlist(configuration.executable)}, [
       :binary,
       :exit_status,
       :use_stdio,
       {:line, 262_143},
       {:args, Enum.map(configuration.arguments, &String.to_charlist/1)},
       {:env, environment},
       {:busy_limits_port, {512, 4096}},
       {:busy_limits_msgq, {512, 4096}}
     ])}
  rescue
    _ -> {:error, Error.new(:connection_failed)}
  end

  @doc false
  @spec send_frame(port(), binary()) :: boolean()
  def send_frame(port, bytes) when is_binary(bytes) and byte_size(bytes) <= 512 do
    Port.command(port, bytes, [:nosuspend])
  rescue
    _ -> false
  end

  @doc false
  @spec close(port()) :: :ok | {:error, Error.t()}
  def close(port) do
    deadline = System.monotonic_time(:millisecond) + 1000
    monitor = :erlang.monitor(:port, port)

    try do
      case Port.info(port, :os_pid) do
        {:os_pid, pid} ->
          ProcessCommand.run("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
          close_if_open(port)

        nil ->
          :ok
      end

      await_release(port, monitor, deadline)
    after
      Process.demonitor(monitor, [:flush])
    end
  rescue
    _ -> {:error, Error.new(:transport_closed)}
  end

  defp close_if_open(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  @doc false
  @spec join(port(), reference(), integer()) :: :ok | {:error, Error.t()}
  def join(port, monitor, deadline), do: await_release(port, monitor, deadline)

  defp await_release(port, monitor, deadline) do
    cond do
      Port.info(port) == nil ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, Error.new(:timeout)}

      true ->
        receive do
          {:DOWN, ^monitor, :port, ^port, _} -> await_release(port, monitor, deadline)
        after
          1 -> await_release(port, monitor, deadline)
        end
    end
  end
end
