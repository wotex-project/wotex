defmodule Wotex.Conformance.Result do
  @moduledoc """
  One runner-classified vector result.

  The reportable value retains expected and actual digests, never the raw
  observation returned by the target.

  `new/3` binds the claim and vector revisions, standards revision, vector
  digest, classified status, bounded code, measured duration, and observation
  digests into one evidence digest. The supported statuses distinguish pass,
  fail, unsupported behavior, work not run, and infrastructure failure; callers
  must not collapse these categories.

  Classification belongs to `Wotex.Conformance.Runner`, not the target adapter.
  An actual value is canonicalized and discarded after its digest is derived.
  `to_map/2` produces the stable report representation and may omit the evidence
  digest only when computing that digest. A result proves only its named vector
  under its recorded evidence coordinates.
  """

  alias Wotex.Conformance.{Canonical, Error, Input, Value, Vector}

  @statuses [:pass, :fail, :unsupported, :not_run, :infrastructure_error]

  @enforce_keys [
    :claim_id,
    :claim_revision,
    :standards_revision,
    :vector_id,
    :vector_revision,
    :vector_digest,
    :status,
    :expected_digest,
    :code,
    :duration_us,
    :evidence_digest
  ]
  defstruct [
    :claim_id,
    :claim_revision,
    :standards_revision,
    :vector_id,
    :vector_revision,
    :vector_digest,
    :status,
    :expected_digest,
    :actual_digest,
    :code,
    :duration_us,
    :evidence_digest
  ]

  @type status :: :pass | :fail | :unsupported | :not_run | :infrastructure_error
  @type t :: %__MODULE__{
          claim_id: String.t(),
          claim_revision: String.t(),
          standards_revision: String.t(),
          vector_id: String.t(),
          vector_revision: String.t(),
          vector_digest: String.t(),
          status: status(),
          expected_digest: String.t(),
          actual_digest: String.t() | nil,
          code: String.t(),
          duration_us: non_neg_integer(),
          evidence_digest: String.t()
        }

  @doc """
  Classifies one vector result and derives its evidence digest.

  Options accept `:actual`, `:code`, and `:duration_us`. Raw observations are
  reduced to a digest before the result becomes reportable.
  """
  @spec new(Vector.t(), status(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(vector, status, options \\ [])

  def new(%Vector{} = vector, status, options) when status in @statuses do
    with :ok <- Input.options(options, [:actual, :code, :duration_us]),
         actual = Keyword.get(options, :actual),
         code = Keyword.get(options, :code, Atom.to_string(status)),
         duration_us = Keyword.get(options, :duration_us, 0),
         {:ok, code} <- Value.validate_identifier(code, "code", max_bytes: 128),
         :ok <- validate_duration(duration_us),
         {:ok, actual_digest} <- digest_actual(actual),
         result = %__MODULE__{
           claim_id: vector.claim.id,
           claim_revision: vector.claim.revision,
           standards_revision: vector.claim.standard["revision"],
           vector_id: vector.id,
           vector_revision: vector.revision,
           vector_digest: vector.digest,
           status: status,
           expected_digest: vector.expectation.digest,
           actual_digest: actual_digest,
           code: code,
           duration_us: duration_us,
           evidence_digest: ""
         },
         {:ok, digest} <- Canonical.digest(to_map(result, include_digest: false)) do
      {:ok, %{result | evidence_digest: digest}}
    end
  end

  def new(%Vector{}, _status, _options) do
    {:error, Error.new(:invalid_result_status, :result, "result status is not supported")}
  end

  @doc "Serializes a result, optionally omitting its evidence digest."
  @spec to_map(t(), keyword()) :: map()
  def to_map(%__MODULE__{} = result, options \\ []) do
    map = %{
      "claim_id" => result.claim_id,
      "claim_revision" => result.claim_revision,
      "standards_revision" => result.standards_revision,
      "vector_id" => result.vector_id,
      "vector_revision" => result.vector_revision,
      "vector_digest" => result.vector_digest,
      "status" => Atom.to_string(result.status),
      "expected_digest" => result.expected_digest,
      "actual_digest" => result.actual_digest,
      "code" => result.code,
      "duration_us" => result.duration_us
    }

    if Keyword.get(options, :include_digest, true) do
      Map.put(map, "evidence_digest", result.evidence_digest)
    else
      map
    end
  end

  defp digest_actual(nil), do: {:ok, nil}
  defp digest_actual(actual), do: Canonical.digest(actual)

  defp validate_duration(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_duration(_value),
    do:
      {:error, Error.new(:invalid_duration, :result, "duration_us must be a non-negative integer")}
end
