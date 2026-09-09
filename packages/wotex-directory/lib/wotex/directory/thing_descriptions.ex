defmodule Wotex.Directory.ThingDescriptions do
  @moduledoc """
  Boundary conversions between core Thing Descriptions and Discovery-enriched documents.

  Consumers normally use `Wotex.Directory`; this module is public so custom
  service layers can apply the same normalization rules at their boundaries.

  Incoming values are validated by the core `Wotex.ThingDescription` model.
  The conversion functions separate the Discovery `registration` member from
  the stored document, verify that enriched documents declare the W3C
  Discovery context, and preserve the core library's ownership of Thing
  Description validation.

  The inverse functions add registration information and the Discovery
  context when producing a response representation. Failures are translated
  into `Wotex.Directory.Error` values with JSON Pointer paths where the core
  validator supplies a location. These functions do not read a repository or
  assign registration timestamps.
  """

  alias Wotex.Directory.{Error, Registration}

  @discovery_context "https://www.w3.org/2022/wot/discovery"

  @doc "Validates a Thing Description and separates optional registration metadata."
  @spec normalize_and_extract(term(), keyword(), atom()) ::
          {:ok, Wotex.ThingDescription.t(), Registration.input()} | {:error, Error.t()}
  def normalize_and_extract(thing_description, options, operation) do
    with {:ok, validated} <- validate(thing_description, options, operation),
         map when is_map(map) <- Wotex.ThingDescription.to_map(validated),
         {registration, base_map} <- Map.pop(map, "registration", :absent),
         :ok <- registration_context(map, registration, operation),
         {:ok, base} <- from_map(base_map, options, operation) do
      {:ok, base, registration_input(registration)}
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @doc "Reconstructs a Thing Description and registration map from an enriched document."
  @spec from_enriched_map(map(), keyword(), atom()) ::
          {:ok, Wotex.ThingDescription.t(), map()} | {:error, Error.t()}
  def from_enriched_map(map, options, operation) when is_map(map) do
    with {registration, base_map} when is_map(registration) <-
           Map.pop(map, "registration", %{}),
         :ok <- registration_context(map, registration, operation),
         {:ok, base} <- from_map(base_map, options, operation) do
      {:ok, base, registration}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> invalid(operation, "/registration")
    end
  end

  def from_enriched_map(_, _, operation), do: invalid(operation, "/")

  @doc "Returns the identifier of a validated Thing Description."
  @spec id(Wotex.ThingDescription.t()) :: String.t() | nil
  def id(thing_description), do: Wotex.ThingDescription.id(thing_description)

  @doc "Returns a Thing Description with its identifier replaced and revalidated."
  @spec put_id(Wotex.ThingDescription.t(), String.t(), keyword(), atom()) ::
          {:ok, Wotex.ThingDescription.t()} | {:error, Error.t()}
  def put_id(thing_description, identifier, options, operation) do
    case Wotex.ThingDescription.put_id(thing_description, identifier, options) do
      {:ok, updated} -> {:ok, updated}
      {:error, errors} -> invalid(operation, core_path(errors))
    end
  end

  @doc "Builds the W3C Discovery representation with registration metadata and context."
  @spec enriched_map(Wotex.ThingDescription.t(), Registration.t()) :: map()
  def enriched_map(thing_description, registration) do
    thing_description
    |> Wotex.ThingDescription.to_map()
    |> put_discovery_context()
    |> Map.put("registration", Registration.to_map(registration))
  end

  @doc "Builds and validates the W3C Discovery representation as a Thing Description."
  @spec enriched(Wotex.ThingDescription.t(), Registration.t(), keyword(), atom()) ::
          {:ok, Wotex.ThingDescription.t()} | {:error, Error.t()}
  def enriched(thing_description, registration, options, operation) do
    thing_description
    |> enriched_map(registration)
    |> from_map(options, operation)
  end

  defp validate(%Wotex.ThingDescription{} = thing_description, options, operation) do
    case Wotex.ThingDescription.validate(thing_description, options) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> invalid(operation, core_path(errors))
    end
  end

  defp validate(_, _, operation), do: invalid(operation)

  defp from_map(map, options, operation) do
    case Wotex.ThingDescription.from_map(map, options) do
      {:ok, thing_description} -> {:ok, thing_description}
      {:error, errors} -> invalid(operation, core_path(errors))
    end
  end

  defp registration_input(:absent), do: :absent
  defp registration_input(value), do: {:present, value}

  defp registration_context(_, :absent, _), do: :ok

  defp registration_context(map, _, operation) do
    contexts = Map.get(map, "@context")

    if context_present?(contexts), do: :ok, else: invalid(operation, "/@context")
  end

  defp context_present?(@discovery_context), do: true
  defp context_present?(contexts) when is_list(contexts), do: @discovery_context in contexts
  defp context_present?(_), do: false

  defp put_discovery_context(map) do
    Map.update(map, "@context", [@discovery_context], &append_context/1)
  end

  defp append_context(@discovery_context), do: @discovery_context

  defp append_context(contexts) when is_list(contexts) do
    if @discovery_context in contexts, do: contexts, else: contexts ++ [@discovery_context]
  end

  defp append_context(context), do: [context, @discovery_context]

  defp core_path(%Wotex.Error{path: path}), do: path
  defp core_path(errors) when is_list(errors), do: Enum.find_value(errors, &core_path/1)

  defp invalid(operation, path \\ nil),
    do: {:error, Error.new(:invalid_thing_description, :validation, operation, path: path)}
end
