defmodule WotexContinuum.Codec do
  @moduledoc """
  Bounded JSON codec for registered continuum values.

  Decoding delegates source admission to `Wotex.JSON.decode/2`, which bounds
  bytes, UTF-8 validity, nesting depth, string size, node count, and collection
  size, copies strings out of the source binary, and rejects duplicate object
  members. Continuum validation then constructs the registered value from the
  decoded map. Core admission failures are returned as
  `WotexContinuum.Error` values with the codes documented in WCT.01.
  """

  alias WotexContinuum.{CanonicalJSON, Error, Limits, Validation}

  @doc "Encodes a registered value as JSON."
  @spec encode(struct(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, options \\ []) do
    with :ok <- Validation.options(options, [:canonical]),
         {:ok, canonical?} <-
           Validation.boolean(Keyword.get(options, :canonical, false), "/canonical"),
         {:ok, map} <- WotexContinuum.to_map(value) do
      if canonical?, do: CanonicalJSON.encode(map), else: encode_json(map)
    end
  end

  @doc "Decodes bounded JSON into a registered value."
  @spec decode(iodata(), keyword() | map() | Limits.t()) ::
          {:ok, struct()} | {:error, Error.t()}
  def decode(source, limit_options \\ []) do
    with {:ok, binary} <- to_binary(source),
         {:ok, limits} <- Limits.new(limit_options),
         {:ok, decoded} <- admit(binary, limits),
         :ok <- top_level_object(decoded) do
      WotexContinuum.from_map(decoded)
    end
  end

  @doc "Encodes a value, decodes it, and returns the canonical re-encoding."
  @spec canonicalize(struct()) :: {:ok, binary()} | {:error, Error.t()}
  def canonicalize(value), do: encode(value, canonical: true)

  defp admit(source, %Limits{} = limits) do
    case Wotex.JSON.decode(source, Limits.to_options(limits)) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, %Wotex.Error{} = error} -> {:error, Error.from_core(error)}
    end
  end

  defp encode_json(map) do
    case Jason.encode(map) do
      {:ok, encoded} ->
        {:ok, encoded}

      {:error, reason} ->
        Error.error(:encode_error, :encode, "/", "JSON encoding failed", %{
          reason: inspect(reason)
        })
    end
  end

  defp to_binary(source) do
    {:ok, IO.iodata_to_binary(source)}
  rescue
    ArgumentError -> Error.error(:invalid_type, :decode, "/", "expected JSON iodata")
  end

  defp top_level_object(value) when is_map(value), do: :ok

  defp top_level_object(_),
    do: Error.error(:invalid_type, :decode, "/", "expected a top-level object")
end
