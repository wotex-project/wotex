defmodule Wotex.ThingDescription.Validator do
  @moduledoc false

  alias Wotex.{Error, ThingDescription}

  @context "https://www.w3.org/2022/wot/td/v1.1"
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
    case ExJsonSchema.Validator.validate(@resolved_schema, document) do
      :ok -> []
      {:error, errors} -> Enum.map(errors, &schema_error/1)
    end
  end

  defp schema_error(error) do
    raw_path = map_value(error, :path, "#")
    raw_error = map_value(error, :error, error)

    Error.new(
      :schema_violation,
      :schema,
      "Thing Description does not satisfy the pinned TD 1.1 schema",
      normalize_path(raw_path),
      %{assertion: inspect(raw_error, limit: 40, printable_limit: 160)}
    )
  end

  defp semantic_errors(document) do
    []
    |> require_context(Map.get(document, "@context"))
    |> require_non_empty_title(Map.get(document, "title"))
    |> require_defined_security_references(document)
    |> Enum.reverse()
  end

  defp require_defined_security_references(
         errors,
         %{"securityDefinitions" => definitions} = document
       )
       when is_map(definitions) do
    document
    |> security_references(definitions)
    |> Enum.reduce(errors, &accumulate_security_reference(&1, &2, definitions))
  end

  defp require_defined_security_references(errors, _document), do: errors

  defp accumulate_security_reference({_path, reference}, errors, definitions)
       when is_map_key(definitions, reference),
       do: errors

  defp accumulate_security_reference({path, reference}, errors, _definitions) do
    [
      Error.new(
        :undefined_security_reference,
        :semantic,
        "Security reference must name an entry in securityDefinitions",
        path,
        %{reference: reference}
      )
      | errors
    ]
  end

  defp security_references(document, definitions) do
    security_values(Map.get(document, "security"), "/security") ++
      form_security_references(Map.get(document, "forms"), "/forms") ++
      affordance_security_references(document) ++ combo_security_references(definitions)
  end

  defp affordance_security_references(document) do
    Enum.flat_map(~w(properties actions events), fn category ->
      document
      |> Map.get(category, %{})
      |> sorted_map_entries()
      |> Enum.flat_map(fn {name, affordance} ->
        path = "/#{category}/#{pointer_segment(name)}/forms"
        form_security_references(map_value(affordance, "forms", nil), path)
      end)
    end)
  end

  defp form_security_references(forms, path) when is_list(forms) do
    forms
    |> Enum.with_index()
    |> Enum.flat_map(fn {form, index} ->
      security_values(map_value(form, "security", nil), "#{path}/#{index}/security")
    end)
  end

  defp form_security_references(_forms, _path), do: []

  defp combo_security_references(definitions) do
    definitions
    |> sorted_map_entries()
    |> Enum.flat_map(fn {name, definition} -> combo_references(name, definition) end)
  end

  defp combo_references(name, %{"scheme" => "combo"} = definition) do
    Enum.flat_map(~w(oneOf allOf), fn member ->
      path = "/securityDefinitions/#{pointer_segment(name)}/#{member}"
      security_values(Map.get(definition, member), path)
    end)
  end

  defp combo_references(_name, _definition), do: []

  defp security_values(reference, path) when is_binary(reference), do: [{path, reference}]

  defp security_values(references, path) when is_list(references) do
    references
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {reference, index} when is_binary(reference) -> [{"#{path}/#{index}", reference}]
      {_reference, _index} -> []
    end)
  end

  defp security_values(_references, _path), do: []

  defp sorted_map_entries(value) when is_map(value), do: Enum.sort_by(value, &elem(&1, 0))
  defp sorted_map_entries(_value), do: []

  defp pointer_segment(segment) do
    segment
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end

  defp require_context(errors, @context), do: errors

  defp require_context(errors, contexts) when is_list(contexts) do
    if Enum.any?(contexts, &(&1 == @context)) do
      errors
    else
      [
        Error.new(
          :unsupported_context,
          :semantic,
          "Thing Description context must include the TD 1.1 context",
          "/@context",
          %{required: @context}
        )
        | errors
      ]
    end
  end

  defp require_context(errors, _context) do
    [
      Error.new(
        :unsupported_context,
        :semantic,
        "Thing Description context must be the TD 1.1 context or include it",
        "/@context",
        %{required: @context}
      )
      | errors
    ]
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

  defp map_value(value, key, default) when is_map(value), do: Map.get(value, key, default)
  defp map_value(_value, _key, default), do: default

  defp normalize_path(path) when is_binary(path) do
    trimmed = String.trim_leading(path, "#")

    case trimmed do
      "" -> "/"
      "/" <> _rest = pointer -> pointer
      other -> "/" <> other
    end
  end

  defp normalize_path(path), do: normalize_path(to_string(path))
end
