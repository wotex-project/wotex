defmodule Wotex.Modbus.Connection do
  @moduledoc "Explicitly started socket owner with serialized, deadline-bounded TCP exchanges."

  use GenServer
  alias Wotex.Modbus.{Codec, Command, Error}

  @doc "Starts a linked connection. The caller supplies host; no named process is registered."
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    with {:ok, config} <- config(opts) do
      case GenServer.start(__MODULE__, config) do
        {:ok, pid} ->
          Process.link(pid)
          {:ok, pid}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc "Executes a validated command with a finite deadline including queue time."
  @spec request(pid(), Command.t(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def request(pid, %Command{} = command, timeout)
      when is_pid(pid) and is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout
    GenServer.call(pid, {:request, command, deadline}, timeout + 1000)
  catch
    :exit, _reason ->
      {:error,
       %Error{
         code: :connection_closed,
         effect: if(Command.write?(command), do: :unknown, else: :none)
       }}
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @doc "Closes the connection idempotently."
  @spec close(pid()) :: :ok
  def close(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal, 61_000)
  catch
    :exit, _ -> :ok
  end

  @doc "Validates explicit connection options without opening a socket."
  @spec config(term()) :: {:ok, map()} | {:error, Error.t()}
  def config(opts) when is_list(opts) do
    if admitted_options?(opts),
      do: config_options(opts),
      else: {:error, Error.new(:invalid_options)}
  end

  def config(_), do: {:error, Error.new(:invalid_options)}

  @impl GenServer
  def init(config) do
    options = [
      :binary,
      active: false,
      packet: :raw,
      nodelay: true,
      send_timeout: config.timeout,
      send_timeout_close: true
    ]

    options = if tuple_size(config.host) == 8, do: [:inet6 | options], else: options

    case :gen_tcp.connect(config.host, config.port, options, config.timeout) do
      {:ok, socket} ->
        monitor = Process.monitor(config.owner)
        {:ok, %{socket: socket, transaction: config.transaction_id, monitor: monitor}}

      {:error, reason} ->
        {:stop, Error.new(:connect_failed, nil, %{reason: reason})}
    end
  end

  @impl GenServer
  def handle_call({:request, command, deadline}, _from, state) do
    started = System.monotonic_time()
    result = exchange(state, command, deadline)

    :telemetry.execute(
      [:wotex, :modbus, :request, :stop],
      %{duration: System.monotonic_time() - started},
      %{function: command.function, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
    )

    case result do
      {:ok, _} ->
        {:reply, result, %{state | transaction: rem(state.transaction + 1, 65_536)}}

      {:error, %Error{code: code}} when code in [:remote_exception, :deadline_exceeded] ->
        {:reply, result, %{state | transaction: rem(state.transaction + 1, 65_536)}}

      {:error, _} ->
        {:stop, :normal, result, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  @impl GenServer
  def terminate(_reason, state), do: :gen_tcp.close(state.socket)

  defp exchange(state, command, deadline) do
    if remaining(deadline) == 0 do
      {:error, Error.new(:deadline_exceeded)}
    else
      with {:ok, adu} <- Codec.encode(command, state.transaction),
           :ok <- :gen_tcp.send(state.socket, adu),
           {:ok, header} <- recv(state.socket, 6, deadline),
           :more <- Codec.decode(header),
           <<_::32, length::16>> = header,
           {:ok, body} <- recv(state.socket, length, deadline),
           {:ok, frame, <<>>} <- Codec.decode(header <> body),
           {:ok, value} <- Codec.response(frame, command, state.transaction) do
        {:ok, value}
      else
        {:error, %Error{} = error} -> effect(error, command)
        {:error, reason} -> effect(Error.new(:transport_error, nil, %{reason: reason}), command)
      end
    end
  end

  defp effect(%Error{code: :remote_exception} = error, _), do: {:error, error}

  defp effect(error, command),
    do: {:error, %{error | effect: if(Command.write?(command), do: :unknown, else: :none)}}

  defp recv(socket, length, deadline) do
    case remaining(deadline) do
      0 -> {:error, :timeout}
      time -> :gen_tcp.recv(socket, length, time)
    end
  end

  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  defp config_options(opts) do
    host = Keyword.get(opts, :host)
    port = Keyword.get(opts, :port, 502)
    timeout = Keyword.get(opts, :timeout, 5000)
    transaction = Keyword.get(opts, :transaction_id, 0)
    owner = Keyword.get(opts, :owner, self())
    unit = Keyword.get(opts, :unit_id, 1)

    with :ok <- security(Keyword.get(opts, :security, :none)),
         {:ok, host} <- address(host) do
      if is_integer(port) and port in 1..65_535 and is_integer(timeout) and timeout in 1..60_000 and
           is_integer(transaction) and transaction in 0..65_535 and is_pid(owner) and
           (unit in 1..247 or unit == 255),
         do:
           {:ok,
            %{host: host, port: port, timeout: timeout, transaction_id: transaction, owner: owner}},
         else: {:error, Error.new(:invalid_options)}
    end
  end

  defp security(:none), do: :ok
  defp security(_), do: {:error, Error.new(:unsupported_security, :security)}

  defp address(host) when is_binary(host) and byte_size(host) <= 64 do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> {:error, Error.new(:invalid_host, :host)}
    end
  end

  defp address(host) when is_tuple(host) do
    case :inet.ntoa(host) do
      {:error, _} -> {:error, Error.new(:invalid_host, :host)}
      _ -> {:ok, host}
    end
  rescue
    _ -> {:error, Error.new(:invalid_host, :host)}
  end

  defp address(_), do: {:error, Error.new(:invalid_host, :host)}

  defp admitted_options?(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)
      allowed = [:host, :port, :timeout, :transaction_id, :owner, :unit_id, :security]

      keys -- allowed == [] and length(keys) == MapSet.size(MapSet.new(keys))
    else
      false
    end
  end
end
