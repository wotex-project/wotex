defmodule Wotex.BACnet.DiscoveryWindow do
  @moduledoc """
  Pure state transitions for one bounded Who-Is collection window.

  The window ends at the earlier of its configured duration and the caller's
  absolute deadline. Admission reserves time for the send to complete. Reaching
  the caller deadline is an error; completing the collection window can return
  an empty list successfully.

  Valid I-Am records are keyed by source and device instance and sorted by that
  pair on success. Identical repeats are harmless, out-of-range or malformed
  reports are ignored, and conflicting records or excess capacity fail the
  entire collection. `Wotex.BACnet.DiscoveryOwner` supplies time and received
  APDUs; this module starts no listener or timer.
  """

  alias Wotex.BACnet.{Device, DiscoveryOptions, Error}

  @doc false
  @spec new(term(), term(), term(), integer(), integer()) :: {:ok, map()} | {:error, Error.t()}
  def new(nil, _, _, _, _), do: {:error, Error.new(:discovery_not_configured)}

  def new(options, low, high, now, deadline) when is_integer(now) and is_integer(deadline) do
    with :ok <- DiscoveryOptions.validate(options),
         {:ok, apdu} <- DiscoveryOptions.request(low, high) do
      state = %{
        apdu: apdu,
        started: now,
        destination: options.destination,
        limit: options.max_devices,
        low: low,
        high: high,
        deadline: deadline,
        expires: min(now + options.timeout_ms, deadline),
        devices: %{},
        ignored: 0,
        outcome: nil
      }

      case admission(state, now) do
        {:ok, _} -> {:ok, state}
        {:error, _} = error -> error
      end
    end
  end

  def new(_, _, _, _, _), do: {:error, Error.new(:invalid_discovery_options)}

  @doc false
  @spec admission(map(), integer()) :: {:ok, integer()} | {:error, Error.t()}
  def admission(state, now) do
    if is_nil(state.outcome) and state.expires - now >= 10,
      do: {:ok, state.expires - 9},
      else: {:error, Error.new(:deadline_exceeded)}
  end

  @doc false
  @spec accept(map(), term(), term(), integer()) :: map()
  def accept(%{outcome: outcome} = state, _, _, _) when outcome != nil, do: state

  def accept(state, _, _, now) when now >= state.expires, do: finish(state, now)

  def accept(state, source, apdu, _) do
    case Device.from_apdu(source, apdu) do
      {:ok, device} -> collect(state, device)
      _ -> ignored(state)
    end
  end

  @doc false
  @spec finish(map(), integer()) :: map()
  def finish(%{outcome: outcome} = state, _) when outcome != nil, do: state

  def finish(state, now) do
    cond do
      now >= state.deadline -> fail(state, :deadline_exceeded)
      now < state.expires -> state
      true -> %{state | outcome: {:ok, sorted(state.devices)}}
    end
  end

  defp fail(state, code), do: %{state | devices: %{}, outcome: {:error, Error.new(code)}}

  defp collect(%{low: low, high: high} = state, %{instance: instance})
       when is_integer(low) and (instance < low or instance > high),
       do: ignored(state)

  defp collect(state, device) do
    key = {device.source, device.instance}

    case state.devices[key] do
      ^device ->
        state

      nil when map_size(state.devices) < state.limit ->
        %{state | devices: Map.put(state.devices, key, device)}

      nil ->
        fail(state, :discovery_limit)

      _ ->
        fail(state, :conflicting_discovery_response)
    end
  end

  defp ignored(state), do: %{state | ignored: min(state.ignored + 1, 4_294_967_295)}

  defp sorted(devices) do
    devices
    |> Map.values()
    |> Enum.sort_by(&{&1.source, &1.instance})
  end
end
