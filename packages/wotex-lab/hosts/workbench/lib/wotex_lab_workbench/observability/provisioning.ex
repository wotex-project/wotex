defmodule WotexLabWorkbench.Observability.Provisioning do
  @moduledoc """
  Operator-invoked retention provisioning for a local GreptimeDB receiver.

  `provision/2` is an explicit administrative call, for example from an
  attached `iex` session or `bin/wotex_lab_workbench rpc`, never from boot, a
  browser session or an export worker. It admits the receiver's exact IPv4
  loopback base URL (`http://127.0.0.1:<port>`, without path, query,
  fragment or userinfo) and a `Wotex.Lab.Metrics.Retention` plan, then sends
  only the plan's generated statements to `POST /v1/sql`. Each exchange has a
  five-second connect and receive deadline, no redirect or retry, and reads at
  most 64 KiB of response. The call returns the verified database, TTL and
  effective seconds, or the plan's structured refusal.

  Provisioning uses the standalone receiver's local administrative access; it
  sends no credential and is not a hosted database administration path. The
  exporter selects the provisioned database separately through the durable
  `:database` option.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Retention

  @max_response_bytes 65_536
  @timeout_ms 5_000

  @doc "Provisions `:database` with the optional `:ttl` (default `7d`) at a loopback receiver."
  @spec provision(term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def provision(url, opts) do
    with {:ok, base} <- base_url(url),
         {:ok, plan} <- Retention.plan(opts) do
      Retention.provision(plan, &execute(base, &1))
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

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_retention, :construction, "receiver must be an exact loopback base URL")}
end
