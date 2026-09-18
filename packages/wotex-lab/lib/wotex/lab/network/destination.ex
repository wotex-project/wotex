defmodule Wotex.Lab.Network.Destination do
  @moduledoc """
  Resolves and admits one HTTP destination for a local or hosted Lab profile.

  The hosted profile requires HTTPS, an exact configured origin, and a DNS
  result made entirely of globally routable addresses. It then rewrites the
  connection URL to one admitted address while retaining the original host for
  the HTTP authority, SNI and certificate hostname check. This closes the gap
  between checking a URI and connecting to a later, independently resolved
  address.

  The local profile is explicit and permits loopback fixtures. TLS verification
  remains enabled there; a disposable fixture can provide its CA certificate.
  """

  @typedoc "Resolved request target and the Mint connection options that pin it."
  @type admission :: %{
          required(:url) => String.t(),
          required(:origin) => String.t(),
          required(:peer) => :local | :inet.ip_address(),
          required(:connect_options) => keyword()
        }

  @doc "Admits and, for hosted use, resolves and pins an HTTP request URI."
  @spec admit(String.t(), map()) :: {:ok, admission()} | {:error, atom()}
  def admit(uri, config) when is_binary(uri) and is_map(config) do
    with {:ok, parsed} <- parse(uri),
         :ok <- valid_http_uri(parsed) do
      admit_profile(parsed, config)
    end
  end

  def admit(_, _), do: {:error, :destination_not_admitted}

  @doc "Returns whether an IPv4 or IPv6 address is globally routable."
  @spec public_address?(term()) :: boolean()
  def public_address?({_, _, _, _} = address), do: not reserved_ipv4?(address)

  def public_address?({_, _, _, _, _, _, _, _} = address), do: not reserved_ipv6?(address)

  def public_address?(_), do: false

  defp parse(uri) do
    {:ok, URI.parse(uri)}
  rescue
    URI.Error -> {:error, :destination_not_admitted}
  end

  defp valid_http_uri(%URI{scheme: scheme, host: host, userinfo: nil})
       when scheme in ["http", "https"] and is_binary(host) and byte_size(host) > 0,
       do: :ok

  defp valid_http_uri(_), do: {:error, :destination_not_admitted}

  defp admit_profile(uri, %{profile: :local} = config) do
    {:ok,
     %{
       url: URI.to_string(uri),
       origin: origin(uri),
       peer: :local,
       connect_options: connect_options(uri, config)
     }}
  end

  defp admit_profile(%URI{scheme: "https"} = uri, %{profile: :hosted} = config) do
    with :ok <- audience_matches(uri, config.audience),
         {:ok, addresses} <- resolve(uri.host, config.resolver),
         true <- addresses != [] and Enum.all?(addresses, &public_address?/1),
         peer <- hd(Enum.sort(addresses)),
         {:ok, host} <- address_string(peer) do
      pinned = %{uri | host: host}

      {:ok,
       %{
         url: URI.to_string(pinned),
         origin: origin(uri),
         peer: peer,
         connect_options: connect_options(uri, config, uri.host)
       }}
    else
      _ -> {:error, :destination_not_admitted}
    end
  end

  defp admit_profile(_, _), do: {:error, :destination_not_admitted}

  defp audience_matches(uri, audience) when is_binary(audience) do
    case parse(audience) do
      {:ok, parsed} ->
        if origin_uri?(parsed) and origin(parsed) == origin(uri),
          do: :ok,
          else: {:error, :destination_not_admitted}

      {:error, _} ->
        {:error, :destination_not_admitted}
    end
  end

  defp audience_matches(_, _), do: {:error, :destination_not_admitted}

  defp origin_uri?(%URI{path: path, query: nil, fragment: nil, userinfo: nil}),
    do: path in [nil, "", "/"]

  defp resolve(host, resolver) do
    results = [resolver.(host, :inet), resolver.(host, :inet6)]

    addresses =
      results
      |> Enum.flat_map(fn
        {:ok, values} when is_list(values) -> values
        _ -> []
      end)
      |> Enum.filter(&:inet.is_ip_address/1)
      |> Enum.uniq()

    if Enum.any?(results, &match?({:ok, _}, &1)),
      do: {:ok, addresses},
      else: {:error, :destination_not_admitted}
  end

  defp connect_options(uri, config, hostname \\ nil) do
    tls_options = tls_options(uri, config)

    [timeout: config.connect_timeout]
    |> put_if(:hostname, hostname)
    |> put_if(:transport_opts, tls_options)
  end

  defp tls_options(%URI{scheme: "https"}, config) do
    [verify: :verify_peer]
    |> put_if(:cacertfile, config.tls_ca_certfile)
  end

  defp tls_options(_, _), do: nil

  defp put_if(options, _, nil), do: options
  defp put_if(options, key, value), do: Keyword.put(options, key, value)

  defp address_string(address) do
    case :inet.ntoa(address) do
      value when is_list(value) -> {:ok, List.to_string(value)}
      _ -> {:error, :destination_not_admitted}
    end
  end

  defp origin(uri), do: "#{uri.scheme}://#{authority(uri)}"

  defp authority(%URI{scheme: scheme, host: host, port: port}) do
    rendered_host = if String.contains?(host, ":"), do: "[#{host}]", else: host
    default = (scheme == "http" and port in [nil, 80]) or (scheme == "https" and port in [nil, 443])
    if default, do: rendered_host, else: "#{rendered_host}:#{port}"
  end

  defp reserved_ipv4?({first, _, _, _}) when first in [0, 10, 127] or first >= 224, do: true
  defp reserved_ipv4?({100, second, _, _}) when second in 64..127, do: true
  defp reserved_ipv4?({169, 254, _, _}), do: true
  defp reserved_ipv4?({172, second, _, _}) when second in 16..31, do: true
  # 192.0.0.0/16 is refused as a whole. It covers the special-purpose
  # 192.0.0.0/24 and TEST-NET-1 192.0.2.0/24; 192.168.0.0/16 is private.
  defp reserved_ipv4?({192, second, _, _}) when second in [0, 168], do: true
  defp reserved_ipv4?({198, second, _, _}) when second in 18..19, do: true
  defp reserved_ipv4?({198, 51, 100, _}), do: true
  defp reserved_ipv4?({203, 0, 113, _}), do: true
  defp reserved_ipv4?(address), do: not :inet.is_ip_address(address)

  defp reserved_ipv6?({0, 0, 0, 0, 0, 0, 0, tail}) when tail in [0, 1], do: true
  defp reserved_ipv6?({0, 0, 0, 0, 0, 0xFFFF, _, _}), do: true

  # Unique local addresses, fc00::/7.
  defp reserved_ipv6?({first, _, _, _, _, _, _, _}) when Bitwise.bsr(first, 9) == 0b1111110,
    do: true

  # fe00::/8: the IETF-reserved fe00::/9, link-local fe80::/10 and the
  # site-local fec0::/10 that RFC 3879 deprecated.
  defp reserved_ipv6?({first, _, _, _, _, _, _, _}) when Bitwise.bsr(first, 8) == 0xFE,
    do: true

  # Multicast, ff00::/8.
  defp reserved_ipv6?({first, _, _, _, _, _, _, _}) when Bitwise.bsr(first, 8) == 0xFF,
    do: true

  defp reserved_ipv6?({0x2001, 0x0DB8, _, _, _, _, _, _}), do: true
  defp reserved_ipv6?(address), do: not :inet.is_ip_address(address)
end
