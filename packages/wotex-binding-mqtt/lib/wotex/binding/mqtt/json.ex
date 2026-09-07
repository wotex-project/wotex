defmodule Wotex.Binding.MQTT.JSON do
  @moduledoc """
  Bounded JSON admission for MQTT Application Messages.

  Encoding and decoding run through `Wotex.JSON`, so an Application Message is
  admitted under explicit byte, nesting, node, string, and collection limits and
  duplicate object members are rejected. The MQTT payload limit supplies
  `:max_bytes`; the remaining limits are the package defaults documented by
  `Wotex.JSON.Limits`. Encoding is the canonical Wotex form with recursively
  sorted object keys.

  A core failure becomes a stable binding error. Only the core failure's atom
  code is retained; payload bytes, member names, and codec terms are never
  copied into an error.
  """

  alias Wotex.Binding.MQTT.Error

  @type json_scalar :: nil | boolean() | number() | String.t()
  @type json_value :: json_scalar() | [json_value()] | %{String.t() => json_value()}

  @limit_codes [:invalid_limit, :invalid_options]

  @doc "Encodes a JSON value canonically when the encoded payload fits the byte limit."
  @spec encode(json_value(), pos_integer()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    case Wotex.JSON.encode(value, max_bytes: max_bytes) do
      {:ok, payload} ->
        ensure_size(payload, max_bytes, :encoded_payload_too_large)

      {:error, %Wotex.Error{} = error} ->
        translate(error, max_bytes, :encoded_payload_too_large, :json_encode_failed)
    end
  end

  def encode(_value, _max_bytes), do: invalid_limit()

  @doc "Decodes a JSON payload under the supplied byte limit and the core structural limits."
  @spec decode(binary(), pos_integer()) :: {:ok, json_value()} | {:error, Error.t()}
  def decode(payload, max_bytes)
      when is_binary(payload) and is_integer(max_bytes) and max_bytes > 0 do
    case Wotex.JSON.decode(payload, max_bytes: max_bytes) do
      {:ok, value} ->
        {:ok, value}

      {:error, %Wotex.Error{} = error} ->
        translate(error, max_bytes, :received_payload_too_large, :json_decode_failed)
    end
  end

  def decode(payload, _max_bytes) when not is_binary(payload),
    do: codec_error(:invalid_json_payload, :protocol, "JSON payload must be a binary")

  def decode(_payload, _max_bytes), do: invalid_limit()

  defp translate(%Wotex.Error{code: :byte_limit_exceeded}, max_bytes, size_code, _codec_code) do
    {:error,
     Error.new(size_code, :codec, :protocol, "JSON payload exceeds the configured byte limit", %{
       max_bytes: max_bytes
     })}
  end

  defp translate(%Wotex.Error{code: code}, _max_bytes, _size_code, _codec_code)
       when code in @limit_codes do
    invalid_limit()
  end

  defp translate(%Wotex.Error{code: code}, _max_bytes, _size_code, codec_code) do
    {:error,
     Error.new(codec_code, :codec, :protocol, "JSON admission rejected the Application Message", %{
       cause: code
     })}
  end

  defp ensure_size(payload, max_bytes, code) do
    if byte_size(payload) <= max_bytes do
      {:ok, payload}
    else
      {:error,
       Error.new(code, :codec, :protocol, "JSON payload exceeds the configured byte limit", %{
         max_bytes: max_bytes
       })}
    end
  end

  defp invalid_limit do
    codec_error(
      :invalid_payload_limit,
      :permanent,
      "payload byte limit must be a positive integer"
    )
  end

  defp codec_error(code, class, message), do: {:error, Error.new(code, :codec, class, message)}
end
