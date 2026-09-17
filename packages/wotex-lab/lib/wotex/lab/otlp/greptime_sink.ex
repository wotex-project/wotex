defmodule Wotex.Lab.Otlp.GreptimeSink do
  @moduledoc """
  The OTLP/HTTP sink for GreptimeDB's documented signal endpoints.

  `new/1` admits a base URL ending in `/v1/otlp`, an optional database
  identifier admitted by `Wotex.Lab.Metrics.Retention.database/1` and the
  `Wotex.Lab.Metrics.ReqSink` transport keys (`:profile`, `:audience`,
  `:tls_ca_certfile`, `:receive_timeout`, `:connect_timeout`). It returns a
  sink function for `Wotex.Lab.Otlp.Exporter`. Traces go to `<base>/v1/traces`
  with `x-greptime-pipeline-name: greptime_trace_v1`, which GreptimeDB 1.1.4
  requires; logs go to `<base>/v1/logs` without a pipeline header and land in
  the server's default OTLP log table. A selected database adds
  `x-greptime-db-name`, so the database's retention TTL applies to the created
  trace and log tables.

  Every write goes through `ReqSink.write/3` with redirects and retries
  disabled and a 4 KiB response ceiling, so the hosted profile keeps its DNS
  admission, peer pinning and TLS checks. This sink sends no credential; an
  authenticated hosted receiver is not part of this profile. The sink returns
  the status and bounded body for the exporter to classify.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{ReqSink, Retention}

  @transport_keys [:profile, :audience, :tls_ca_certfile, :receive_timeout, :connect_timeout]
  @paths %{traces: "/v1/traces", logs: "/v1/logs"}

  @typedoc "A sink for `Wotex.Lab.Otlp.Exporter`."
  @type sink :: (:traces | :logs, %{body: binary(), headers: [{String.t(), String.t()}]} ->
                   {:ok, %{status: pos_integer(), body: binary()}} | {:error, Error.t()})

  @doc "Admits a GreptimeDB OTLP base URL, optional database and transport keys."
  @spec new(map()) :: {:ok, sink()} | {:error, Error.t()}
  def new(%{url: url} = config) when is_binary(url) do
    database = Map.get(config, :database)
    extra = Map.keys(config) -- [:url, :database | @transport_keys]

    with true <- extra == [],
         true <- byte_size(url) in 1..2_048 and String.ends_with?(url, "/v1/otlp"),
         %URI{query: nil, fragment: nil, userinfo: nil} <- URI.parse(url),
         :ok <- database_ok(database) do
      transport =
        config
        |> Map.take(@transport_keys)
        |> Map.put(:max_response_bytes, 4_096)

      {:ok, fn signal, request -> write(url, database, transport, signal, request) end}
    else
      _ -> invalid()
    end
  end

  def new(_), do: invalid()

  defp write(url, database, transport, signal, %{headers: headers} = request)
       when is_map_key(@paths, signal) do
    added =
      if(signal == :traces, do: [{"x-greptime-pipeline-name", "greptime_trace_v1"}], else: []) ++
        if database, do: [{"x-greptime-db-name", database}], else: []

    case ReqSink.write(
           %{request | headers: added ++ headers},
           nil,
           Map.put(transport, :url, url <> Map.fetch!(@paths, signal))
         ) do
      {:ok, %{status: status, body: body}} -> {:ok, %{status: status, body: body}}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp database_ok(nil), do: :ok

  defp database_ok(database) do
    case Retention.database(database) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp invalid,
    do: {:error, Error.new(:invalid_otlp_sink, :construction, "OTLP sink configuration is invalid")}
end
