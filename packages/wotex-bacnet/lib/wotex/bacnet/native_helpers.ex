defmodule Wotex.BACnet.NativeHelpers do
  @moduledoc """
  Implements the facade's native read, write, and sequential Property helpers.

  Each operation validates the session and address before invoking a client.
  Writes require an explicit supported value and the exact `:written` reply;
  reads validate the native returned value. A batch contains one through 64
  distinct properties for one object and must return exactly those keys.

  Validation, dispatch, and result admission share one absolute session
  deadline. Batch errors include the failed position and completed count but
  omit partial values. `Wotex.BACnet.Batch` owns sequential progress for the
  first-party client; custom implementations remain responsible for honoring
  the supplied timeout and equivalent result contract.
  """

  alias Wotex.BACnet
  alias Wotex.BACnet.{Address, Batch, Error, NativeCall, Session, Value}

  @doc false
  @spec read_property(term(), term(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_property(session, object, instance, property) do
    with {:ok, deadline} <- deadline(session),
         {:ok, request} <- request(:read_property, object, instance, property),
         {:ok, value} <- BACnet.send_deadline(session, request, deadline),
         :ok <- validate_read(value),
         :ok <- completed(deadline, :none) do
      {:ok, value}
    else
      {:error, %Error{} = error} -> {:error, Error.with_effect(error, :none)}
    end
  end

  @doc false
  @spec write_property(term(), term(), term(), term(), term()) :: :ok | {:error, Error.t()}
  def write_property(session, object, instance, property, value) do
    with {:ok, deadline} <- deadline(session),
         {:ok, request} <- request(:write_property, object, instance, property),
         message = Map.put(request, :value, value),
         {:ok, :written} <- BACnet.send_deadline(session, message, deadline),
         :ok <- completed(deadline, :unknown) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, Error.with_effect(Error.new(:invalid_transport_return), :unknown)}
    end
  end

  @doc false
  @spec read_properties(term(), term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def read_properties(session, object, instance, properties) do
    with {:ok, deadline} <- deadline(session),
         {:ok, requests} <- Batch.new(object, instance, properties),
         {:ok, values} <- call_batch(session, requests, deadline),
         :ok <- validate_result(values, requests),
         :ok <- completed_batch(requests, deadline) do
      {:ok, values}
    else
      {:error, %Error{} = error} -> {:error, Error.with_effect(error, :none)}
    end
  end

  defp validate_read(value) do
    case Value.validate_read(value) do
      :ok -> :ok
      {:error, error} -> {:error, Error.protocol(error)}
    end
  end

  defp validate_result(values, requests) when is_map(values) and map_size(values) <= 64 do
    if Enum.sort(Map.keys(values)) == Enum.sort(Enum.map(requests, & &1.property)) and
         Enum.all?(Map.values(values), &(Value.validate_read(&1) == :ok)),
       do: :ok,
       else: {:error, Error.new(:invalid_transport_return)}
  end

  defp validate_result(_, _), do: {:error, Error.new(:invalid_transport_return)}

  defp request(type, object, instance, property) do
    with {:ok, address} <-
           Address.new(%{object_type: object, instance: instance, property: property}),
         do: {:ok, Map.put(Map.from_struct(address), :type, type)}
  end

  defp deadline(%Session{client: client, timeout: timeout})
       when is_atom(client) and not is_nil(client) and is_integer(timeout) and timeout in 1..60_000,
       do: {:ok, System.monotonic_time(:millisecond) + timeout}

  defp deadline(_), do: {:error, Error.new(:invalid_session)}

  defp completed(deadline, effect) do
    if System.monotonic_time(:millisecond) < deadline,
      do: :ok,
      else: {:error, Error.with_effect(Error.new(:deadline_exceeded), effect)}
  end

  defp call_batch(session, requests, deadline) do
    case NativeCall.invoke(session, :read_properties, requests, deadline) do
      {:not_started, error} -> {:error, Batch.failure(error, 0, hd(requests).property)}
      result -> result
    end
  end

  defp completed_batch(requests, deadline) do
    case completed(deadline, :none) do
      :ok ->
        :ok

      {:error, error} ->
        {:error, Batch.failure(error, length(requests) - 1, List.last(requests).property)}
    end
  end
end
