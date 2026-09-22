defmodule Wotex.Lab.Island.Encoder do
  @moduledoc "Validates browser-visible island props against the Lab's closed descriptors."

  alias Wotex.Lab.Island.{CanonicalJSON, Component}

  @doc "Validates and normalizes props for an admitted Lab island."
  @spec encode(String.t(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def encode(component, props) when is_list(props) do
    if Keyword.keyword?(props), do: encode(component, Map.new(props)), else: invalid(component)
  end

  def encode(component, props)
      when is_binary(component) and is_map(props) and not is_struct(props) do
    with {:ok, descriptor} <- fetch(component),
         {:ok, props} <- normalize_keys(props),
         :ok <- closed_props(props, descriptor["props"]),
         :ok <- required_props(props, descriptor["props"]),
         :ok <- validate_props(props, descriptor["props"]),
         {:ok, _} <- CanonicalJSON.encode(props) do
      {:ok, props}
    end
  end

  def encode(component, _), do: invalid(component)

  defp fetch(component) do
    case Component.fetch(component) do
      {:ok, descriptor} -> {:ok, descriptor}
      :error -> {:error, {:unregistered_island_component, component}}
    end
  end

  defp normalize_keys(props) do
    pairs = Enum.map(props, fn {key, value} -> {to_string(key), value} end)

    if length(pairs) == MapSet.size(MapSet.new(pairs, &elem(&1, 0))),
      do: {:ok, Map.new(pairs)},
      else: {:error, :duplicate_island_prop}
  end

  defp closed_props(props, schemas) do
    case Map.keys(props) -- Map.keys(schemas) do
      [] -> :ok
      _ -> {:error, :unknown_island_prop}
    end
  end

  defp required_props(props, schemas) do
    if Enum.all?(schemas, fn {name, schema} ->
         schema["required"] != true or Map.has_key?(props, name)
       end),
       do: :ok,
       else: {:error, :missing_island_prop}
  end

  defp validate_props(props, schemas) do
    if Enum.all?(props, fn {name, value} -> valid_value?(value, schemas[name]) end),
      do: :ok,
      else: {:error, :invalid_island_prop}
  end

  defp valid_value?(value, %{"type" => "string"} = schema),
    do:
      is_binary(value) and String.valid?(value) and
        byte_size(value) <= (schema["max_bytes"] || 8_192)

  defp valid_value?(value, %{"type" => "item_list"} = schema),
    do: is_list(value) and length(value) <= (schema["max_items"] || 2_000)

  defp valid_value?(_, _), do: false
  defp invalid(component), do: {:error, {:invalid_island_props, component}}
end
