defmodule Wotex.BACnet.NativeDiscovery do
  @moduledoc """
  Facade admission and result validation for explicit native Who-Is calls.

  One session timeout covers range validation, client dispatch, and result
  admission. First-party clients receive the original start time and deadline;
  custom clients use an optional Who-Is callback with the remaining budget.

  Results must be a sorted list of at most 1024 valid `Wotex.BACnet.Device`
  values with unique source-and-instance pairs. Invalid or late results become
  typed errors. This helper neither supplies a broadcast destination nor starts
  ambient discovery; collection belongs to the selected client.
  """

  alias Wotex.BACnet.{Device, DiscoveryOptions, Error, PortCall, Session}

  @doc false
  @spec who_is(term(), term(), term()) :: {:ok, [Device.t()]} | {:error, Error.t()}
  def who_is(%Session{client: client, timeout: timeout} = session, low, high)
      when is_atom(client) and client != nil and is_integer(timeout) and timeout in 1..60_000 do
    started = System.monotonic_time(:millisecond)
    deadline = started + timeout

    with {:ok, _} <- DiscoveryOptions.request(low, high),
         {:ok, devices} <- dispatch(session, low, high, started, deadline),
         true <- valid_result?(devices),
         :ok <- completed(deadline) do
      {:ok, devices}
    else
      {:error, %Error{} = error} -> {:error, Error.with_effect(error, :none)}
      false -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def who_is(_, _, _), do: {:error, Error.new(:invalid_session)}

  defp dispatch(%{client: client, handle: handle}, low, high, started, deadline)
       when client in [Wotex.BACnet.BACstack, Wotex.BACnet.IPv4],
       do: PortCall.invoke(client, :who_is_deadline, [handle, low, high, started, deadline])

  defp dispatch(session, low, high, _, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining >= 10,
      do: PortCall.optional(session.client, :who_is, [session.handle, low, high, remaining]),
      else: {:error, Error.new(:deadline_exceeded)}
  end

  defp valid_result?(devices) when is_list(devices) do
    selected = Enum.take(devices, 1025)

    keys =
      Enum.map(selected, fn device -> {Map.get(device, :source), Map.get(device, :instance)} end)

    length(selected) <= 1024 and keys == Enum.sort(keys) and length(keys) == length(Enum.uniq(keys)) and
      Enum.all?(selected, fn value ->
        case Device.new(value) do
          {:ok, device} -> device === value
          _ -> false
        end
      end)
  rescue
    _ -> false
  end

  defp valid_result?(_), do: false

  defp completed(deadline) do
    if System.monotonic_time(:millisecond) < deadline,
      do: :ok,
      else: {:error, Error.new(:deadline_exceeded)}
  end
end
