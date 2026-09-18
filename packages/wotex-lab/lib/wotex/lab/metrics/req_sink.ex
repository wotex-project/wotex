defmodule Wotex.Lab.Metrics.ReqSink do
  @moduledoc """
  The remote-write HTTP port implemented with the optional `Req` dependency.

  `write/3` POSTs an encoded request to an admitted destination with the
  reserved remote-write headers, redirects and automatic retries disabled
  (retry policy belongs to the bridge), a bounded receive timeout and a
  response body cut at `:max_response_bytes` (4 KiB) so a server cannot flood
  the exporter. The `:local` profile permits loopback fixtures. The `:hosted`
  profile requires HTTPS, an exact `:audience` origin, globally routable DNS
  answers and a connection pinned to one admitted peer while retaining the
  original hostname for HTTP authority, SNI and certificate verification.
  Hosted use cannot select a shared Finch because that would bypass per-write
  destination pinning. The credential is `nil`, `{:bearer, token}` or
  `{:basic, user, password}`; it becomes the `authorization` header of that
  one exchange and is never stored or echoed. A transport failure is
  classified as `:timeout` or `:unavailable` so the bridge can decide whether
  it is retryable. When `Req` is not present the sink reports
  `:client_unavailable` instead of raising. Configuration keys are
  `:url`, `:profile` (`:local` by default), `:audience`, `:resolver`,
  `:tls_ca_certfile`, `:receive_timeout` (5,000 ms), `:connect_timeout`
  (5,000 ms), `:max_response_bytes` and `:finch`. The result carries the status,
  headers and the response body cut at `:max_response_bytes`; callers treat that
  body as untrusted server text.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Network.Destination

  @max_url_bytes 2_048
  @max_response_ceiling 1_048_576

  @type credential :: nil | {:bearer, String.t()} | {:basic, String.t(), String.t()}
  @type result ::
          {:ok, %{status: pos_integer(), headers: [{String.t(), String.t()}], body: binary()}}
          | {:error, Error.t()}

  @doc "Sends one request body; the result carries the status, headers and bounded body."
  @spec write(%{body: binary(), headers: [{String.t(), String.t()}]}, credential(), map()) ::
          result()
  def write(%{body: body, headers: headers}, credential, config)
      when is_binary(body) and is_list(headers) and is_map(config) do
    with {:ok, config} <- normalize_config(config),
         {:ok, destination} <- destination(config),
         :ok <- validate_headers(headers),
         {:ok, authorized} <- authorize(headers, credential) do
      request(config, destination, authorized, body)
    end
  end

  def write(_, _, _),
    do: {:error, Error.new(:invalid_sink_request, :export, "request needs body and headers")}

  defp normalize_config(config) do
    normalized = %{
      url: Map.get(config, :url),
      profile: Map.get(config, :profile, :local),
      audience: Map.get(config, :audience),
      resolver: Map.get(config, :resolver, &:inet.getaddrs/2),
      tls_ca_certfile: Map.get(config, :tls_ca_certfile),
      receive_timeout: Map.get(config, :receive_timeout, 5_000),
      connect_timeout: Map.get(config, :connect_timeout, 5_000),
      max_response_bytes: Map.get(config, :max_response_bytes, 4_096),
      finch: Map.get(config, :finch)
    }

    if Enum.all?(Map.keys(config), &Map.has_key?(normalized, &1)) and valid_config?(normalized),
      do: {:ok, normalized},
      else: invalid_config()
  rescue
    _ -> invalid_config()
  end

  defp valid_config?(config) do
    Enum.all?([
      is_binary(config.url) and byte_size(config.url) in 1..@max_url_bytes,
      config.profile in [:local, :hosted],
      profile_options?(config),
      is_function(config.resolver, 2),
      is_nil(config.tls_ca_certfile) or is_binary(config.tls_ca_certfile),
      timeout?(config.receive_timeout),
      timeout?(config.connect_timeout),
      is_integer(config.max_response_bytes) and
        config.max_response_bytes in 1..@max_response_ceiling,
      is_nil(config.finch) or is_atom(config.finch),
      config.profile == :local or is_nil(config.finch)
    ])
  end

  defp timeout?(value), do: is_integer(value) and value in 1..60_000

  defp profile_options?(%{profile: :local, audience: nil}), do: true

  defp profile_options?(%{profile: :hosted, audience: audience, finch: nil}),
    do: is_binary(audience) and byte_size(audience) in 1..@max_url_bytes

  defp profile_options?(_), do: false

  defp destination(config) do
    case Destination.admit(config.url, config) do
      {:ok, admitted} ->
        {:ok, admitted}

      {:error, _} ->
        {:error,
         Error.new(:destination_not_admitted, :export, "remote write destination is not admitted")}
    end
  end

  defp invalid_config,
    do: {:error, Error.new(:invalid_sink_config, :export, "sink configuration is invalid")}

  defp validate_headers(headers) when length(headers) <= 32 do
    if Enum.all?(headers, fn
         {name, value} when is_binary(name) and is_binary(value) ->
           byte_size(name) in 1..128 and byte_size(value) <= 8_192 and safe_field?(name) and
             safe_field?(value)

         _ ->
           false
       end),
       do: :ok,
       else: invalid_request()
  end

  defp validate_headers(_), do: invalid_request()

  defp invalid_request,
    do: {:error, Error.new(:invalid_sink_request, :export, "request needs bounded headers")}

  defp authorize(headers, nil), do: {:ok, headers}

  defp authorize(headers, {:bearer, token}) when is_binary(token) do
    if credential_field?(token),
      do: {:ok, [{"authorization", "Bearer " <> token} | headers]},
      else: unsupported_credential()
  end

  defp authorize(headers, {:basic, user, password}) when is_binary(user) and is_binary(password) do
    if credential_field?(user) and credential_field?(password),
      do: {:ok, [{"authorization", "Basic " <> Base.encode64(user <> ":" <> password)} | headers]},
      else: unsupported_credential()
  end

  defp authorize(_, _), do: unsupported_credential()

  defp credential_field?(value),
    do: byte_size(value) in 1..8_192 and safe_field?(value)

  defp safe_field?(value), do: not String.contains?(value, ["\r", "\n"])

  defp unsupported_credential,
    do: {:error, Error.new(:unsupported_credential, :export, "credential shape is unsupported")}

  # Req is optional: the exchange is compiled only when it is present, and a
  # host without it gets `:client_unavailable` once the request is admitted.
  if Code.ensure_loaded?(Req) do
    defp request(config, destination, headers, body) do
      options =
        [
          method: :post,
          url: destination.url,
          headers: headers,
          body: body,
          redirect: false,
          retry: false,
          decode_body: false,
          receive_timeout: config.receive_timeout,
          into: &collect(&1, &2, config.max_response_bytes)
        ] ++ connection(config, destination)

      classify(Req.request(options))
    end

    defp collect({:data, data}, {req, %{body: body} = resp}, limit) when is_binary(body) do
      if byte_size(body) + byte_size(data) > limit,
        do: {:halt, {req, %{resp | body: binary_part(body, 0, byte_size(body))}}},
        else: {:cont, {req, %{resp | body: body <> data}}}
    end

    defp collect({:data, _}, acc, _), do: {:halt, acc}

    defp classify({:ok, %{status: status, headers: headers} = response}) do
      flattened =
        Enum.flat_map(headers, fn {name, values} -> Enum.map(List.wrap(values), &{name, &1}) end)

      body = if is_binary(response.body), do: response.body, else: ""
      {:ok, %{status: status, headers: flattened, body: body}}
    end

    defp classify({:error, %{reason: :timeout}}),
      do: {:error, Error.new(:timeout, :export, "remote write timed out", class: :timeout)}

    defp classify({:error, _}),
      do:
        {:error, Error.new(:transport_failed, :export, "remote write failed", class: :unavailable)}

    defp connection(%{finch: name}, _) when is_atom(name) and not is_nil(name),
      do: [finch: [name: name]]

    defp connection(_, destination), do: [connect_options: destination.connect_options]
  else
    defp request(_, _, _, _),
      do: {:error, Error.new(:client_unavailable, :export, "Req is not available")}
  end
end
