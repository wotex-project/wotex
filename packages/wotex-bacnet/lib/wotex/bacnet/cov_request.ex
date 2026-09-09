defmodule Wotex.BACnet.COVRequest do
  @moduledoc "A finite COV request with explicit device and object identity."

  alias Wotex.BACnet.{Address, Error}

  @fields [
    :type,
    :object_type,
    :instance,
    :property,
    :array_index,
    :device_instance,
    :receiver,
    :confirmed,
    :lifetime,
    :renew,
    :cov_increment,
    :max_queue_length,
    :duplicate_window_ms
  ]
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          type: :cov | :cov_property,
          object_type: 0..1023,
          instance: 0..4_194_302,
          property: 0..4_194_303 | nil,
          array_index: 0..4_294_967_295 | nil,
          device_instance: 0..4_194_302,
          receiver: pid(),
          confirmed: boolean(),
          lifetime: 2..86_400,
          renew: boolean(),
          cov_increment: float() | nil,
          max_queue_length: 1..10_000,
          duplicate_window_ms: 1..60_000
        }

  @doc "Validates before listener registration; device identity is never learned from a report."
  @spec new(term(), pid()) :: {:ok, t()} | {:error, Error.t()}
  def new(request, default_receiver) when is_map(request) and not is_struct(request) do
    with true <- Map.keys(request) -- @fields == [],
         true <- request[:type] in [:cov, :cov_property],
         true <- addressing?(request),
         {:ok, address} <- Address.new(Map.put_new(request, :property, 85)),
         true <- integer?(request[:device_instance], 0, 4_194_302),
         receiver = Map.get(request, :receiver, default_receiver),
         true <- is_pid(receiver),
         confirmed = Map.get(request, :confirmed, true),
         renew = Map.get(request, :renew, true),
         lifetime = Map.get(request, :lifetime, 60),
         queue = Map.get(request, :max_queue_length, 1000),
         duplicate_window = Map.get(request, :duplicate_window_ms, 60_000),
         true <- is_boolean(confirmed) and is_boolean(renew),
         true <- integer?(lifetime, 2, 86_400) and integer?(queue, 1, 10_000),
         true <- integer?(duplicate_window, 1, 60_000),
         {:ok, increment} <- increment(request) do
      {:ok,
       %__MODULE__{
         type: request.type,
         object_type: address.object_type,
         instance: address.instance,
         property: if(request.type == :cov_property, do: address.property),
         array_index: address.array_index,
         device_instance: request.device_instance,
         receiver: receiver,
         confirmed: confirmed,
         lifetime: lifetime,
         renew: renew,
         cov_increment: increment,
         max_queue_length: queue,
         duplicate_window_ms: duplicate_window
       }}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_subscription)}
    end
  end

  def new(_, _), do: {:error, Error.new(:invalid_subscription)}

  @doc "Revalidates public structs without trusting their construction path."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = request) do
    fields = Map.from_struct(request)

    fields =
      if request.type == :cov,
        do: Map.drop(fields, [:property, :array_index, :cov_increment]),
        else: fields

    with true <-
           request.type != :cov or
             (is_nil(request.property) and is_nil(request.array_index) and
                is_nil(request.cov_increment)),
         {:ok, ^request} <- new(fields, request.receiver) do
      :ok
    else
      _ -> {:error, Error.new(:invalid_subscription)}
    end
  end

  def validate(_), do: {:error, Error.new(:invalid_subscription)}

  defp addressing?(%{type: :cov} = request),
    do: not Enum.any?([:property, :array_index, :cov_increment], &Map.has_key?(request, &1))

  defp addressing?(request), do: Map.has_key?(request, :property)
  defp integer?(value, low, high), do: is_integer(value) and value >= low and value <= high

  defp increment(%{cov_increment: value})
       when is_number(value) and value > 0 and value <= 3.402_823_466_385_288_6e38,
       do: real_increment(value / 1)

  defp increment(%{cov_increment: nil}), do: {:ok, nil}
  defp increment(%{cov_increment: _}), do: {:error, Error.new(:invalid_cov_increment)}

  defp increment(_), do: {:ok, nil}

  defp real_increment(value) do
    <<encoded::float-32>> = <<value::float-32>>
    if encoded > 0, do: {:ok, value}, else: {:error, Error.new(:invalid_cov_increment)}
  end
end
