defmodule Wotex.BACnet.IPv4Interface do
  @moduledoc """
  Resolves an explicitly selected IPv4 interface for the owned BACnet transport.

  A concrete address must belong to a local interface with an IPv4 netmask and
  broadcast address. Resolution records those values once at startup; it does
  not choose a default interface or change a route. The explicit `:none` fixture
  mode binds all interfaces and conservatively treats every destination as
  routed. That mode has no inferred network prefix.

  The transport uses the recorded broadcast address for its receive socket and
  outgoing BVLC selection. A consumer must reconnect after interface addressing
  changes; this module does not monitor DHCP or interface configuration.
  """

  import Bitwise, only: [band: 2]

  @type t :: %{ip: :inet.ip4_address(), broadcast: :inet.ip4_address(), mask: tuple() | nil}

  @doc "Resolves only the supplied local address, without selecting another interface."
  @spec resolve(:none | :inet.ip4_address()) :: {:ok, t()} | {:error, :invalid_interface}
  def resolve(:none), do: {:ok, %{ip: {0, 0, 0, 0}, broadcast: {255, 255, 255, 255}, mask: nil}}

  def resolve(ip) when is_tuple(ip) and tuple_size(ip) == 4 do
    case :inet.getifaddrs() do
      {:ok, interfaces} -> select(ip, interfaces)
      _ -> {:error, :invalid_interface}
    end
  end

  def resolve(_), do: {:error, :invalid_interface}

  @doc false
  @spec select(:inet.ip4_address(), [{term(), keyword()}]) ::
          {:ok, t()} | {:error, :invalid_interface}
  def select(ip, interfaces) do
    addresses = Enum.flat_map(interfaces, fn {_, props} -> address_groups(props) end)

    with props when is_list(props) <- Enum.find(addresses, &(Keyword.get(&1, :addr) == ip)),
         mask when is_tuple(mask) and tuple_size(mask) == 4 <- Keyword.get(props, :netmask),
         broadcast when is_tuple(broadcast) and tuple_size(broadcast) == 4 <-
           Keyword.get(props, :broadaddr) do
      {:ok, %{ip: ip, broadcast: broadcast, mask: mask}}
    else
      _ -> {:error, :invalid_interface}
    end
  end

  @doc "Returns whether a destination lies outside the recorded local IPv4 prefix."
  @spec routed?(t(), term()) :: boolean()
  def routed?(%{mask: nil}, _), do: true

  def routed?(%{ip: local, mask: mask}, {destination, _})
      when is_tuple(destination) and tuple_size(destination) == 4 do
    octets = Tuple.to_list(destination)

    if Enum.all?(octets, &(is_integer(&1) and &1 in 0..255)) do
      [Tuple.to_list(local), octets, Tuple.to_list(mask)]
      |> Enum.zip()
      |> Enum.any?(fn {own, peer, mask} -> band(own, mask) != band(peer, mask) end)
    else
      true
    end
  end

  def routed?(_, _), do: true

  defp address_groups(props) do
    props
    |> Enum.reduce([], fn
      {:addr, _} = address, groups -> [[address] | groups]
      pair, [current | tail] -> [[pair | current] | tail]
      _, [] -> []
    end)
    |> Enum.map(&Enum.reverse/1)
  end
end
