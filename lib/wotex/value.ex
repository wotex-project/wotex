defmodule Wotex.Value do
  @moduledoc false

  alias Wotex.{Error, JSON, ValueSchema}

  @doc "Builds an opaque value after JSON and required-member validation."
  @spec build(
          module(),
          term(),
          [{String.t(), (term() -> boolean()), String.t()}],
          atom(),
          keyword()
        ) ::
          {:ok, struct()} | {:error, Error.t()}
  def build(module, map, requirements, schema_kind, opts)

  def build(module, map, requirements, schema_kind, opts) when is_map(map) do
    with :ok <- JSON.validate(map, opts),
         :ok <- validate_requirements(map, requirements),
         :ok <- ValueSchema.validate(map, schema_kind) do
      {:ok, struct!(module, value: map)}
    end
  end

  def build(_module, _map, _requirements, _schema_kind, _opts) do
    {:error, Error.new(:object_required, :value, "Value must be a JSON object")}
  end

  @doc "Returns the preserved map held by an opaque Wotex value."
  @spec to_map(map()) :: map()
  def to_map(%{value: value}), do: value

  @doc "Builds the Forms of an affordance map in one interaction context."
  @spec forms(map(), atom()) :: {:ok, [Wotex.Form.t()]} | {:error, Error.t()}
  def forms(affordance, context) when is_map(affordance) do
    result =
      affordance
      |> Map.get("forms", [])
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {form_map, index}, {:ok, acc} ->
        case Wotex.Form.new(form_map, for: context) do
          {:ok, form} ->
            {:cont, {:ok, [form | acc]}}

          {:error, %Error{} = error} ->
            path = String.trim_trailing("/forms/#{index}" <> error.path, "/")
            {:halt, {:error, %{error | path: path}}}
        end
      end)

    case result do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_requirements(map, requirements) do
    Enum.reduce_while(requirements, :ok, fn {key, predicate, message}, :ok ->
      value = Map.get(map, key)

      if predicate.(value) do
        {:cont, :ok}
      else
        {:halt, {:error, Error.new(:invalid_member, :value, message, "/" <> key)}}
      end
    end)
  end
end
