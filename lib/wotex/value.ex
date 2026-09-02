defmodule Wotex.Value do
  @moduledoc false

  alias Wotex.{Error, JSON}

  @spec build(module(), term(), [{String.t(), (term() -> boolean()), String.t()}], keyword()) ::
          {:ok, struct()} | {:error, Error.t()}
  def build(module, map, requirements, opts \\ [])

  def build(module, map, requirements, opts) when is_map(map) do
    with :ok <- JSON.validate(map, opts),
         :ok <- validate_requirements(map, requirements) do
      {:ok, struct!(module, value: map)}
    end
  end

  def build(_module, _map, _requirements, _opts) do
    {:error, Error.new(:object_required, :value, "Value must be a JSON object")}
  end

  @spec to_map(%{required(:value) => map()}) :: map()
  def to_map(%{value: value}), do: value

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
