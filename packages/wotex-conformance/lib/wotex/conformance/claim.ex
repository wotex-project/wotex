defmodule Wotex.Conformance.Claim do
  @moduledoc """
  One bounded, versioned behavior claim exercised by conformance vectors.

  A claim names the exact standards revision and operation it addresses. It is
  not a package-level conformance declaration.
  """

  alias Wotex.Conformance.{Error, Input, Value}

  @profiles ~w(value codec runtime binding directory simulator live_transport hardware certification production)

  @enforce_keys [:id, :revision, :operation, :evidence_profile, :standard]
  defstruct [:id, :revision, :operation, :evidence_profile, :standard, assertions: [], tags: []]

  @type t :: %__MODULE__{
          id: String.t(),
          revision: String.t(),
          operation: String.t(),
          evidence_profile: String.t(),
          standard: %{String.t() => Value.json_value()},
          assertions: [String.t()],
          tags: [String.t()]
        }

  @doc "Validates external claim data and constructs a versioned claim."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(input) when is_map(input) do
    with :ok <-
           Input.only_keys(
             input,
             ~w(id revision operation evidence_profile standard assertions tags)
           ),
         {:ok, id_input} <- Input.required(input, :id),
         {:ok, id} <- Value.validate_identifier(id_input, "id"),
         {:ok, revision_input} <- Input.required(input, :revision),
         {:ok, revision} <- Value.validate_identifier(revision_input, "revision", max_bytes: 64),
         {:ok, operation_input} <- Input.required(input, :operation),
         {:ok, operation} <- Value.validate_identifier(operation_input, "operation"),
         {:ok, profile_input} <- Input.required(input, :evidence_profile),
         {:ok, profile} <- validate_profile(profile_input),
         {:ok, standard_input} <- Input.required(input, :standard),
         {:ok, standard} <- validate_standard(standard_input),
         {:ok, assertions} <-
           validate_identifiers(Input.optional(input, :assertions, []), "assertions"),
         {:ok, tags} <- validate_identifiers(Input.optional(input, :tags, []), "tags") do
      {:ok,
       %__MODULE__{
         id: id,
         revision: revision,
         operation: operation,
         evidence_profile: profile,
         standard: standard,
         assertions: assertions,
         tags: tags
       }}
    end
  end

  def from_map(_input), do: {:error, Error.new(:invalid_type, :claim, "claim must be an object")}

  @doc "Alias for `from_map/1`, the map-shaped claim constructor."
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(input), do: from_map(input)

  @doc "Serializes a validated claim to its string-keyed interchange form."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = claim) do
    %{
      "id" => claim.id,
      "revision" => claim.revision,
      "operation" => claim.operation,
      "evidence_profile" => claim.evidence_profile,
      "standard" => claim.standard,
      "assertions" => claim.assertions,
      "tags" => claim.tags
    }
  end

  defp validate_profile(value) when value in @profiles, do: {:ok, value}

  defp validate_profile(_value) do
    {:error,
     Error.new(:invalid_value, :claim, "evidence_profile is not supported",
       path: ["evidence_profile"],
       details: %{"supported" => @profiles}
     )}
  end

  defp validate_standard(value) do
    with {:ok, standard} <- Value.string_key_map(value, "standard"),
         :ok <- Input.only_keys(standard, ~w(identifier revision source section)),
         {:ok, identifier} <- required_standard_identifier(standard, "identifier"),
         {:ok, revision} <- required_standard_identifier(standard, "revision"),
         {:ok, source} <- validate_source(Map.get(standard, "source")),
         {:ok, section} <- validate_optional_string(Map.get(standard, "section"), "section") do
      {:ok,
       %{
         "identifier" => identifier,
         "revision" => revision,
         "source" => source,
         "section" => section
       }}
    end
  end

  defp required_standard_identifier(standard, key) do
    case Map.fetch(standard, key) do
      {:ok, value} ->
        Value.validate_identifier(value, key)

      :error ->
        {:error,
         Error.new(:missing_field, :claim, "standard #{key} is required", path: ["standard", key])}
    end
  end

  defp validate_source(source) when is_binary(source) do
    case URI.parse(source) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        {:ok, source}

      _uri ->
        {:error,
         Error.new(:invalid_value, :claim, "standard source must be an absolute HTTPS URI",
           path: ["standard", "source"]
         )}
    end
  end

  defp validate_source(_source) do
    {:error,
     Error.new(:missing_field, :claim, "standard source is required", path: ["standard", "source"])}
  end

  defp validate_optional_string(nil, _field), do: {:ok, nil}

  defp validate_optional_string(value, _field) when is_binary(value) and byte_size(value) <= 255 do
    {:ok, value}
  end

  defp validate_optional_string(_value, field) do
    {:error,
     Error.new(:invalid_value, :claim, "#{field} must be a bounded string",
       path: ["standard", field]
     )}
  end

  defp validate_identifiers(values, field) when is_list(values) and length(values) <= 64 do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, entries} ->
      case Value.validate_identifier(value, field, max_bytes: 128) do
        {:ok, identifier} -> {:cont, {:ok, [identifier | entries]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, entries} -> {:ok, entries |> Enum.uniq() |> Enum.sort()}
      {:error, error} -> {:error, error}
    end)
  end

  defp validate_identifiers(_values, field) do
    {:error, Error.new(:invalid_value, :claim, "#{field} must be a bounded list", path: [field])}
  end
end
