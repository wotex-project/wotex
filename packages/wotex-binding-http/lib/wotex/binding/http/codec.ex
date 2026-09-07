defmodule Wotex.Binding.HTTP.Codec do
  @moduledoc """
  Encodes and decodes complete JSON representations under explicit byte limits.

  Decoding delegates to `Wotex.JSON.decode/2`, so the caller's byte limit is
  enforced on the source bytes before materialization and the package's
  structural limits on nesting depth, node count, string size, collection size,
  and duplicate object members apply to every admitted body. The byte limit is
  validated here, so an invalid limit never reaches the core admission limits.

  Size checks happen on encoded bytes. Codec failures are normalized into
  credential-free binding errors rather than exposing JSON-library values.
  """

  alias Wotex.Binding.HTTP.Error

  @structural_limits [
    :collection_limit_exceeded,
    :depth_limit_exceeded,
    :node_limit_exceeded,
    :string_limit_exceeded
  ]

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
  def decode(body, max_bytes) when is_binary(body) and is_integer(max_bytes) and max_bytes > 0 do
    case Wotex.JSON.decode(body, max_bytes: max_bytes) do
      {:ok, value} -> {:ok, value}
      {:error, %Wotex.Error{} = error} -> {:error, decode_error(error, max_bytes)}
    end
  end

  def decode(_, _) do
    {:error, Error.new(:invalid_decode_input, :codec, "JSON body or byte limit is invalid")}
  end

  defp decode_error(%Wotex.Error{code: :byte_limit_exceeded}, max_bytes) do
    Error.new(
      :response_body_too_large,
      :codec,
      "JSON body exceeds byte limit",
      %{max_bytes: max_bytes},
      :protocol
    )
  end

  defp decode_error(%Wotex.Error{code: code}, _) when code in @structural_limits do
    Error.new(
      :json_limit_exceeded,
      :codec,
      "JSON body exceeds a bounded admission limit",
      %{limit: code},
      :protocol
    )
  end

  defp decode_error(_, _) do
    Error.new(:json_decode_failed, :codec, "body is not valid JSON", %{}, :protocol)
  end
end
