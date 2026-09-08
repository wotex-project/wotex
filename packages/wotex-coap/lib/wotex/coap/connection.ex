defmodule Wotex.CoAP.Connection do
  @moduledoc "Explicit UDP socket owner with bounded RFC 7252 request correlation and retransmission."

  use GenServer
  alias Wotex.CoAP.{Codec, Error, Message}

  @doc "Starts a linked socket owner. Numeric host and finite timeout are explicit inputs."
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

  @doc "Runs one exchange; caller queue time is part of the deadline."
  @spec request(pid(), Message.t(), pos_integer()) :: {:ok, Message.t()} | {:error, Error.t()}
  def request(pid, %Message{} = message, timeout)
      when is_pid(pid) and is_integer(timeout) and timeout in 1..60_000 do
    GenServer.call(
      pid,
      {:request, message, System.monotonic_time(:millisecond) + timeout},
      timeout + 1000
    )
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @doc "Closes a socket owner idempotently."
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.stop(pid, :normal, 61_000)
  catch
    :exit, _ -> :ok
  end

  @doc "Validates configuration without accessing the network."
  @spec config(term()) :: {:ok, map()} | {:error, Error.t()}
  def config(opts) when is_list(opts) do
    allowed = [:host, :port, :timeout, :ack_timeout, :owner, :scheme, :dtls_mode]

    if Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [],
      do: options(opts),
      else: {:error, Error.new(:invalid_options)}
  end

  def config(_), do: {:error, Error.new(:invalid_options)}

  @impl GenServer
  def init(config) do
    family = if tuple_size(config.host) == 8, do: :inet6, else: :inet

    config =
      if is_nil(config.ack_timeout),
        do: %{config | ack_timeout: 2000 + :rand.uniform(1000)},
        else: config

    case :gen_udp.open(0, [family, :binary, active: false]) do
      {:ok, socket} ->
        {:ok,
         %{
           config: config,
           socket: socket,
           mid: :rand.uniform(65_536) - 1,
           token: :rand.uniform(4_294_967_296) - 1,
           history: %{},
           monitor: Process.monitor(config.owner)
         }}

      {:error, reason} ->
        {:stop, Error.new(:socket_failed, nil, %{reason: reason})}
    end
  end

  @impl GenServer
  def handle_call({:request, message, deadline}, _, state) do
    now = System.monotonic_time(:millisecond)
    history = Map.reject(state.history, fn {_, time} -> now - time > 247_000 end)

    if now >= deadline or Map.has_key?(history, state.mid) do
      {:reply, {:error, Error.new(:exchange_unavailable)}, state}
    else
      message = %{message | message_id: state.mid, token: <<state.token::64>>}
      started = System.monotonic_time()
      result = exchange(state, message, deadline)

      :telemetry.execute(
        [:wotex, :coap, :request, :stop],
        %{duration: System.monotonic_time() - started},
        %{code: message.code, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
      )

      next = %{
        state
        | mid: rem(state.mid + 1, 65_536),
          token: state.token + 1,
          history: Map.put(history, state.mid, now)
      }

      {:reply, result, next}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = state),
    do: {:stop, :normal, state}

  @impl GenServer
  def terminate(_, state), do: :gen_udp.close(state.socket)

  defp exchange(state, message, deadline) do
    with :ok <- Codec.validate_options(message),
         {:ok, bytes} <- Codec.encode(message),
         :ok <- transmit(state, bytes) do
      timeout = state.config.ack_timeout

      wait(
        state,
        message,
        bytes,
        deadline,
        System.monotonic_time(:millisecond) + timeout,
        timeout,
        0,
        false
      )
    else
      {:error, %Error{}} = error -> error
      {:error, _} -> {:error, Error.new(:transport_error)}
    end
  end

  defp wait(state, request, bytes, deadline, retry_at, interval, retries, acknowledged) do
    now = System.monotonic_time(:millisecond)
    retransmit? = retransmit?(request.type, acknowledged, retries)
    wake = if retransmit?, do: min(deadline, retry_at), else: deadline

    result = receive_before(state.socket, now, deadline, wake)

    case result do
      {:ok, {host, port, data}} when host == state.config.host and port == state.config.port ->
        continue(
          incoming(data, request),
          {state, request, bytes, deadline, retry_at, interval, retries, acknowledged}
        )

      {:ok, _} ->
        wait(state, request, bytes, deadline, retry_at, interval, retries, acknowledged)

      {:error, :timeout} when retransmit? and wake < deadline ->
        case transmit(state, bytes) do
          :ok ->
            wait(
              state,
              request,
              bytes,
              deadline,
              wake + interval * 2,
              interval * 2,
              retries + 1,
              false
            )

          {:error, _} ->
            {:error, Error.new(:transport_error)}
        end

      {:error, _} ->
        {:error,
         %Error{code: :timeout, effect: if(request.code in [2, 3, 4], do: :unknown, else: :none)}}
    end
  end

  defp continue(
         result,
         {state, request, bytes, deadline, retry_at, interval, retries, acknowledged}
       ) do
    case result do
      :ack ->
        wait(state, request, bytes, deadline, retry_at, interval, retries, true)

      :ignore ->
        wait(state, request, bytes, deadline, retry_at, interval, retries, acknowledged)

      {:ok, %Message{type: :con} = reply} ->
        {:ok, ack} = Codec.encode(%Message{type: :ack, code: 0, message_id: reply.message_id})
        with :ok <- transmit(state, ack), do: {:ok, reply}

      result ->
        result
    end
  end

  defp incoming(data, request) do
    with {:ok, reply} <- Codec.decode(data), :ok <- Codec.validate_options(reply) do
      cond do
        reply.type == :rst and reply.message_id == request.message_id ->
          {:error, Error.new(:reset)}

        reply.type == :ack and (reply.message_id != request.message_id or request.type != :con) ->
          :ignore

        reply.type == :ack and reply.code == 0 ->
          :ack

        reply.code < 64 or reply.token != request.token ->
          :ignore

        reply.type not in [:con, :non, :ack] ->
          :ignore

        true ->
          {:ok, reply}
      end
    else
      {:error, _} -> :ignore
    end
  end

  defp transmit(state, bytes),
    do: :gen_udp.send(state.socket, state.config.host, state.config.port, bytes)

  defp options(opts) do
    host = Keyword.get(opts, :host)
    port = Keyword.get(opts, :port, 5683)
    timeout = Keyword.get(opts, :timeout, 5000)
    ack_timeout = Keyword.get(opts, :ack_timeout)
    host = if is_binary(host), do: :inet.parse_address(String.to_charlist(host)), else: {:ok, host}

    case host do
      {:ok, host} when is_tuple(host) ->
        cond do
          Keyword.get(opts, :scheme, :coap) != :coap or
              Keyword.get(opts, :dtls_mode, :none) != :none ->
            {:error, Error.new(:unsupported_security)}

          not valid_ip?(host) ->
            {:error, Error.new(:invalid_host)}

          not bounded_integer?(port, 65_535) ->
            {:error, Error.new(:invalid_port)}

          not bounded_integer?(timeout, 60_000) ->
            {:error, Error.new(:invalid_timeout)}

          not valid_ack_timeout?(ack_timeout) ->
            {:error, Error.new(:invalid_ack_timeout)}

          not is_pid(Keyword.get(opts, :owner, self())) ->
            {:error, Error.new(:invalid_owner)}

          true ->
            {:ok,
             %{
               host: host,
               port: port,
               timeout: timeout,
               ack_timeout: ack_timeout,
               owner: Keyword.get(opts, :owner, self())
             }}
        end

      _ ->
        {:error, Error.new(:invalid_host)}
    end
  end

  defp valid_ip?(host) do
    maximum = if tuple_size(host) == 4, do: 255, else: 65_535

    tuple_size(host) in [4, 8] and
      Enum.all?(Tuple.to_list(host), &(is_integer(&1) and &1 in 0..maximum))
  end

  defp bounded_integer?(value, max), do: is_integer(value) and value in 1..max
  defp valid_ack_timeout?(nil), do: true
  defp valid_ack_timeout?(value), do: bounded_integer?(value, 3000)
  defp receive_before(_, now, deadline, _) when now >= deadline, do: {:error, :timeout}
  defp receive_before(socket, now, _, wake), do: :gen_udp.recv(socket, 0, max(0, wake - now))

  defp retransmit?(type, acknowledged, retries),
    do: type == :con and not acknowledged and retries < 4
end
