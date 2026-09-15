defmodule Wotex.CoAP.Native.Report do
  @moduledoc """
  Validates native OSCORE report and body-event envelopes.

  `decode/4` binds a report to an established subscription and generation,
  reconstructs its complete `Wotex.CoAP.Message`, and verifies that the five
  wire metadata fields equal the Message's Observe, ETag, Content-Format and
  Max-Age options. `body_event/3` removes only the common correlation fields
  from a streamed report frame before `Wotex.CoAP.Native.Body` receives it.
  Unary body events use `body_event/2` and carry no generation or report credit.

  `terminal/3` admits the reserved established-subscription failure envelope
  without a report sequence. Every decoder uses exact field sets and finite
  identities. Sequence continuity, frame credit, delivery queues and process
  cleanup belong to the native session owner.
  """

  alias Wotex.CoAP.{Codec, Error, Message, Native.Wire}
  alias Wotex.CoAP.Observation.Report, as: ObservationReport

  @maximum_counter 0xFFFFFFFFFFFFFFFF

  @typedoc "One complete, correlated native report ready for owner accounting."
  @type decoded :: %{
          message: Wotex.CoAP.Message.t(),
          metadata: ObservationReport.metadata(),
          report_seq: pos_integer()
        }

  @doc "Validates one complete report for an exact subscription generation."
  @spec decode(term(), term(), term(), Wire.completed_bodies()) ::
          {:ok, decoded()} | {:error, Error.t()}
  def decode(frame, subscription_id, generation, completed_bodies \\ %{})

  def decode(
        %{
          "version" => 1,
          "subscription_id" => subscription_id,
          "generation" => generation,
          "report_seq" => sequence,
          "event" => "report",
          "value" => value,
          "metadata" => metadata
        } = frame,
        subscription_id,
        generation,
        completed_bodies
      )
      when map_size(frame) == 7 and is_integer(generation) and
             generation in 1..@maximum_counter and is_integer(sequence) and
             sequence in 1..@maximum_counter and is_map(completed_bodies) do
    with true <- identifier?(subscription_id),
         {:ok, message} <- Wire.decode_message(value, completed_bodies),
         {:ok, metadata} <- metadata(metadata),
         {:ok, actual_metadata} <- message_metadata(message),
         true <- actual_metadata == metadata do
      {:ok, %{message: message, metadata: metadata, report_seq: sequence}}
    else
      _ -> failure()
    end
  end

  def decode(_, _, _, _), do: failure()

  @doc "Projects an exact unary body event after matching its request ID."
  @spec body_event(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def body_event(frame, id), do: unary_body_event(frame, id)

  @doc "Projects an exact report body event and its sequence after correlation."
  @spec body_event(term(), term(), term()) ::
          {:ok, pos_integer(), map()} | {:error, Error.t()}
  def body_event(frame, subscription_id, generation) do
    report_body_event(frame, subscription_id, generation)
  end

  @doc "Validates an established subscription's exact terminal error envelope."
  @spec terminal(term(), term(), term()) :: {:error, Error.t()}
  def terminal(
        %{
          "version" => 1,
          "subscription_id" => subscription_id,
          "generation" => generation,
          "event" => "error",
          "value" => value,
          "metadata" => metadata
        } = frame,
        subscription_id,
        generation
      )
      when map_size(frame) == 6 and is_integer(generation) and
             generation in 1..@maximum_counter and map_size(metadata) == 0 do
    with true <- identifier?(subscription_id),
         {:ok, error} <- Wire.decode_error(value) do
      {:error, error}
    else
      _ -> failure()
    end
  end

  def terminal(_, _, _), do: failure()

  defp unary_body_event(
         %{
           "version" => 1,
           "id" => id,
           "event" => "body_begin",
           "body_id" => body_id,
           "length" => length,
           "sha256" => hash
         } = frame,
         id
       )
       when map_size(frame) == 6 do
    project(id, %{
      "event" => "body_begin",
      "body_id" => body_id,
      "length" => length,
      "sha256" => hash
    })
  end

  defp unary_body_event(
         %{
           "version" => 1,
           "id" => id,
           "event" => "body_chunk",
           "body_id" => body_id,
           "offset" => offset,
           "data" => data
         } = frame,
         id
       )
       when map_size(frame) == 6 do
    project(id, %{
      "event" => "body_chunk",
      "body_id" => body_id,
      "offset" => offset,
      "data" => data
    })
  end

  defp unary_body_event(
         %{"version" => 1, "id" => id, "event" => "body_end", "body_id" => body_id} = frame,
         id
       )
       when map_size(frame) == 4,
       do: project(id, %{"event" => "body_end", "body_id" => body_id})

  defp unary_body_event(_, _), do: failure()

  defp report_body_event(
         %{
           "version" => 1,
           "id" => id,
           "generation" => generation,
           "report_seq" => sequence,
           "event" => "body_begin",
           "body_id" => body_id,
           "length" => length,
           "sha256" => hash
         } = frame,
         id,
         generation
       )
       when map_size(frame) == 8 do
    project(sequence, id, %{
      "event" => "body_begin",
      "body_id" => body_id,
      "length" => length,
      "sha256" => hash
    })
  end

  defp report_body_event(
         %{
           "version" => 1,
           "id" => id,
           "generation" => generation,
           "report_seq" => sequence,
           "event" => "body_chunk",
           "body_id" => body_id,
           "offset" => offset,
           "data" => data
         } = frame,
         id,
         generation
       )
       when map_size(frame) == 8 do
    project(sequence, id, %{
      "event" => "body_chunk",
      "body_id" => body_id,
      "offset" => offset,
      "data" => data
    })
  end

  defp report_body_event(
         %{
           "version" => 1,
           "id" => id,
           "generation" => generation,
           "report_seq" => sequence,
           "event" => "body_end",
           "body_id" => body_id
         } = frame,
         id,
         generation
       )
       when map_size(frame) == 6,
       do: project(sequence, id, %{"event" => "body_end", "body_id" => body_id})

  defp report_body_event(_, _, _), do: failure()

  defp project(id, event), do: if(identifier?(id), do: {:ok, event}, else: failure())

  defp project(sequence, id, event) do
    if identifier?(id) and is_integer(sequence) and sequence in 1..@maximum_counter,
      do: {:ok, sequence, event},
      else: failure()
  end

  defp metadata(
         %{
           "code" => code,
           "observe" => observe,
           "etag" => etag,
           "content_format" => content_format,
           "max_age" => max_age
         } = metadata
       )
       when map_size(metadata) == 5 and is_integer(code) and code in 64..94 and
              is_integer(observe) and observe in 0..16_777_215 and
              (is_nil(content_format) or
                 (is_integer(content_format) and content_format in 0..65_535)) and
              is_integer(max_age) and max_age in 0..4_294_967_295 do
    case etag(etag) do
      {:ok, etag} ->
        {:ok,
         %{
           code: code,
           observe: observe,
           etag: etag,
           content_format: content_format,
           max_age: max_age
         }}

      :error ->
        :error
    end
  end

  defp metadata(_), do: :error

  defp message_metadata(%Message{code: code} = message) when code in 64..94 do
    with [observe] <- Codec.option(message, 6),
         [etag] <- singleton(Codec.option(message, 4), nil),
         [content_format] <- singleton_integer(Codec.option(message, 12), nil),
         [max_age] <- singleton_integer(Codec.option(message, 14), 60) do
      {:ok,
       %{
         code: code,
         observe: :binary.decode_unsigned(observe),
         etag: etag,
         content_format: content_format,
         max_age: max_age
       }}
    else
      _ -> :error
    end
  end

  defp message_metadata(_), do: :error

  defp singleton([], default), do: [default]
  defp singleton([value], _), do: [value]
  defp singleton(_, _), do: :error

  defp singleton_integer(values, default) do
    case singleton(values, nil) do
      [nil] -> [default]
      [value] -> [:binary.decode_unsigned(value)]
      :error -> :error
    end
  end

  defp etag(nil), do: {:ok, nil}

  defp etag(value) do
    case Wire.decode_bytes(value, 8) do
      {:ok, bytes} when byte_size(bytes) in 1..8 -> {:ok, bytes}
      _ -> :error
    end
  end

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..64,
    do: Enum.all?(:binary.bin_to_list(value), &(&1 in 0x20..0x7E))

  defp identifier?(_), do: false
  defp failure, do: {:error, Error.new(:native_protocol_error)}
end
