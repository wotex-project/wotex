defmodule WotexContinuum.EvidenceReference do
  @moduledoc """
  Immutable reference to evidence held outside this library.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Validation}

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

  @impl true
  def kind, do: @kind

  @impl true
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    fields = [:evidence_id, :uri, :digest, :media_type, :captured_at, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, evidence_id} <- Validation.required(data, :evidence_id),
         {:ok, evidence_id} <- Validation.string(evidence_id, ["evidence_id"]),
         {:ok, uri} <- Validation.required(data, :uri),
         {:ok, uri} <- Validation.iri(uri, ["uri"]),
         {:ok, digest} <- Validation.required(data, :digest),
         {:ok, digest} <- Validation.digest(digest, ["digest"]),
         {:ok, media_type} <- Validation.required(data, :media_type),
         {:ok, media_type} <- Validation.string(media_type, ["media_type"], max: 512),
         {:ok, captured_at} <- Validation.required(data, :captured_at),
         {:ok, captured_at} <- Validation.timestamp(captured_at, ["captured_at"]),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
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

  @impl true
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
