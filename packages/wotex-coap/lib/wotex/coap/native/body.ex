defmodule Wotex.CoAP.Native.Body do
  @moduledoc """
  Assembles one bounded native response body before public delivery.

  `push/2` accepts the helper's exact begin, chunk and end event objects. Chunks
  use the canonical byte envelope, must begin at the next expected
  offset and cannot exceed either 32,768 bytes or the declared body length.
  `take/2` releases the binary only after `body_end` verifies the declared
  length and lowercase SHA-256 digest.

  Any malformed event, interleaving, mismatch or forged state moves the returned
  state to a permanent failed phase and drops its body reference. A caller must
  carry the returned state forward. Only `take/2` returns payload bytes, and it
  requires a completed state. The value owns no process, timer, filesystem object,
  Port or network resource; correlation, deadlines and generation cleanup belong
  to the native session owner.
  """

  alias Wotex.CoAP.{Error, Native.Wire}

  @maximum_body_bytes 1_048_576
  @maximum_chunk_bytes 32_768
  @derive {Inspect, only: [:phase]}
  defstruct phase: :idle,
            id: nil,
            length: 0,
            used: 0,
            expected_hash: nil,
            bytes: <<>>

  @opaque t :: %__MODULE__{
            phase: :idle | :active | :complete | :failed,
            id: String.t() | nil,
            length: 0..1_048_576,
            used: 0..1_048_576,
            expected_hash: binary() | nil,
            bytes: binary()
          }

  @doc "Creates an empty body assembler without allocating a payload buffer."
  @spec new() :: t()
  def new, do: struct(__MODULE__)

  @doc "Applies one exact body event and returns the next state or a poisoned state."
  @spec push(term(), term()) :: {:ok, t()} | {:error, Error.t(), t()}
  def push(%__MODULE__{} = state, event) do
    case validate(state) do
      :ok -> event(state, event)
      :error -> reject()
    end
  end

  def push(_, _), do: reject()

  @doc "Returns one completed body by exact ID and resets the assembler to idle."
  @spec take(term(), term()) :: {:ok, binary(), t()} | {:error, Error.t(), t()}
  def take(%__MODULE__{phase: :complete, id: id, bytes: bytes} = state, id) do
    case validate(state) do
      :ok -> {:ok, bytes, new()}
      :error -> reject()
    end
  end

  def take(%__MODULE__{}, _), do: reject()
  def take(_, _), do: reject()

  defp event(
         %__MODULE__{phase: :idle},
         %{
           "event" => "body_begin",
           "body_id" => id,
           "length" => length,
           "sha256" => hash
         } = event
       )
       when map_size(event) == 4 and is_integer(length) and length in 0..@maximum_body_bytes do
    with true <- identifier?(id),
         {:ok, decoded_hash} <- decode_hash(hash) do
      {:ok,
       %__MODULE__{
         phase: :active,
         id: id,
         length: length,
         expected_hash: decoded_hash
       }}
    else
      _ -> reject()
    end
  end

  defp event(
         %__MODULE__{phase: :active, id: id, length: length, used: used, bytes: bytes} = state,
         %{"event" => "body_chunk", "body_id" => id, "offset" => used, "data" => data} = event
       )
       when map_size(event) == 4 do
    capacity = min(@maximum_chunk_bytes, length - used)

    case Wire.decode_bytes(data, capacity) do
      {:ok, chunk} -> {:ok, %{state | used: used + byte_size(chunk), bytes: bytes <> chunk}}
      :error -> reject()
    end
  end

  defp event(
         %__MODULE__{
           phase: :active,
           id: id,
           length: length,
           used: length,
           expected_hash: expected,
           bytes: bytes
         } = state,
         %{"event" => "body_end", "body_id" => id} = event
       )
       when map_size(event) == 2 do
    if :crypto.hash(:sha256, bytes) == expected,
      do: {:ok, %{state | phase: :complete}},
      else: reject()
  end

  defp event(_, _), do: reject()

  defp validate(
         %__MODULE__{
           phase: :idle,
           id: nil,
           length: 0,
           used: 0,
           expected_hash: nil,
           bytes: <<>>
         } = state
       )
       when map_size(state) == 7,
       do: :ok

  defp validate(
         %__MODULE__{
           phase: phase,
           id: id,
           length: length,
           used: used,
           expected_hash: hash,
           bytes: bytes
         } = state
       )
       when map_size(state) == 7 and phase in [:active, :complete] do
    if transfer_fields?(id, length, used, hash, bytes),
      do: validate_phase(phase, length, used, hash, bytes),
      else: :error
  end

  defp validate(
         %__MODULE__{
           phase: :failed,
           id: nil,
           length: 0,
           used: 0,
           expected_hash: nil,
           bytes: <<>>
         } = state
       )
       when map_size(state) == 7,
       do: :ok

  defp validate(_), do: :error

  defp transfer_fields?(id, length, used, hash, bytes) do
    identifier?(id) and is_integer(length) and length in 0..@maximum_body_bytes and
      is_integer(used) and used >= 0 and used <= length and is_binary(hash) and
      byte_size(hash) == 32 and is_binary(bytes) and byte_size(bytes) == used
  end

  defp validate_phase(:active, _, _, _, _), do: :ok

  defp validate_phase(:complete, length, length, hash, bytes),
    do: if(:crypto.hash(:sha256, bytes) == hash, do: :ok, else: :error)

  defp validate_phase(:complete, _, _, _, _), do: :error

  defp decode_hash(value) when is_binary(value) and byte_size(value) == 64 do
    case Base.decode16(value, case: :lower) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> :error
    end
  end

  defp decode_hash(_), do: :error

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..64,
    do: Enum.all?(:binary.bin_to_list(value), &(&1 in 0x20..0x7E))

  defp identifier?(_), do: false

  defp reject do
    state = %__MODULE__{phase: :failed}
    {:error, Error.new(:native_protocol_error), state}
  end
end
