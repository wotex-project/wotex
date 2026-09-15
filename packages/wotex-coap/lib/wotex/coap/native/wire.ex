defmodule Wotex.CoAP.Native.Wire do
  @moduledoc """
  Validates the bounded JSON-line boundary for the optional native OSCORE helper.

  `line/1` and `frame/1` apply the WCO-C07 byte, depth, collection, node and
  integer-domain limits before an owner interprets a frame. `ready/1` binds the
  startup event to the pinned libcoap revision. `response/4` requires an exact
  request identity and operation-specific result envelope, converts canonical
  byte values into binaries and constructs a complete `Wotex.CoAP.Message`.

  A streamed body can be supplied to `response/4` only after another component
  has authenticated and completely assembled it. The decoder never exposes a
  body identifier through a Message. These functions perform no filesystem,
  process, Port, clock or network operation. Process lifetime, identifier reuse,
  deadlines, body-event correlation and report credit remain responsibilities
  of the native session owner.
  """

  alias Wotex.CoAP.{Codec, Error, Message}

  @maximum_line_bytes 131_072
  @maximum_frame_bytes @maximum_line_bytes - 1
  @maximum_inline_bytes 32_768
  @maximum_body_bytes 1_048_576
  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @json_limits [
    max_bytes: @maximum_frame_bytes,
    max_depth: 8,
    max_nodes: 4_096,
    max_collection_size: 1_024,
    max_string_bytes: @maximum_frame_bytes
  ]
  @null_operations [:open, :body_begin, :body_chunk, :body_end, :credit, :cancel, :close]
  @error_codes %{
    "body_limit" => :body_limit,
    "busy" => :busy,
    "cleanup_timeout" => :cleanup_timeout,
    "connection_closed" => :connection_closed,
    "context_store_corrupt" => :context_store_corrupt,
    "context_store_full" => :context_store_full,
    "context_store_locked" => :context_store_locked,
    "context_store_unavailable" => :context_store_unavailable,
    "deadline_exceeded" => :deadline_exceeded,
    "fresh_context_required" => :fresh_context_required,
    "invalid_cancellation_response" => :invalid_cancellation_response,
    "invalid_context_store" => :invalid_context_store,
    "invalid_request" => :invalid_request,
    "invalid_response" => :invalid_response,
    "message_too_large" => :message_too_large,
    "native_protocol_error" => :native_protocol_error,
    "native_unavailable" => :native_unavailable,
    "observation_active" => :observation_active,
    "observation_failed" => :observation_failed,
    "observation_stale" => :observation_stale,
    "overlapping_event_report" => :overlapping_event_report,
    "receiver_overflow" => :receiver_overflow,
    "remote_response" => :remote_response,
    "representation_changed" => :representation_changed,
    "security_handshake_failed" => :security_handshake_failed,
    "sequence_exhausted" => :sequence_exhausted,
    "timeout" => :timeout,
    "unsupported_native_backend" => :unsupported_native_backend
  }

  @typedoc "A completed body indexed by its native identifier."
  @type completed_bodies :: %{optional(String.t()) => binary()}

  @doc "Decodes one LF-terminated JSON line whose total size is at most 128 KiB."
  @spec line(term()) :: {:ok, term()} | {:error, Error.t()}
  def line(bytes)
      when is_binary(bytes) and byte_size(bytes) in 2..@maximum_line_bytes and
             binary_part(bytes, byte_size(bytes) - 1, 1) == "\n" do
    frame = binary_part(bytes, 0, byte_size(bytes) - 1)

    if :binary.match(frame, ["\n", "\r"]) == :nomatch,
      do: frame(frame),
      else: failure()
  end

  def line(_), do: failure()

  @doc "Decodes one newline-free Port frame under the WCO-C07 resource limits."
  @spec frame(term()) :: {:ok, term()} | {:error, Error.t()}
  def frame(bytes) when is_binary(bytes) and byte_size(bytes) in 1..@maximum_frame_bytes do
    with true <- :binary.match(bytes, ["\n", "\r"]) == :nomatch,
         {:ok, value} <- Wotex.JSON.decode(bytes, @json_limits),
         :ok <- integer_domain(value) do
      {:ok, value}
    else
      _ -> failure()
    end
  end

  def frame(_), do: failure()

  @doc "Validates the exact startup identity for the pinned libcoap backend."
  @spec ready(term()) :: {:ok, map()} | {:error, Error.t()}
  def ready(
        %{
          "version" => 1,
          "event" => "ready",
          "backend" => "libcoap",
          "revision" => @revision
        } = frame
      )
      when map_size(frame) == 4,
      do: {:ok, %{event: :ready, backend: "libcoap", revision: @revision}}

  def ready(_), do: failure()

  @doc """
  Decodes an exact response for `operation` and `id`.

  `completed_bodies` contains only bodies already verified for this originating
  call. A body reference is consumed conceptually by the native owner; this pure
  function does not mutate the supplied map.
  """
  @spec response(atom(), term(), term(), completed_bodies()) ::
          {:ok, term()} | {:error, Error.t()}
  def response(operation, frame, id, completed_bodies \\ %{})

  def response(
        operation,
        %{"version" => 1, "id" => id, "ok" => true, "result" => result} = frame,
        id,
        completed_bodies
      )
      when map_size(frame) == 4 and is_map(completed_bodies) do
    if identifier?(id), do: result(operation, result, id, completed_bodies), else: failure()
  end

  def response(
        _,
        %{"version" => 1, "id" => id, "ok" => false, "error" => error} = frame,
        id,
        completed_bodies
      )
      when map_size(frame) == 4 and is_map(completed_bodies) do
    with true <- identifier?(id),
         {:ok, error} <- error(error),
         do: {:error, error},
         else: (_ -> failure())
  end

  def response(_, _, _, _), do: failure()

  defp result(operation, nil, _, _) when operation in @null_operations, do: {:ok, nil}

  defp result(
         :observe,
         %{"subscription_id" => id, "generation" => generation} = result,
         id,
         _
       )
       when map_size(result) == 2 and is_integer(generation) and
              generation in 1..0xFFFFFFFFFFFFFFFF,
       do: {:ok, %{subscription_id: id, generation: generation}}

  defp result(:request, result, _, bodies), do: message(result, bodies)
  defp result(_, _, _, _), do: failure()

  defp message(
         %{
           "type" => type,
           "code" => code,
           "message_id" => message_id,
           "token" => token,
           "options" => options
         } = value,
         bodies
       )
       when map_size(value) == 6 and is_integer(code) and code in 0..255 and
              is_integer(message_id) and message_id in 0..65_535 do
    with {:ok, type} <- message_type(type),
         {:ok, token} <- decode_bytes(token, 8),
         {:ok, options} <- options(options, 0, []),
         {:ok, payload} <- payload(value, bodies),
         message = %Message{
           type: type,
           code: code,
           message_id: message_id,
           token: token,
           options: options,
           payload: payload
         },
         :ok <- Codec.validate_options(message),
         {:ok, _} <- Codec.encode(%{message | payload: <<>>}) do
      {:ok, message}
    else
      _ -> failure()
    end
  end

  defp message(_, _), do: failure()

  defp payload(value, bodies) do
    case {Map.fetch(value, "payload"), Map.fetch(value, "body_id")} do
      {{:ok, encoded}, :error} ->
        decode_bytes(encoded, @maximum_inline_bytes)

      {:error, {:ok, body_id}} ->
        with true <- identifier?(body_id),
             {:ok, body} <- Map.fetch(bodies, body_id),
             true <- is_binary(body) and byte_size(body) <= @maximum_body_bytes do
          {:ok, body}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp options([], count, acc) when count <= 64, do: {:ok, Enum.reverse(acc)}

  defp options([%{"number" => number, "value" => value} = option | rest], count, acc)
       when map_size(option) == 2 and count < 64 and is_integer(number) and
              number in 0..65_535 do
    with {:ok, value} <- decode_bytes(value, 1_152),
         do: options(rest, count + 1, [{number, value} | acc])
  end

  defp options(_, _, _), do: :error

  @doc false
  @spec decode_bytes(term(), non_neg_integer()) :: {:ok, binary()} | :error
  def decode_bytes(%{"type" => "bytes", "base64" => encoded} = value, maximum)
      when map_size(value) == 2 and is_binary(encoded) and is_integer(maximum) and
             maximum in 0..@maximum_body_bytes do
    maximum_encoded = 4 * div(maximum + 2, 3)

    if byte_size(encoded) <= maximum_encoded do
      case Base.decode64(encoded) do
        {:ok, decoded} when byte_size(decoded) <= maximum ->
          if Base.encode64(decoded) == encoded, do: {:ok, decoded}, else: :error

        _ ->
          :error
      end
    else
      :error
    end
  end

  def decode_bytes(_, _), do: :error

  defp error(%{"code" => code} = value) when map_size(value) in 1..2 and is_binary(code) do
    with true <- Map.keys(value) -- ["code", "status"] == [],
         {:ok, code} <- Map.fetch(@error_codes, code),
         {:ok, details} <- status(value) do
      {:ok, Error.new(code, nil, details)}
    else
      _ -> :error
    end
  end

  defp error(_), do: :error

  defp status(%{"status" => status})
       when is_integer(status) and status in -0x8000000000000000..0xFFFFFFFFFFFFFFFF,
       do: {:ok, %{status: status}}

  defp status(value), do: if(Map.has_key?(value, "status"), do: :error, else: {:ok, %{}})

  defp integer_domain(value)
       when is_integer(value) and value not in -0x8000000000000000..0xFFFFFFFFFFFFFFFF,
       do: :error

  defp integer_domain(value) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {_, child}, :ok ->
      case integer_domain(child) do
        :ok -> {:cont, :ok}
        :error -> {:halt, :error}
      end
    end)
  end

  defp integer_domain(value) when is_list(value) do
    Enum.reduce_while(value, :ok, fn child, :ok ->
      case integer_domain(child) do
        :ok -> {:cont, :ok}
        :error -> {:halt, :error}
      end
    end)
  end

  defp integer_domain(_), do: :ok

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..64,
    do: Enum.all?(:binary.bin_to_list(value), &(&1 in 0x20..0x7E))

  defp identifier?(_), do: false
  defp message_type("con"), do: {:ok, :con}
  defp message_type("non"), do: {:ok, :non}
  defp message_type("ack"), do: {:ok, :ack}
  defp message_type("rst"), do: {:ok, :rst}
  defp message_type(_), do: :error
  defp failure, do: {:error, Error.new(:native_protocol_error)}
end
