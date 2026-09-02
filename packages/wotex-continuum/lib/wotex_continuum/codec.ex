defmodule WotexContinuum.Codec do
  @moduledoc """
  Bounded JSON codec for registered continuum values.

  Decoding copies strings out of the input binary and rejects duplicate object
  members before constructing a typed value.
  """

  alias WotexContinuum.{CanonicalJSON, Error, Limits}

  @doc "Encodes a registered value as JSON."
  @spec encode(struct(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, options \\ []) do
    canonical? = Keyword.get(options, :canonical, false)

    with {:ok, map} <- WotexContinuum.to_map(value) do
      if canonical?, do: CanonicalJSON.encode(map), else: encode_json(map)
    end
  end

  @doc "Decodes bounded JSON into a registered value."
  @spec decode(iodata(), keyword() | map() | Limits.t()) ::
          {:ok, struct()} | {:error, Error.t()}
  def decode(source, limit_options \\ []) do
    with {:ok, source} <- to_binary(source),
         {:ok, limits} <- Limits.new(limit_options),
         :ok <- Limits.preflight(source, limits),
         {:ok, ordered} <- decode_json(source),
         {:ok, map} <- Limits.normalize_decoded(ordered, limits),
         :ok <- top_level_object(map),
         {:ok, value} <- WotexContinuum.from_map(map) do
      {:ok, value}
    end
  end

  @doc "Encodes a value, decodes it, and returns the canonical re-encoding."
  @spec canonicalize(struct()) :: {:ok, binary()} | {:error, Error.t()}
  def canonicalize(value), do: encode(value, canonical: true)

  defp encode_json(map) do
    case Jason.encode(map) do
      {:ok, encoded} ->
        {:ok, encoded}

      {:error, reason} ->
        Error.error(:encode_error, [], "JSON encoding failed", %{reason: inspect(reason)})
    end
  end

  defp decode_json(source) do
    case Jason.decode(source, objects: :ordered_objects, strings: :copy) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, %Jason.DecodeError{position: position}} ->
        Error.error(:invalid_json, [], "JSON decoding failed", %{position: position})
    end
  end

  defp to_binary(source) do
    {:ok, IO.iodata_to_binary(source)}
  rescue
    ArgumentError -> Error.error(:invalid_type, [], "expected JSON iodata")
  end

  defp top_level_object(value) when is_map(value), do: :ok
  defp top_level_object(_value), do: Error.error(:invalid_type, [], "expected a top-level object")
end
