defmodule Wotex.Runtime.Codec.Wire do
  @moduledoc """
  Pure bounded JSON-line framing for the process-codec v1 contract.

  The consumer owns process startup, ready state, request correlation,
  deadlines and cleanup. This module validates syntax and configuration
  consistency only. Inspection omits buffered foreign bytes.
  """

  alias Wotex.Runtime.Codec.{Grammar, Value}
  alias Wotex.Runtime.Implementation.{Error, JSON}
  alias Wotex.Runtime.Implementation.Grammar, as: ImplementationGrammar

  @safe 9_007_199_254_740_991
  @frame 131_072
  @queue 262_144
  @json %{bytes: @frame - 1, depth: 24, nodes: 4096, entries: 256, string: 87_384}
  @identity ~w(instance_id generation descriptor_sha256 contract_id contract_sha256 decode_ms configuration_sha256)
  @refusals ~w(invalid_input unsupported_format unsupported_value output_limit)
  @derive {Inspect, except: [:buffer]}
  @typedoc "Immutable partial frame and explicitly supplied allocation ceilings."
  @type t :: %__MODULE__{buffer: binary(), frame_bytes: pos_integer(), queue_bytes: pos_integer()}
  defstruct buffer: <<>>, frame_bytes: @frame, queue_bytes: @queue

  @doc "Creates an empty stream under closed frame_bytes and queue_bytes limits."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(limits) do
    if ImplementationGrammar.closed?(limits, [:frame_bytes, :queue_bytes]) and
         is_integer(limits.frame_bytes) and limits.frame_bytes in 1..@frame and
         is_integer(limits.queue_bytes) and limits.queue_bytes in 1..@queue do
      {:ok, %__MODULE__{frame_bytes: limits.frame_bytes, queue_bytes: limits.queue_bytes}}
    else
      {:error, Error.new(:invalid_configuration, :admission, %{})}
    end
  end

  @doc "Admits a chunk before concatenating and returns complete validated frames in order."
  @spec feed(term(), term()) :: {:ok, [map()], t()} | {:error, Error.t()}
  def feed(%__MODULE__{} = wire, chunk) do
    with true <- valid?(wire),
         true <- is_binary(chunk) and byte_size(wire.buffer) + byte_size(chunk) <= wire.queue_bytes,
         {:ok, frames, buffer} <- split(wire.buffer <> chunk, wire.frame_bytes, []) do
      {:ok, frames, %{wire | buffer: buffer}}
    else
      _ -> failure()
    end
  end

  def feed(_, _), do: failure()

  @doc "Validates one complete LF-terminated frame, including duplicate-key rejection."
  @spec decode(term()) :: {:ok, map()} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) and byte_size(bytes) in 2..@frame do
    size = byte_size(bytes) - 1

    with <<body::binary-size(^size), 10>> <- bytes,
         :nomatch <- :binary.match(body, ["\r", "\n"]),
         {:ok, frame} <- JSON.decode(body, @json),
         true <- frame?(frame) do
      {:ok, frame}
    else
      _ -> failure()
    end
  end

  def decode(_), do: failure()

  @doc "Validates a frame map and emits its JCS bytes followed by LF."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(frame) do
    with {:ok, body} <- encoded(frame) do
      {:ok, body <> "\n"}
    end
  end

  @doc "Validates the closed v1 frame grammar without implying exchange state."
  @spec validate(term()) :: {:ok, map()} | {:error, Error.t()}
  def validate(frame) do
    with {:ok, _} <- encoded(frame), do: {:ok, frame}
  end

  defp encoded(frame) do
    with true <- frame?(frame),
         {:ok, body} <- JSON.encode(frame, @json) do
      {:ok, body}
    else
      _ -> failure()
    end
  end

  defp valid?(wire) do
    ImplementationGrammar.closed?(Map.from_struct(wire), [:buffer, :frame_bytes, :queue_bytes]) and
      is_binary(wire.buffer) and byte_size(wire.buffer) < wire.frame_bytes and
      byte_size(wire.buffer) <= wire.queue_bytes and :binary.match(wire.buffer, "\n") == :nomatch and
      match?({:ok, _}, new(Map.take(wire, [:frame_bytes, :queue_bytes])))
  end

  defp split(bytes, limit, frames) do
    case :binary.match(bytes, "\n") do
      {index, 1} when index + 1 <= limit ->
        <<line::binary-size(^index + 1), rest::binary>> = bytes

        with {:ok, frame} <- decode(line) do
          split(rest, limit, [frame | frames])
        end

      :nomatch when byte_size(bytes) < limit ->
        {:ok, Enum.reverse(frames), bytes}

      _ ->
        failure()
    end
  end

  defp frame?(%{"v" => 1, "type" => "hello"} = frame), do: hello?(frame)

  defp frame?(%{"v" => 1, "type" => "ready"} = frame),
    do: closed?(frame, @identity) and identity?(frame)

  defp frame?(%{"v" => 1, "type" => "decode"} = frame), do: decode_frame?(frame)

  defp frame?(%{"v" => 1, "type" => "result"} = frame),
    do:
      closed?(frame, ~w(seq request_id value)) and correlation?(frame) and
        match?({:ok, _}, Value.validate(frame["value"]))

  defp frame?(%{"v" => 1, "type" => "refusal"} = frame),
    do:
      closed?(frame, ~w(seq request_id code)) and correlation?(frame) and
        frame["code"] in @refusals

  defp frame?(%{"v" => 1, "type" => "stop"} = frame), do: closed?(frame, [])

  defp frame?(_), do: false
  defp closed?(frame, keys), do: ImplementationGrammar.closed?(frame, ["v", "type" | keys])

  defp hello?(frame) do
    closed?(frame, ["configuration" | @identity]) and identity?(frame) and
      Grammar.flat?(frame["configuration"]) and
      JSON.digest(frame["configuration"]) == {:ok, frame["configuration_sha256"]}
  end

  defp identity?(frame) do
    ImplementationGrammar.token?(frame["instance_id"]) and positive?(frame["generation"], @safe) and
      ImplementationGrammar.digest?(frame["descriptor_sha256"]) and
      ImplementationGrammar.token?(frame["contract_id"]) and
      ImplementationGrammar.digest?(frame["contract_sha256"]) and
      positive?(frame["decode_ms"], 1000) and
      ImplementationGrammar.digest?(frame["configuration_sha256"])
  end

  defp decode_frame?(frame) do
    closed?(frame, ~w(seq request_id budget_ms bytes metadata)) and correlation?(frame) and
      positive?(frame["budget_ms"], 1000) and input?(frame["bytes"]) and
      Grammar.flat?(frame["metadata"])
  end

  defp correlation?(frame), do: positive?(frame["seq"], @safe) and request_id?(frame["request_id"])

  defp request_id?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)

  defp positive?(value, max), do: is_integer(value) and value in 1..max

  defp input?(%{"type" => "bytes", "base64" => value} = input)
       when is_binary(value) and byte_size(value) <= 87_384 do
    with true <- ImplementationGrammar.closed?(input, ~w(type base64)),
         true <- decoded_size?(value),
         {:ok, decoded} <- Base.decode64(value),
         true <- byte_size(decoded) <= 65_536 and Base.encode64(decoded) == value do
      true
    else
      _ -> false
    end
  end

  defp input?(_), do: false
  # Check expansion before allocating decoded bytes, including the two possible
  # padding bytes at the maximum encoded input length.
  defp decoded_size?(value) do
    padding =
      cond do
        String.ends_with?(value, "==") -> 2
        String.ends_with?(value, "=") -> 1
        true -> 0
      end

    rem(byte_size(value), 4) == 0 and div(byte_size(value) * 3, 4) - padding <= 65_536
  end

  defp failure, do: {:error, Error.new(:protocol_fault, :decode, %{})}
end
