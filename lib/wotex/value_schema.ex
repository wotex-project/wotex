defmodule Wotex.ValueSchema do
  @moduledoc false

  alias Wotex.Error

  @external_resource schema_path =
                       Path.expand("../../priv/w3c/td-json-schema-validation-1.1.json", __DIR__)
  @resolved_schema schema_path
                   |> File.read!()
                   |> Jason.decode!()
                   |> ExJsonSchema.Schema.resolve()

  @fragments %{
    action_affordance: "#/definitions/action_element",
    data_schema: "#/definitions/dataSchema",
    event_affordance: "#/definitions/event_element",
    form: "#/definitions/form_element_base",
    property_affordance: "#/definitions/property_element",
    security_scheme: "#/definitions/securityScheme"
  }

  @form_fragments %{
    action: "#/definitions/form_element_action",
    event: "#/definitions/form_element_event",
    generic: "#/definitions/form_element_base",
    property: "#/definitions/form_element_property",
    thing: "#/definitions/form_element_root"
  }

  @doc "Validates a standalone value against one pinned TD 1.1 definition."
  @spec validate(map(), atom()) :: :ok | {:error, Error.t()}
  def validate(value, kind) when is_map(value) and is_map_key(@fragments, kind) do
    validate_fragment(value, Map.fetch!(@fragments, kind))
  end

  @doc "Validates a Form against its common or interaction-specific definition."
  @spec validate_form(map(), atom()) :: :ok | {:error, Error.t()}
  def validate_form(value, context)
      when is_map(value) and is_map_key(@form_fragments, context) do
    validate_fragment(value, Map.fetch!(@form_fragments, context))
  end

  def validate_form(_value, context) do
    {:error,
     Error.new(
       :invalid_form_context,
       :value,
       "Form context must be :generic, :property, :action, :event, or :thing",
       "/",
       %{context: inspect(context, limit: 10, printable_limit: 40)}
     )}
  end

  defp validate_fragment(value, fragment) do
    case ExJsonSchema.Validator.validate_fragment(
           @resolved_schema,
           fragment,
           value,
           error_formatter: false
         ) do
      :ok ->
        :ok

      {:error, errors} when is_list(errors) ->
        error =
          errors
          |> Enum.map(&schema_error/1)
          |> Enum.sort_by(&{&1.path, inspect(&1.details)})
          |> List.first()

        {:error, error}
    end
  end

  defp schema_error(error) do
    raw_path = Map.get(error, :path, "#")
    raw_error = Map.get(error, :error, error)

    Error.new(
      :schema_violation,
      :schema,
      "Value does not satisfy its pinned TD 1.1 definition",
      normalize_path(raw_path),
      %{assertion: inspect(raw_error, limit: 40, printable_limit: 160)}
    )
  end

  defp normalize_path(path) when is_binary(path) do
    case String.trim_leading(path, "#") do
      "" -> "/"
      "/" <> _rest = pointer -> pointer
      other -> "/" <> other
    end
  end

  defp normalize_path(path), do: normalize_path(to_string(path))
end
