defmodule Wotex.BLE.Procedure do
  @moduledoc """
  Validates shared GATT procedure options and bridge byte envelopes.

  This implementation helper admits a closed, duplicate-free keyword list for
  timeout, value type and byte order. Timeouts range from 1 to 60,000 ms; the
  owning operation supplies the default. Scalar conversion belongs to
  `Wotex.BLE.Value`, while `parameters/1` validates the native address and
  constructs the exact read or write bridge parameters.

  Byte envelopes contain exactly type and canonical Base64 fields. Decoding
  rejects extra fields, noncanonical encodings and values larger than 512
  bytes. These pure helpers perform no process startup or protocol I/O.

  ## Examples

      iex> Wotex.BLE.Procedure.decode_bytes(%{"type" => "bytes", "base64" => "NBI="})
      {:ok, <<52, 18>>}
  """

  alias Wotex.BLE.{Address, Error}

  @codecs ~w(bytes utf8 boolean uint8 int8 uint16 int16 uint32 int32 uint64 int64 float32 float64)a

  @doc false
  @spec options(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def options(options, default) do
    with true <- Keyword.keyword?(options),
         keys = Keyword.keys(options),
         true <- keys -- [:timeout, :value_type, :byte_order] == [],
         true <- length(keys) == length(Enum.uniq(keys)),
         timeout = Keyword.get(options, :timeout, default),
         true <- is_integer(timeout) and timeout in 1..60_000 do
      type = Keyword.get(options, :value_type, :bytes)
      order = Keyword.get(options, :byte_order, :little)

      if type in @codecs and order in [:little, :big],
        do: {:ok, %{timeout: timeout, type: type, codec: [byte_order: order]}},
        else: {:error, Error.new(:invalid_value)}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  @doc false
  @spec parameters(term()) :: {:ok, String.t(), map()} | {:error, Error.t()}
  def parameters(message) do
    with :ok <- Address.validate_message(message),
         {:ok, address} <- Address.new(message) do
      parameters = %{
        "address" => %{
          "service" => address.service,
          "characteristic" => address.characteristic,
          "object_path" => address.object_path,
          "handle" => address.handle,
          "generation" => address.generation
        }
      }

      parameters =
        if message.type == :write,
          do: Map.put(parameters, "value", bytes(message.value)),
          else: parameters

      {:ok, Atom.to_string(message.type), parameters}
    end
  end

  @doc false
  @spec decode_bytes(term()) :: {:ok, binary()} | :invalid
  def decode_bytes(%{"type" => "bytes", "base64" => encoded} = value)
      when map_size(value) == 2 and is_binary(encoded) and byte_size(encoded) <= 684 do
    case Base.decode64(encoded) do
      {:ok, bytes} when byte_size(bytes) <= 512 ->
        if Base.encode64(bytes) == encoded, do: {:ok, bytes}, else: :invalid

      _ ->
        :invalid
    end
  end

  def decode_bytes(_), do: :invalid

  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}
end
