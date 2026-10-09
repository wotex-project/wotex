defmodule Wotex.Matter.Bridge.ClockProbe do
  @moduledoc """
  Encodes bounded clock probes and validates their exact native sample replies.

  These version-1 `matter-bridge` control frames are separate from requests and
  results. `encode/2` binds one 16-byte process generation to a nonzero uint64
  probe id. `decode/3` requires that same generation and id; native milliseconds
  remain uint64 values, including zero. Each complete frame includes its final
  LF and fits within 512 bytes. Missing, extra or duplicate fields, wrong roles,
  types, identities and malformed framing return a detail-free error.

  The native input owner requires strictly increasing probe ids in their own
  namespace. The Port owner retains the BEAM sample before sending and the
  sample after receiving this reply, then supplies them and the native sample
  to `Wotex.Matter.Bridge.ClockProjection.new/5`. It separately owns authenticated
  process/probe admission and qualified sampling-error and elapsed-time-rate
  bounds. Encoding or decoding neither establishes those qualifications nor
  changes an operation deadline. These pure functions read no clock and open
  no process or connection.
  """

  alias Wotex.Matter.Error

  @uint64 0xFFFFFFFFFFFFFFFF
  @keys ~w(v backend type generation id native_ms)
  @limits [
    max_bytes: 511,
    max_depth: 1,
    max_nodes: 16,
    max_collection_size: 6,
    max_string_bytes: 32
  ]

  @doc "Encodes one five-field probe for an explicit generation and identity."
  @spec encode(term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(generation, id)
      when is_binary(generation) and byte_size(generation) == 16 and is_integer(id) and
             id in 1..@uint64 do
    frame = %{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "clock-probe",
      "generation" => Base.encode16(generation, case: :lower),
      "id" => Integer.to_string(id)
    }

    {:ok, Jason.encode!(frame) <> "\n"}
  end

  def encode(_, _), do: invalid()

  @doc "Decodes only the correlated six-field sample, retaining its native clock domain."
  @spec decode(term(), term(), term()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def decode(frame, generation, id)
      when is_binary(frame) and byte_size(frame) in 1..512 and is_binary(generation) and
             byte_size(generation) == 16 and is_integer(id) and id in 1..@uint64 do
    with true <- :binary.last(frame) == 10,
         body = binary_part(frame, 0, byte_size(frame) - 1),
         :nomatch <- :binary.match(body, ["\n", "\r", <<0>>]),
         {:ok, value} <- Wotex.JSON.decode(body, @limits),
         true <- is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(@keys),
         true <- value["v"] === 1 and value["backend"] === "matter-bridge",
         true <- value["type"] === "clock-sample",
         true <- value["generation"] === Base.encode16(generation, case: :lower),
         true <- value["id"] === Integer.to_string(id),
         {:ok, native_ms} <- uint64(value["native_ms"]) do
      {:ok, native_ms}
    else
      _ -> invalid()
    end
  end

  def decode(_, _, _), do: invalid()

  defp uint64(value) when is_binary(value) and byte_size(value) in 1..20 do
    case Integer.parse(value) do
      {number, ""} when number in 0..@uint64 ->
        if Integer.to_string(number) == value, do: {:ok, number}, else: :error

      _ ->
        :error
    end
  end

  defp uint64(_), do: :error
  defp invalid, do: {:error, Error.new(:invalid_frame)}
end
