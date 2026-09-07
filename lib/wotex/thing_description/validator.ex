defmodule Wotex.ThingDescription.Validator do
  @moduledoc false

  alias Wotex.{Error, JSON, SecurityReferences, ThingDescription}

  @context "https://www.w3.org/2022/wot/td/v1.1"
  @legacy_context "https://www.w3.org/2019/wot/td/v1"
  @schema_version "1.1-09-November-2023"
  @schema_sha256 "87481cfafa3847d0c593c047750e090d4365dcc0f1b5daab3a725d63c991a4da"
  @upstream_commit "7c0b968f403ecdb9594bd882cafbacf544c41fc0"

  @external_resource schema_path =
                       Path.expand("../../../priv/w3c/td-json-schema-validation-1.1.json", __DIR__)
  @resolved_schema schema_path
                   |> File.read!()
                   |> Jason.decode!()
                   |> ExJsonSchema.Schema.resolve()

  @doc "Validates a Thing Description with the pinned schema and semantic checks."
  @spec validate(ThingDescription.t(), keyword()) ::
          {:ok, ThingDescription.t()} | {:error, [Error.t()]}
  def validate(%ThingDescription{} = td, _opts) do
    document = ThingDescription.to_map(td)
    errors = schema_errors(document) ++ semantic_errors(document)

    case errors do
      [] -> {:ok, td}
      values -> {:error, values}
    end
  end

  @doc "Returns the pinned standard, upstream source, and schema digest."
  @spec schema_info() :: ThingDescription.schema_info()
  def schema_info do
    %{
      standard: "W3C WoT Thing Description 1.1",
      recommendation_date: "2023-12-05",
      schema_version: @schema_version,
      upstream_tag: "REC1.1",
      upstream_commit: @upstream_commit,
      sha256: @schema_sha256,
      informative: true
    }
  end

  defp schema_errors(document) do
    case ExJsonSchema.Validator.validate(@resolved_schema, document, error_formatter: false) do
      :ok -> []
      {:error, errors} -> Enum.flat_map(errors, &schema_error/1)
    end
  end

  # A missing required member is located at the member's own pointer, one
  # violation per member, so consumers and conformance vectors see "/title"
  # rather than the parent object.
  defp schema_error(%ExJsonSchema.Validator.Error{
         path: path,
         error: %ExJsonSchema.Validator.Error.Required{missing: missing}
       }) do
    Enum.map(missing, fn member ->
      Error.new(
        :schema_violation,
        :schema,
        "Thing Description does not satisfy the pinned TD 1.1 schema",
        JSON.join_pointer(normalize_path(path), member),
        %{assertion: "required", missing: member}
      )
    end)
  end

  defp schema_error(%ExJsonSchema.Validator.Error{path: path, error: raw_error}) do
    [
      Error.new(
        :schema_violation,
        :schema,
        "Thing Description does not satisfy the pinned TD 1.1 schema",
        normalize_path(path),
        %{assertion: inspect(raw_error, limit: 40, printable_limit: 160)}
      )
    ]
  end

  defp semantic_errors(document) do
    []
    |> require_context(Map.get(document, "@context"))
    |> reject_thing_model(Map.get(document, "@type"))
    |> require_non_empty_title(Map.get(document, "title"))
    |> require_defined_security_references(document)
    |> Enum.reverse()
  end

  defp require_defined_security_references(
         errors,
         document
       )
       when is_map(document) do
    Enum.reverse(SecurityReferences.errors(document), errors)
  end

  defp require_context(errors, @context), do: errors
  defp require_context(errors, [@context | _rest]), do: errors
  defp require_context(errors, [@legacy_context, @context | _rest]), do: errors

  defp require_context(errors, _context) do
    [
      Error.new(
        :unsupported_context,
        :semantic,
        "Thing Description context must be the TD 1.1 context, or an array that " <>
          "begins with it, optionally preceded only by the TD 1.0 context",
        "/@context",
        %{required: @context}
      )
      | errors
    ]
  end

  defp reject_thing_model(errors, type) do
    if "tm:ThingModel" in List.wrap(type) do
      [
        Error.new(
          :thing_model_not_accepted,
          :semantic,
          "A Thing Model is not accepted as a Thing Description",
          "/@type"
        )
        | errors
      ]
    else
      errors
    end
  end

  defp require_non_empty_title(errors, title) when is_binary(title) do
    if String.trim(title) == "" do
      [
        Error.new(:empty_title, :semantic, "Thing Description title must be non-empty", "/title")
        | errors
      ]
    else
      errors
    end
  end

  defp require_non_empty_title(errors, _title), do: errors

  defp normalize_path("#"), do: "/"
  defp normalize_path("#" <> pointer), do: pointer
end
