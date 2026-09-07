defmodule Wotex.Conformance.Vector do
  @moduledoc """
  Immutable input and runner-owned expectation for one conformance claim.

  `target_request/3` intentionally omits the expectation and provenance.
  """

  alias Wotex.Conformance.{Canonical, Claim, Error, Expectation, Input, Subject, Value}

  @enforce_keys [:id, :revision, :claim, :input, :expectation, :provenance, :digest]
  defstruct [:id, :revision, :claim, :input, :expectation, :provenance, :digest, tags: []]

  @type t :: %__MODULE__{
          id: String.t(),
          revision: String.t(),
          claim: Claim.t(),
          input: Value.json_value(),
          expectation: Expectation.t(),
          provenance: %{String.t() => Value.json_value()},
          digest: String.t(),
          tags: [String.t()]
        }

  @doc "Validates decoded vector data and derives its canonical digest."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(input) when is_map(input) do
    with :ok <-
           Input.only_keys(
             input,
             ~w(id revision claim input expectation provenance tags digest)
           ),
         {:ok, id_input} <- Input.required(input, :id),
         {:ok, id} <- Value.validate_identifier(id_input, "id"),
         {:ok, revision_input} <- Input.required(input, :revision),
         {:ok, revision} <- Value.validate_identifier(revision_input, "revision", max_bytes: 64),
         {:ok, claim_input} <- Input.required(input, :claim),
         {:ok, claim} <- Claim.from_map(claim_input),
         {:ok, value} <- Input.required(input, :input),
         {:ok, validated_input} <- Value.validate(value),
         {:ok, expectation_input} <- Input.required(input, :expectation),
         {:ok, expectation} <- Expectation.from_map(expectation_input),
         {:ok, provenance_input} <- Input.required(input, :provenance),
         {:ok, provenance} <- validate_provenance(provenance_input),
         {:ok, tags} <- validate_tags(Input.optional(input, :tags, [])),
         vector = %__MODULE__{
           id: id,
           revision: revision,
           claim: claim,
           input: validated_input,
           expectation: expectation,
           provenance: provenance,
           digest: "",
           tags: tags
         },
         {:ok, digest} <- Canonical.digest(to_map(vector, include_digest: false)) do
      {:ok, %{vector | digest: digest}}
    end
  end

  def from_map(_input), do: {:error, Error.new(:invalid_type, :vector, "vector must be an object")}

  @doc "Alias for `from_map/1`, the map-shaped vector constructor."
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(input), do: from_map(input)

  @doc "Serializes a vector, optionally omitting its digest with `include_digest: false`."
  @spec to_map(t(), keyword()) :: map()
  def to_map(%__MODULE__{} = vector, options \\ []) do
    map = %{
      "id" => vector.id,
      "revision" => vector.revision,
      "claim" => Claim.to_map(vector.claim),
      "input" => vector.input,
      "expectation" => Expectation.to_map(vector.expectation),
      "provenance" => vector.provenance,
      "tags" => vector.tags
    }

    if Keyword.get(options, :include_digest, true) do
      Map.put(map, "digest", vector.digest)
    else
      map
    end
  end

  @doc """
  Builds the bounded request given to a target adapter.

  The request deliberately excludes runner-owned expectations and provenance.
  """
  @spec target_request(t(), Subject.t(), map()) :: map()
  def target_request(%__MODULE__{} = vector, %Subject{} = subject, context) when is_map(context) do
    %{
      "protocol" => "wotex.conformance.target",
      "protocol_version" => "1.0",
      "subject" => Subject.to_map(subject),
      "claim" => Claim.to_map(vector.claim),
      "vector" => %{
        "id" => vector.id,
        "revision" => vector.revision,
        "input" => vector.input
      },
      "context" => context
    }
  end

  defp validate_provenance(value) do
    with {:ok, provenance} <- Value.string_key_map(value, "provenance"),
         {:ok, _validated} <-
           Value.validate(provenance, max_depth: 8, max_nodes: 64, max_string_bytes: 2_048),
         {:ok, source} <- required_https_source(provenance),
         {:ok, observed} <- required_observed_date(provenance) do
      {:ok, Map.merge(provenance, %{"source" => source, "observed" => observed})}
    end
  end

  defp required_https_source(provenance) do
    case Map.get(provenance, "source") do
      source when is_binary(source) ->
        case URI.parse(source) do
          %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
            {:ok, source}

          _uri ->
            {:error,
             Error.new(:invalid_value, :vector, "provenance source must be an absolute HTTPS URI",
               path: ["provenance", "source"]
             )}
        end

      _value ->
        {:error,
         Error.new(:missing_field, :vector, "provenance source is required",
           path: ["provenance", "source"]
         )}
    end
  end

  defp required_observed_date(provenance) do
    case Map.get(provenance, "observed") do
      observed when is_binary(observed) ->
        case Date.from_iso8601(observed) do
          {:ok, _date} ->
            {:ok, observed}

          {:error, _reason} ->
            {:error,
             Error.new(:invalid_value, :vector, "provenance observed must be an ISO 8601 date",
               path: ["provenance", "observed"]
             )}
        end

      _value ->
        {:error,
         Error.new(:missing_field, :vector, "provenance observed is required",
           path: ["provenance", "observed"]
         )}
    end
  end

  defp validate_tags(tags) when is_list(tags) and length(tags) <= 32 do
    tags
    |> Enum.reduce_while({:ok, []}, fn tag, {:ok, entries} ->
      case Value.validate_identifier(tag, "tags", max_bytes: 64) do
        {:ok, value} -> {:cont, {:ok, [value | entries]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, entries} -> {:ok, entries |> Enum.uniq() |> Enum.sort()}
      {:error, error} -> {:error, error}
    end)
  end

  defp validate_tags(_tags),
    do: {:error, Error.new(:invalid_value, :vector, "tags must be a bounded list", path: ["tags"])}
end
