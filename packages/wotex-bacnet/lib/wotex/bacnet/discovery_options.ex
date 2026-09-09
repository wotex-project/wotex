defmodule Wotex.BACnet.DiscoveryOptions do
  @moduledoc false

  alias BACnet.Protocol.Services.WhoIs
  alias Wotex.BACnet.{Device, Error}

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(nil), do: :ok

  def validate(%{destination: destination, timeout_ms: timeout, max_devices: maximum} = options)
      when map_size(options) == 3 do
    if destination?(destination) and is_integer(timeout) and timeout in 10..60_000 and
         is_integer(maximum) and maximum in 1..1024,
       do: :ok,
       else: {:error, Error.new(:invalid_discovery_options)}
  end

  def validate(_), do: {:error, Error.new(:invalid_discovery_options)}

  @doc false
  @spec request(term(), term()) ::
          {:ok, BACnet.Protocol.APDU.UnconfirmedServiceRequest.t()} | {:error, Error.t()}
  def request(nil, nil),
    do: WhoIs.to_apdu(%WhoIs{device_id_low_limit: nil, device_id_high_limit: nil}, [])

  def request(low, high)
      when is_integer(low) and is_integer(high) and low in 0..4_194_302 and
             high in 0..4_194_302 and low <= high,
      do: WhoIs.to_apdu(%WhoIs{device_id_low_limit: low, device_id_high_limit: high}, [])

  def request(_, _), do: {:error, Error.new(:invalid_discovery_range)}

  defp destination?({{255, 255, 255, 255}, _} = destination), do: Device.valid_source?(destination)

  defp destination?({{first, _, _, _}, _} = destination),
    do: Device.valid_source?(destination) and first in 1..223

  defp destination?(_), do: false
end
