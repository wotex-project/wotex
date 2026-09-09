defmodule WotexContinuum.EvidenceReference do
  @moduledoc """
  Immutable identity for evidence stored outside this library.

  An evidence ID, absolute IRI, media type, capture time, and lowercase SHA-256
  digest refer to exact external bytes without importing a storage system.
  Consumers decide retrieval, retention, authorization, and verification
  policy.

  `from_map/1` validates the identifier, absolute Internationalized Resource
  Identifier, media type, normalized capture time, lowercase SHA-256 digest,
  and extension map. `to_map/1` emits the common continuum envelope and retains
  unknown namespaced extension values.

  The digest binds the referenced bytes but does not verify them until a
  consumer retrieves and hashes the resource. The capture time is supplied
  evidence rather than a clock observation made by this library. Constructing
  the value performs no network or filesystem I/O and confers no permission to
  access the referenced location.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, Validation}

  @kind "evidence_reference"

  @enforce_keys [:evidence_id, :uri, :digest, :media_type, :captured_at]
  defstruct [:evidence_id, :uri, :digest, :media_type, :captured_at, extensions: %{}]

  @type t :: %__MODULE__{
          evidence_id: String.t(),
          uri: String.t(),
          digest: String.t(),
          media_type: String.t(),
          captured_at: String.t(),
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def from_map(%__MODULE__{} = value), do: from_map(Map.from_struct(value))

  def from_map(data) do
    fields = [:evidence_id, :uri, :digest, :media_type, :captured_at, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, evidence_id} <- Validation.required(data, :evidence_id),
         {:ok, evidence_id} <- Validation.string(evidence_id, "/evidence_id"),
         {:ok, uri} <- Validation.required(data, :uri),
         {:ok, uri} <- Validation.iri(uri, "/uri"),
         {:ok, digest} <- Validation.required(data, :digest),
         {:ok, digest} <- Validation.digest(digest, "/digest"),
         {:ok, media_type} <- Validation.required(data, :media_type),
         {:ok, media_type} <- Validation.string(media_type, "/media_type", max: 512),
         {:ok, captured_at} <- Validation.required(data, :captured_at),
         {:ok, captured_at} <- Validation.timestamp(captured_at, "/captured_at"),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), "/extensions") do
      {:ok,
       %__MODULE__{
         evidence_id: evidence_id,
         uri: uri,
         digest: digest,
         media_type: media_type,
         captured_at: captured_at,
         extensions: extensions
       }}
    end
  end

  @doc "Alias of `from_map/1` retained for the 0.1 constructor API."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(data), do: from_map(data)

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("evidence_id", value.evidence_id)
    |> Map.put("uri", value.uri)
    |> Map.put("digest", value.digest)
    |> Map.put("media_type", value.media_type)
    |> Map.put("captured_at", value.captured_at)
    |> Map.put("extensions", value.extensions)
  end
end
