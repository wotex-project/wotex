defmodule Wotex.Conformance.Canonical do
  @moduledoc """
  Deterministic JSON encoding and SHA-256 digests for conformance artifacts.

  Objects are ordered by UTF-8 key bytes and contain only string keys. The
  encoder is a project canonical form; it does not claim RFC 8785 equivalence.
  """

  alias Wotex.Conformance.{Error, Value}

  @digest_prefix "sha256:"

  @doc "Encodes a bounded JSON value using the deterministic project canonical form."
  @spec encode(Value.json_value()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value) do
    with {:ok, validated} <- Value.validate(value) do
      {:ok, validated |> encode_value() |> IO.iodata_to_binary()}
    end
  rescue
    Jason.EncodeError ->
      {:error, Error.new(:encoding_failed, "value could not be encoded as canonical JSON")}
  end

  @doc "Returns the canonical SHA-256 digest for a JSON-compatible value."
  @spec digest(Value.json_value()) :: {:ok, String.t()} | {:error, Error.t()}
  def digest(value) do
    with {:ok, encoded} <- encode(value) do
      {:ok, digest_bytes(encoded)}
    end
  end

  @doc "Hashes encoded bytes and returns a lowercase `sha256:` digest."
  @spec digest_bytes(iodata()) :: String.t()
  def digest_bytes(bytes) do
    @digest_prefix <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))
  end

  @doc "Reports whether a value is a lowercase, prefixed SHA-256 digest."
  @spec valid_digest?(term()) :: boolean()
  def valid_digest?(digest) when is_binary(digest) do
    String.match?(digest, ~r/^sha256:[0-9a-f]{64}$/)
  end

  def valid_digest?(_digest), do: false

  defp encode_value(nil), do: "null"
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"

  defp encode_value(value) when is_integer(value) or is_float(value),
    do: Jason.encode_to_iodata!(value)

  defp encode_value(value) when is_binary(value), do: Jason.encode_to_iodata!(value)

  defp encode_value(value) when is_list(value) do
    ["[", value |> Enum.map(&encode_value/1) |> Enum.intersperse(","), "]"]
  end

  defp encode_value(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _entry} -> key end)
      |> Enum.map(fn {key, entry} -> [Jason.encode_to_iodata!(key), ":", encode_value(entry)] end)
      |> Enum.intersperse(",")

    ["{", entries, "}"]
  end
end
