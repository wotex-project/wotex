defmodule Wotex.CoAP.Exchange do
  @moduledoc """
  Holds one bounded CoAP exchange without owning a clock or datagram resource.

  All times, the request identity and the initial retransmission interval are
  explicit inputs. Confirmable retransmission preserves encoded bytes and ends
  after four retries; an empty ACK waits only for the original deadline. This
  value classifies correlated responses while the connection owns ACKs, RSTs,
  duplicate history and completion of the surrounding whole-body interaction.
  """

  alias Wotex.CoAP.{Codec, Error, Message}
  @enforce_keys [:request, :bytes, :deadline, :retry_at, :interval]
  defstruct [:request, :bytes, :deadline, :retry_at, :interval, retries: 0, acknowledged: false]

  @type t :: %__MODULE__{
          request: Message.t(),
          bytes: binary(),
          deadline: integer(),
          retry_at: integer(),
          interval: pos_integer(),
          retries: 0..4,
          acknowledged: boolean()
        }
  @type outcome :: :ignore | :ack | {:ok, Message.t()} | {:error, Error.t()}

  @doc "Validates one wire request and fixes its bytes and finite retry schedule."
  @spec new(Message.t(), integer(), integer(), pos_integer()) :: {:ok, t()} | {:error, Error.t()}
  def new(%Message{type: type, code: code} = message, now, deadline, interval)
      when type in [:con, :non] and code in 1..4 and is_integer(now) and is_integer(deadline) and
             deadline > now and deadline - now <= 60_000 and is_integer(interval) and
             interval in 1..3000 do
    with :ok <- Codec.validate_options(message), {:ok, bytes} <- Codec.encode(message) do
      {:ok,
       %__MODULE__{
         request: message,
         bytes: bytes,
         deadline: deadline,
         retry_at: now + interval,
         interval: interval
       }}
    end
  end

  def new(_, _, _, _), do: {:error, Error.new(:invalid_exchange)}

  @doc "Returns the next absolute wake time without consulting a clock."
  @spec wake(t()) :: integer() | {:error, Error.t()}
  def wake(exchange) do
    with :ok <- validate(exchange), do: next_wake(exchange)
  end

  @doc "Advances a due retry, ends an expired exchange, or preserves an early timer."
  @spec tick(t(), integer()) ::
          :timeout | {:wait, t()} | {:send, binary(), t()} | {:error, Error.t()}
  def tick(exchange, now) when is_integer(now) do
    with :ok <- validate(exchange), do: advance(exchange, now)
  end

  def tick(_, _), do: invalid()

  @doc "Classifies a validated response by token, MID and response class."
  @spec incoming(t(), Message.t()) :: outcome()
  def incoming(exchange, reply) do
    with :ok <- validate(exchange), do: response(exchange.request, reply)
  end

  defp next_wake(%{request: %{type: :con}, acknowledged: false} = exchange),
    do: min(exchange.deadline, exchange.retry_at)

  defp next_wake(exchange), do: exchange.deadline

  defp advance(exchange, now) do
    cond do
      now >= exchange.deadline ->
        :timeout

      now < next_wake(exchange) ->
        {:wait, exchange}

      exchange.retries == 4 ->
        :timeout

      true ->
        next = %{
          exchange
          | interval: exchange.interval * 2,
            retry_at: now + exchange.interval * 2,
            retries: exchange.retries + 1
        }

        {:send, exchange.bytes, next}
    end
  end

  defp response(request, %Message{} = reply) do
    case Codec.validate_options(reply) do
      :ok -> classify(request, reply)
      _ -> :ignore
    end
  end

  defp response(_, _), do: :ignore

  defp validate(
         %__MODULE__{
           request: %Message{type: type, code: code} = request,
           bytes: bytes,
           deadline: deadline,
           retry_at: retry_at,
           interval: interval,
           retries: retries,
           acknowledged: acknowledged
         } = exchange
       )
       when map_size(exchange) == 8 and type in [:con, :non] and code in 1..4 and
              is_binary(bytes) and byte_size(bytes) <= 1152 and is_integer(deadline) and
              is_integer(retry_at) and is_integer(interval) and interval in 1..48_000 and
              retries in 0..4 and is_boolean(acknowledged) do
    with :ok <- Codec.validate_options(request),
         {:ok, ^bytes} <- Codec.encode(request) do
      :ok
    else
      _ -> invalid()
    end
  end

  defp validate(_), do: invalid()
  defp invalid, do: {:error, Error.new(:invalid_exchange)}

  defp classify(request, reply) do
    cond do
      reply.type == :rst and reply.message_id == request.message_id ->
        {:error, Error.new(:reset)}

      reply.type == :ack and (reply.message_id != request.message_id or request.type != :con) ->
        :ignore

      reply.type == :ack and reply.code == 0 ->
        :ack

      not response_for?(reply, request) ->
        :ignore

      reply.code in 64..95 ->
        {:ok, reply}

      reply.code in 128..191 ->
        {:error, Error.new(:remote_response, nil, %{code: reply.code})}

      true ->
        {:error, Error.new(:invalid_response)}
    end
  end

  defp response_for?(reply, request),
    do: reply.token == request.token and reply.type in [:con, :non, :ack] and reply.code >= 32
end
