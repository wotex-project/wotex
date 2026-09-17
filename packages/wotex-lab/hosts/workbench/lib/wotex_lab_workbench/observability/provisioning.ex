defmodule WotexLabWorkbench.Observability.Provisioning do
  @moduledoc """
  Operator-invoked retention provisioning for a GreptimeDB receiver.

  `provision/2` is an explicit administrative call, for example from an
  attached `iex` session or `bin/wotex_lab_workbench rpc`, never from boot, a
  browser session or an export worker. It admits the receiver's exact IPv4
  loopback base URL (`http://127.0.0.1:<port>`, without path, query,
  fragment or userinfo) and a `Wotex.Lab.Metrics.Retention` plan, then sends
  only the plan's generated statements to `POST /v1/sql`. Each exchange has a
  five-second connect and receive deadline, no redirect or retry, and reads at
  most 64 KiB of response. The call returns the verified database, TTL and
  effective seconds, or the plan's structured refusal. Local provisioning uses
  the standalone receiver's local administrative access and sends no
  credential.

  `provision_hosted/2` is the same explicit call for an operator-provisioned
  hosted receiver. It admits an exact HTTPS origin (`https://host` or
  `https://host:port`), the plan options and an optional `:tls_ca_certfile`.
  Every statement goes through `Wotex.Lab.Metrics.ReqSink`'s hosted destination
  policy with that origin as audience: the host is re-resolved, private,
  link-local, metadata, multicast and mixed answers are refused, one public
  peer is pinned and TLS verifies the original hostname. The administrative
  Bearer credential is read from `WOTEX_LAB_GREPTIME_ADMIN_TOKEN` for every
  statement and never stored. It must be a 43–128 character URL-safe token
  that differs from the export, query, OTLP and operator listener credentials
  (`WOTEX_LAB_GREPTIME_TOKEN`, `WOTEX_LAB_GREPTIME_QUERY_TOKEN`,
  `WOTEX_LAB_OTLP_TOKEN`, `WOTEX_LAB_METRICS_TOKEN` and
  `WOTEX_LAB_METRICS_QUERY_TOKEN`), so no running exporter or reader holds DDL
  authority. Without an admitted credential the call returns
  `credential_unavailable` before any connection. Responses are cut at 64 KiB,
  so an oversized answer fails decoding and is `retention_unavailable`.

  The exporter and the durable reader select the provisioned database
  separately through their `:database` options. Hosted provisioning is source
  proof for an admitted transport, not evidence that a hosted receiver applied
  or enforces the retention.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{ReqSink, Retention}

  @max_response_bytes 65_536
  @timeout_ms 5_000
  @credential_env "WOTEX_LAB_GREPTIME_ADMIN_TOKEN"
  @other_credentials ~w(WOTEX_LAB_GREPTIME_TOKEN WOTEX_LAB_GREPTIME_QUERY_TOKEN WOTEX_LAB_OTLP_TOKEN
                        WOTEX_LAB_METRICS_TOKEN WOTEX_LAB_METRICS_QUERY_TOKEN)
  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/
  @form [{"content-type", "application/x-www-form-urlencoded"}]

  @doc "Provisions `:database` with the optional `:ttl` (default `7d`) at a loopback receiver."
  @spec provision(term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def provision(url, opts) do
    with {:ok, base} <- base_url(url),
         {:ok, plan} <- Retention.plan(opts) do
      Retention.provision(plan, &execute(base, &1))
    end
  end

  @doc "Provisions `:database` and `:ttl` at a hosted HTTPS origin with the administrative credential."
  @spec provision_hosted(term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def provision_hosted(origin, opts) when is_list(opts) do
    with :ok <- Options.validate(opts, [:database, :ttl, :tls_ca_certfile]),
         true <- origin?(origin) and ca?(Keyword.get(opts, :tls_ca_certfile)),
         {:ok, plan} <- Retention.plan(Keyword.delete(opts, :tls_ca_certfile)),
         {:ok, _} <- lookup_credential() do
      config = %{
        url: origin <> "/v1/sql?db=public",
        profile: :hosted,
        audience: origin,
        tls_ca_certfile: Keyword.get(opts, :tls_ca_certfile),
        receive_timeout: @timeout_ms,
        connect_timeout: @timeout_ms,
        max_response_bytes: @max_response_bytes
      }

      Retention.provision(plan, &execute_hosted(config, &1))
    else
      :error -> credential_unavailable()
      {:error, %Error{code: :invalid_retention}} = error -> error
      _ -> invalid()
    end
  end

  def provision_hosted(_, _), do: invalid()

  @doc false
  @spec lookup_credential() :: {:ok, ReqSink.credential()} | :error
  def lookup_credential do
    with {:ok, token} <- System.fetch_env(@credential_env),
         true <- Regex.match?(@token, token),
         false <- Enum.any?(@other_credentials, &(System.get_env(&1) == token)) do
      {:ok, {:bearer, token}}
    else
      _ -> :error
    end
  end

  defp base_url(url) when is_binary(url) and byte_size(url) in 1..64 do
    with [_, port] <- Regex.run(~r/\Ahttp:\/\/127\.0\.0\.1:([1-9][0-9]{0,4})\/?\z/, url),
         port = String.to_integer(port),
         true <- port <= 65_535 do
      {:ok, "http://127.0.0.1:#{port}"}
    else
      _ -> invalid()
    end
  end

  defp base_url(_), do: invalid()

  defp execute(base, statement) do
    [
      method: :post,
      url: base <> "/v1/sql?db=public",
      form: [sql: statement],
      redirect: false,
      retry: false,
      decode_body: false,
      receive_timeout: @timeout_ms,
      connect_options: [timeout: @timeout_ms],
      into: &collect/2
    ]
    |> Req.request()
    |> decode()
  end

  defp execute_hosted(config, statement) do
    with {:ok, credential} <- lookup_credential(),
         {:ok, %{body: body}} <-
           ReqSink.write(
             %{body: URI.encode_query(sql: statement), headers: @form},
             credential,
             config
           ) do
      decode({:ok, %{body: body}})
    else
      _ -> {:error, :unavailable}
    end
  end

  defp collect({:data, data}, {request, %{body: body} = response}) when is_binary(body) do
    if byte_size(body) + byte_size(data) > @max_response_bytes,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: body <> data}}}
  end

  defp collect({:data, _}, accumulator), do: {:halt, accumulator}

  defp decode({:ok, %{body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, :invalid_response}
    end
  end

  defp decode(_), do: {:error, :unavailable}

  defp origin?(origin) when is_binary(origin) and byte_size(origin) in 1..2_048 do
    case URI.new(origin) do
      {:ok, %URI{scheme: "https", host: host, path: nil, query: nil, fragment: nil, userinfo: nil}} ->
        is_binary(host) and host != ""

      _ ->
        false
    end
  end

  defp origin?(_), do: false

  defp ca?(nil), do: true
  defp ca?(path), do: is_binary(path) and byte_size(path) in 1..2_048

  defp credential_unavailable,
    do:
      {:error,
       Error.new(
         :credential_unavailable,
         :construction,
         "the administrative receiver credential is unavailable"
       )}

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_retention, :construction, "receiver or retention options are invalid")}
end
