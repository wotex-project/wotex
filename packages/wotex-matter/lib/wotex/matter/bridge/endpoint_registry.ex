defmodule Wotex.Matter.Bridge.EndpointRegistry do
  @moduledoc """
  Pure endpoint identity custody for a consumer-owned Matter bridge.

  A bridge root and aggregator occupy endpoints outside this registry. The
  first bridged endpoint defaults to 3. `allocate/2` binds a stable, opaque
  Thing identity to one endpoint. `remove/2` creates a tombstone; neither a
  different Thing nor a later re-add can reuse that endpoint. The registry
  fails on exhaustion rather than wrapping or silently rebinding.

  `snapshot/1` returns a bounded, credential-free value for an owner to write
  atomically with its native fabric/endpoint store. `restore/1` validates that
  value before any server starts. This module performs no I/O and does not
  provide a Matter server or claim that a snapshot alone preserves fabrics,
  subscriptions or commissioned controller state.
  """

  alias Wotex.Matter.Error

  @enforce_keys [
    :first_endpoint,
    :max_endpoint,
    :next_endpoint,
    :by_thing,
    :by_endpoint,
    :tombstones
  ]
  defstruct [:first_endpoint, :max_endpoint, :next_endpoint, :by_thing, :by_endpoint, :tombstones]

  @type t :: %__MODULE__{
          first_endpoint: 3..65_534,
          max_endpoint: 3..65_534,
          next_endpoint: 3..65_535,
          by_thing: %{binary() => pos_integer()},
          by_endpoint: %{pos_integer() => binary()},
          tombstones: MapSet.t(pos_integer())
        }
  @type snapshot :: %{
          version: 1,
          first_endpoint: pos_integer(),
          max_endpoint: pos_integer(),
          next_endpoint: pos_integer(),
          active: [{binary(), pos_integer()}],
          tombstones: [pos_integer()]
        }

  @doc "Creates an empty registry for endpoints 3 through `max_endpoint` by default."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options \\ [])

  def new(options) when is_list(options) do
    if Keyword.keyword?(options) and Keyword.keys(options) == Enum.uniq(Keyword.keys(options)) and
         Enum.all?(Keyword.keys(options), &(&1 in [:first_endpoint, :max_endpoint])) do
      first = Keyword.get(options, :first_endpoint, 3)
      maximum = Keyword.get(options, :max_endpoint, 65_534)

      if valid_range?(first, maximum) do
        {:ok,
         %__MODULE__{
           first_endpoint: first,
           max_endpoint: maximum,
           next_endpoint: first,
           by_thing: %{},
           by_endpoint: %{},
           tombstones: MapSet.new()
         }}
      else
        invalid(:max_endpoint)
      end
    else
      invalid(:options)
    end
  end

  def new(_), do: invalid(:options)

  @doc "Returns the prior endpoint for a Thing or allocates a never-used ID."
  @spec allocate(t(), binary()) :: {:ok, pos_integer(), t()} | {:error, Error.t()}
  def allocate(%__MODULE__{} = registry, thing_id) when is_binary(thing_id) do
    cond do
      not valid_thing?(thing_id) ->
        invalid(:thing_id)

      Map.has_key?(registry.by_thing, thing_id) ->
        {:ok, Map.fetch!(registry.by_thing, thing_id), registry}

      registry.next_endpoint > registry.max_endpoint ->
        {:error, Error.new(:endpoint_limit, :endpoint)}

      true ->
        endpoint = registry.next_endpoint

        updated = %{
          registry
          | next_endpoint: endpoint + 1,
            by_thing: Map.put(registry.by_thing, thing_id, endpoint),
            by_endpoint: Map.put(registry.by_endpoint, endpoint, thing_id)
        }

        {:ok, endpoint, updated}
    end
  end

  def allocate(_, _), do: invalid(:thing_id)

  @doc "Removes a Thing and permanently tombstones its former endpoint."
  @spec remove(t(), binary()) :: {:ok, t()} | {:error, Error.t()}
  def remove(%__MODULE__{} = registry, thing_id) when is_binary(thing_id) do
    case Map.pop(registry.by_thing, thing_id) do
      {nil, _} ->
        invalid(:thing_id)

      {endpoint, remaining} ->
        {:ok,
         %{
           registry
           | by_thing: remaining,
             by_endpoint: Map.delete(registry.by_endpoint, endpoint),
             tombstones: MapSet.put(registry.tombstones, endpoint)
         }}
    end
  end

  def remove(_, _), do: invalid(:thing_id)

  @doc "Looks up a live endpoint by durable Thing identity."
  @spec endpoint(t(), binary()) :: {:ok, pos_integer()} | {:error, Error.t()}
  def endpoint(%__MODULE__{} = registry, thing_id) when is_binary(thing_id) do
    case Map.fetch(registry.by_thing, thing_id) do
      {:ok, value} -> {:ok, value}
      :error -> invalid(:thing_id)
    end
  end

  def endpoint(_, _), do: invalid(:thing_id)

  @doc "Looks up the live Thing identity at an endpoint."
  @spec thing(t(), pos_integer()) :: {:ok, binary()} | {:error, Error.t()}
  def thing(%__MODULE__{} = registry, endpoint) when is_integer(endpoint) do
    case Map.fetch(registry.by_endpoint, endpoint) do
      {:ok, value} -> {:ok, value}
      :error -> invalid(:endpoint)
    end
  end

  def thing(_, _), do: invalid(:endpoint)

  @doc "Exports a deterministic, credential-free registry value for atomic persistence."
  @spec snapshot(t()) :: snapshot()
  def snapshot(%__MODULE__{} = registry) do
    %{
      version: 1,
      first_endpoint: registry.first_endpoint,
      max_endpoint: registry.max_endpoint,
      next_endpoint: registry.next_endpoint,
      active: Enum.sort(registry.by_thing),
      tombstones:
        registry.tombstones
        |> MapSet.to_list()
        |> Enum.sort()
    }
  end

  @doc "Validates a persisted registry before server activation."
  @spec restore(map()) :: {:ok, t()} | {:error, Error.t()}
  def restore(
        %{
          version: 1,
          first_endpoint: first,
          max_endpoint: maximum,
          next_endpoint: next,
          active: active,
          tombstones: tombstones
        } = snapshot
      ) do
    if map_size(snapshot) == 6 and valid_snapshot?(first, maximum, next, active, tombstones) do
      by_thing = Map.new(active)
      by_endpoint = Map.new(active, fn {thing_id, endpoint} -> {endpoint, thing_id} end)

      {:ok,
       %__MODULE__{
         first_endpoint: first,
         max_endpoint: maximum,
         next_endpoint: next,
         by_thing: by_thing,
         by_endpoint: by_endpoint,
         tombstones: MapSet.new(tombstones)
       }}
    else
      invalid(:snapshot)
    end
  end

  def restore(_), do: invalid(:snapshot)

  defp valid_snapshot?(first, maximum, next, active, tombstones) do
    valid_range?(first, maximum) and is_integer(next) and next in first..(maximum + 1) and
      is_list(active) and length(active) <= maximum - first + 1 and
      Enum.all?(active, &valid_record?(&1, first, next)) and
      is_list(tombstones) and length(tombstones) <= maximum - first + 1 and
      Enum.all?(tombstones, &(is_integer(&1) and &1 >= first and &1 < next)) and
      distinct_history?(active, tombstones)
  end

  defp distinct_history?(active, tombstones) do
    things = Enum.map(active, &elem(&1, 0))
    endpoints = Enum.map(active, &elem(&1, 1)) ++ tombstones

    length(things) == length(Enum.uniq(things)) and
      length(endpoints) == length(Enum.uniq(endpoints))
  end

  defp valid_record?({thing_id, endpoint}, first, next),
    do: valid_thing?(thing_id) and is_integer(endpoint) and endpoint >= first and endpoint < next

  defp valid_record?(_, _, _), do: false

  defp valid_thing?(value), do: is_binary(value) and byte_size(value) in 1..256

  defp valid_range?(first, maximum),
    do:
      is_integer(first) and is_integer(maximum) and first in 3..65_534 and maximum in first..65_534

  defp invalid(field), do: {:error, Error.new(:invalid_endpoint_catalogue, field)}
end
