defmodule Wotex.Zigbee.PeerProbe.Policy do
  @moduledoc false

  @peer_keys [:peer_ieee, :route_address, :source_endpoint, :destination_endpoint]

  @doc false
  @spec valid?(term(), binary()) :: boolean()
  def valid?(peers, coordinator) do
    with {:ok, count} <- count(peers, 0),
         true <- count in 1..32 and Enum.all?(peers, &peer?(&1, coordinator)) do
      Enum.uniq_by(peers, & &1.peer_ieee) == peers and
        Enum.uniq_by(peers, & &1.route_address) == peers
    else
      _ -> false
    end
  end

  defp peer?(peer, coordinator) when is_map(peer) do
    map_size(peer) == 4 and Enum.all?(@peer_keys, &Map.has_key?(peer, &1)) and
      identity?(peer.peer_ieee) and peer.peer_ieee != coordinator and
      in_range?(peer.route_address, 1, 0xFFF7) and
      in_range?(peer.source_endpoint, 1, 240) and in_range?(peer.destination_endpoint, 1, 240)
  end

  defp peer?(_, _), do: false
  defp count([], count), do: {:ok, count}
  defp count([_ | rest], count) when count < 32, do: count(rest, count + 1)
  defp count(_, _), do: :error
  defp identity?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp identity?(_), do: false
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
end
