defmodule Wotex.Lab.Otlp.GreptimeSink do
  @moduledoc """
  The OTLP/HTTP sink for GreptimeDB's documented signal endpoints.

  `new/1` admits a base URL ending in `/v1/otlp`, an optional database
  identifier admitted by `Wotex.Lab.Metrics.Retention.database/1` and the
  `Wotex.Lab.Metrics.ReqSink` transport keys (`:profile`, `:audience`,
  `:tls_ca_certfile`, `:receive_timeout`, `:connect_timeout`) and an optional
  `:credential` function. It returns a sink function for
  `Wotex.Lab.Otlp.Exporter`. Traces go to `<base>/v1/traces`
  with `x-greptime-pipeline-name: greptime_trace_v1`, which GreptimeDB 1.1.4
  requires; logs go to `<base>/v1/logs` without a pipeline header and land in
  the server's default OTLP log table. A selected database adds
  `x-greptime-db-name`, so the database's retention TTL applies to the created
  trace and log tables.

  Every write goes through `ReqSink.write/3` with redirects and retries
  disabled and a 4 KiB response ceiling, so the hosted profile keeps its DNS
  admission, peer pinning and TLS checks. Without `:credential` the sink sends
  no credential. With it, the zero-arity function is called for every write and
  returns `{:ok, credential}` with a `ReqSink.credential()` value or `:error`;
  the credential becomes the `authorization` header of that one exchange and is
  not retained. `:error`, or any other answer, refuses the write as
  `credential_unavailable` before a connection opens. The sink returns the
  status and bounded body for the exporter to classify.
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
    credential = Map.get(config, :credential)
    extra = Map.keys(config) -- [:url, :database, :credential | @transport_keys]

    with true <- extra == [],
         true <- is_nil(credential) or is_function(credential, 0),
         true <- byte_size(url) in 1..2_048 and String.ends_with?(url, "/v1/otlp"),
         %URI{query: nil, fragment: nil, userinfo: nil} <- URI.parse(url),
         :ok <- database_ok(database) do
      transport =
        config
        |> Map.take(@transport_keys)
        |> Map.put(:max_response_bytes, 4_096)

      {:ok,
       fn signal, request -> write({url, database, credential}, transport, signal, request) end}
    else
      _ -> invalid()
    end
  end

  def new(_), do: invalid()

  defp write({url, database, credential}, transport, signal, %{headers: headers} = request)
       when is_map_key(@paths, signal) do
    added =
      if(signal == :traces, do: [{"x-greptime-pipeline-name", "greptime_trace_v1"}], else: []) ++
        if database, do: [{"x-greptime-db-name", database}], else: []

    with {:ok, credential} <- resolve(credential),
         {:ok, %{status: status, body: body}} <-
           ReqSink.write(
             %{request | headers: added ++ headers},
             credential,
             Map.put(transport, :url, url <> Map.fetch!(@paths, signal))
           ) do
      {:ok, %{status: status, body: body}}
    end
  end

  defp resolve(nil), do: {:ok, nil}

  defp resolve(lookup) do
    case lookup.() do
      {:ok, nil} -> credential_unavailable()
      {:ok, credential} -> {:ok, credential}
      _ -> credential_unavailable()
    end
  end

  defp credential_unavailable do
    {:error,
     Error.new(:credential_unavailable, :export, "OTLP credential is unavailable",
       class: :unavailable
     )}
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
