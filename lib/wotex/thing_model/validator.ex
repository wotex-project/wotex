defmodule Wotex.ThingModel.Validator do
  @moduledoc false

  alias Wotex.{Error, SecurityReferences, ThingModel}

  @context "https://www.w3.org/2022/wot/td/v1.1"
  @schema_version "1.1-09-November-2023"
  @upstream_sha256 "d4fecbf6e9713a7c98c85ef8065800b85f72dd690be5016511c72406ed7314f2"
  @bundled_sha256 "3c8dedb2a534d089fdbd7fda8eb05a5b13237a2331f42e2af08cdb4a7af9fc7a"
  @upstream_commit "7c0b968f403ecdb9594bd882cafbacf544c41fc0"

  @external_resource schema_path =
                       Path.expand("../../../priv/w3c/tm-json-schema-validation-1.1.json", __DIR__)
  @resolved_schema schema_path
                   |> File.read!()
                   |> Jason.decode!()
                   |> ExJsonSchema.Schema.resolve()

  @doc "Validates a Thing Model with the pinned schema and semantic checks."
  @spec validate(ThingModel.t(), keyword()) :: {:ok, ThingModel.t()} | {:error, [Error.t()]}
  def validate(%ThingModel{} = tm, _opts) do
    document = ThingModel.to_map(tm)

    errors =
      schema_errors(document) ++ context_errors(document) ++ SecurityReferences.errors(document)

    case errors do
      [] -> {:ok, tm}
      values -> {:error, values}
    end
  end

  @doc "Returns the pinned standard, upstream source, and schema digests."
  @spec schema_info() :: ThingModel.schema_info()
  def schema_info do
    %{
      standard: "W3C WoT Thing Description 1.1 Thing Model",
      recommendation_date: "2023-12-05",
      schema_version: @schema_version,
      upstream_tag: "REC1.1",
      upstream_commit: @upstream_commit,
      upstream_sha256: @upstream_sha256,
      bundled_sha256: @bundled_sha256,
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
      "Thing Model does not satisfy the pinned W3C 1.1 schema",
      normalize_path(raw_path),
      %{assertion: inspect(raw_error, limit: 40, printable_limit: 160)}
    )
  end

  defp context_errors(%{"@context" => @context}), do: []

  defp context_errors(%{"@context" => contexts}) when is_list(contexts) do
    if Enum.any?(contexts, &(&1 == @context)), do: [], else: [unsupported_context()]
  end

  defp context_errors(_document), do: [unsupported_context()]

  defp unsupported_context do
    Error.new(
      :unsupported_context,
      :semantic,
      "Thing Model context must be the TD 1.1 context or include it",
      "/@context",
      %{required: @context}
    )
  end

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
