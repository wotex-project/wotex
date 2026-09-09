defmodule Wotex.BACnet.Batch do
  @moduledoc false

  alias Wotex.BACnet.{Address, Error, Value}

  @doc false
  @spec new(term(), term(), term()) :: {:ok, [map()]} | {:error, Error.t()}
  def new(object_type, instance, properties) when is_list(properties) do
    selected = Enum.take(properties, 65)

    if length(selected) in 1..64,
      do: normalize(selected, object_type, instance, [], %{}),
      else: {:error, Error.new(:invalid_properties)}
  rescue
    _ -> {:error, Error.new(:invalid_properties)}
  end

  def new(_, _, _), do: {:error, Error.new(:invalid_properties)}

  @doc false
  @spec validate(term()) :: {:ok, [map()]} | {:error, Error.t()}
  def validate([%{object_type: object, instance: instance} | _] = requests) do
    selected = Enum.take(requests, 65)

    with true <- length(selected) in 1..64,
         {:ok, normalized} <- new(object, instance, Enum.map(selected, &Map.get(&1, :property))),
         true <- selected === normalized do
      {:ok, normalized}
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_properties)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_properties)}
  end

  def validate(_), do: {:error, Error.new(:invalid_properties)}

  @doc false
  @spec start([map()], integer()) :: map()
  def start(requests, deadline),
    do: %{remaining: requests, deadline: deadline, index: 0, values: %{}}

  @doc false
  @spec current(map(), integer()) :: {:ok, map(), pos_integer()} | {:error, Error.t()}
  def current(%{remaining: [request | _], deadline: deadline} = state, now) do
    if now < deadline,
      do: {:ok, request, deadline - now},
      else: {:error, failure(Error.new(:deadline_exceeded), state.index, request.property)}
  end

  @doc false
  @spec accept(map(), term(), integer()) ::
          {:continue, map()} | {:done, map()} | {:error, Error.t()}
  def accept(%{remaining: [request | tail]} = state, result, now) do
    case finish_read(result, now < state.deadline) do
      {:ok, value} ->
        values = Map.put(state.values, request.property, value)

        if tail == [],
          do: {:done, values},
          else: {:continue, %{state | remaining: tail, index: state.index + 1, values: values}}

      {:error, error} ->
        {:error, failure(error, state.index, request.property)}
    end
  end

  @doc false
  @spec failure(Error.t(), non_neg_integer(), non_neg_integer()) :: Error.t()
  def failure(%Error{} = error, index, property) do
    details = Map.take(error.details, [:class, :code, :reason])

    %{
      error
      | effect: :none,
        details:
          Map.merge(details, %{batch_index: index, property: property, completed_count: index})
    }
  end

  defp normalize([], _, _, requests, _), do: {:ok, Enum.reverse(requests)}

  defp normalize([property | tail], object_type, instance, requests, seen) do
    with {:ok, address} <-
           Address.new(%{object_type: object_type, instance: instance, property: property}),
         false <- Map.has_key?(seen, address.property) do
      request =
        address
        |> Map.from_struct()
        |> Map.put(:type, :read_property)

      normalize(
        tail,
        object_type,
        instance,
        [request | requests],
        Map.put(seen, address.property, true)
      )
    else
      true -> {:error, Error.new(:duplicate_property)}
      {:error, _} = error -> error
    end
  end

  defp finish_read({:ok, value}, true) do
    with :ok <- Value.validate_read(value), do: {:ok, value}
  end

  defp finish_read({:error, %Error{}} = error, _), do: error
  defp finish_read(_, false), do: {:error, Error.new(:deadline_exceeded)}
  defp finish_read(_, _), do: {:error, Error.new(:invalid_transport_return)}
end
