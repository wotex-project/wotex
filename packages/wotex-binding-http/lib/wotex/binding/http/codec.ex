defmodule Wotex.Binding.HTTP.Codec do
  @moduledoc """
  Encodes and decodes complete JSON representations under explicit byte limits.

  Size checks happen on encoded bytes. Codec failures are normalized into
  credential-free binding errors rather than exposing JSON-library values.
  """

  alias Wotex.Binding.HTTP.Error

  @doc "Encodes a Wotex JSON value within the supplied byte limit."
  @spec encode(term(), pos_integer()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    case Wotex.JSON.encode(value) do
      {:ok, encoded} when byte_size(encoded) <= max_bytes ->
        {:ok, encoded}

      {:ok, _} ->
        {:error,
         Error.new(
           :request_body_too_large,
           :codec,
           "encoded JSON request exceeds byte limit",
           %{max_bytes: max_bytes},
           :protocol
         )}

      {:error, _} ->
        {:error,
         Error.new(
           :json_encode_failed,
           :codec,
           "interaction input is not a JSON value",
           %{},
           :protocol
         )}
    end
  end

  def encode(_, _) do
    {:error, Error.new(:invalid_encode_limit, :codec, "JSON byte limit must be positive")}
  end

  @doc "Decodes one complete JSON value within the supplied byte limit."
  @spec decode(binary(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def decode(body, max_bytes)
      when is_binary(body) and is_integer(max_bytes) and max_bytes > 0 and
             byte_size(body) <= max_bytes do
    case Jason.decode(body) do
      {:ok, value} ->
        {:ok, value}

      {:error, _} ->
        {:error, Error.new(:json_decode_failed, :codec, "body is not valid JSON", %{}, :protocol)}
    end
  end

  def decode(body, max_bytes)
      when is_binary(body) and is_integer(max_bytes) and max_bytes > 0 do
    {:error,
     Error.new(
       :response_body_too_large,
       :codec,
       "JSON body exceeds byte limit",
       %{max_bytes: max_bytes},
       :protocol
     )}
  end

  def decode(_, _) do
    {:error, Error.new(:invalid_decode_input, :codec, "JSON body or byte limit is invalid")}
  end
end
