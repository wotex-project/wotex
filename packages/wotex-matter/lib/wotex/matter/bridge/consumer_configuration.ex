defmodule Wotex.Matter.Bridge.ConsumerConfiguration do
  @moduledoc false

  alias Wotex.Matter.Bridge.Path, as: BridgePath
  alias Wotex.Matter.Error
  alias Wotex.Runtime.ExposedThing
  alias Wotex.ThingDescription

  @keys [:generation, :receiver, :policy, :clock, :routes]
  @route_keys [:exposed, :operation, :name, :input, :result]
  @operations %{read: :readproperty, write: :writeproperty, invoke: :invokeaction}

  @doc false
  @spec build(term()) :: {:ok, map()} | {:error, Error.t()}
  def build(options) when is_list(options) do
    with true <- Keyword.keyword?(options) and length(options) == length(@keys),
         configuration = Map.new(options),
         true <- Enum.sort(Map.keys(configuration)) == Enum.sort(@keys),
         true <- is_binary(configuration.generation) and byte_size(configuration.generation) == 16,
         true <- is_pid(configuration.receiver),
         true <- is_function(configuration.policy, 2) and is_function(configuration.clock, 0),
         {:ok, routes} <- routes(configuration.routes) do
      {:ok, Map.put(configuration, :routes, routes)}
    else
      _ -> invalid()
    end
  rescue
    _ -> invalid()
  end

  def build(_), do: invalid()

  defp routes(routes) when is_map(routes) and map_size(routes) <= 1024 do
    result =
      Enum.reduce_while(routes, {:ok, %{}, %{}, %{}}, fn {key, route},
                                                         {:ok, configured, things, endpoints} ->
        with {thing, endpoint, cluster, member, operation} <- key,
             true <- is_binary(thing) and byte_size(thing) in 1..256,
             true <- BridgePath.valid?(endpoint, cluster, member, operation),
             true <- Map.get(things, thing, endpoint) == endpoint,
             true <- Map.get(endpoints, endpoint, thing) == thing,
             {:ok, route} <- route(route, operation) do
          things = Map.put(things, thing, endpoint)
          endpoints = Map.put(endpoints, endpoint, thing)

          if map_size(things) <= 16,
            do: {:cont, {:ok, Map.put(configured, key, route), things, endpoints}},
            else: {:halt, :error}
        else
          _ -> {:halt, :error}
        end
      end)

    case result do
      {:ok, configured, _, _} -> {:ok, configured}
      _ -> :error
    end
  end

  defp routes(_), do: :error

  defp route(route, operation) when is_map(route) do
    with true <- Enum.sort(Map.keys(route)) == Enum.sort(@route_keys),
         true <- route.operation == Map.fetch!(@operations, operation),
         true <-
           is_binary(route.name) and byte_size(route.name) in 1..256 and
             String.valid?(route.name),
         true <- is_function(route.input, 2) and is_function(route.result, 2),
         %ExposedThing{td: _, handlers: _} = exposed <- route.exposed,
         {:ok, validated} <- ExposedThing.new(exposed.td, exposed.handlers),
         true <- declared?(validated, route.operation, route.name) do
      {:ok, Map.put(route, :exposed, validated)}
    else
      _ -> :error
    end
  end

  defp route(_, _), do: :error

  defp declared?(exposed, operation, name) do
    container = if operation == :invokeaction, do: "actions", else: "properties"
    document = ThingDescription.to_map(exposed.td)

    is_map(get_in(document, [container, name])) and
      Map.has_key?(exposed.handlers, {operation, name})
  end

  defp invalid, do: {:error, Error.new(:invalid_options)}
end
