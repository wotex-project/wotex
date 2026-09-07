defmodule Wotex.Binding.MQTT.JSON do
  @moduledoc "Bounded JSON encoding and decoding for MQTT Application Messages."

  alias Wotex.Binding.MQTT.Error

  @type json_scalar :: nil | boolean() | number() | String.t()
  @type json_value :: json_scalar() | [json_value()] | %{String.t() => json_value()}

  @doc "Encodes a JSON value when the encoded payload fits the supplied byte limit."
  @spec encode(json_value(), pos_integer()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    case Jason.encode(value) do
      {:ok, payload} -> ensure_size(payload, max_bytes, :encoded_payload_too_large)
      {:error, _external} -> codec_error(:json_encode_failed, :protocol, "JSON encoding failed")
    end
  end

  def encode(_value, _max_bytes),
    do:
      codec_error(
        :invalid_payload_limit,
        :permanent,
        "payload byte limit must be a positive integer"
      )

  @doc "Decodes a JSON payload after enforcing the supplied byte limit."
  @spec decode(binary(), pos_integer()) :: {:ok, json_value()} | {:error, Error.t()}
  def decode(payload, max_bytes)
      when is_binary(payload) and is_integer(max_bytes) and max_bytes > 0 do
    with {:ok, bounded} <- ensure_size(payload, max_bytes, :received_payload_too_large) do
      case Jason.decode(bounded) do
        {:ok, value} -> {:ok, value}
        {:error, _external} -> codec_error(:json_decode_failed, :protocol, "JSON decoding failed")
      end
    end
  end

  def decode(payload, _max_bytes) when not is_binary(payload),
    do: codec_error(:invalid_json_payload, :protocol, "JSON payload must be a binary")

  def decode(_payload, _max_bytes),
    do:
      codec_error(
        :invalid_payload_limit,
        :permanent,
        "payload byte limit must be a positive integer"
      )

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

  defp codec_error(code, class, message), do: {:error, Error.new(code, :codec, class, message)}
end
