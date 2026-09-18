defmodule WotexLabWorkbench.Observability.DurableReader do
  @moduledoc """
  Closed Workbench executor for durable metric reads from a GreptimeDB receiver.

  `configure/2` admits a local receiver's exact IPv4-loopback base URL
  (`http://127.0.0.1:<port>`, without path, query, fragment or userinfo) and an
  optional database identifier admitted by
  `Wotex.Lab.Metrics.Retention.database/1`; without one, reads use `public`.
  `configure_hosted/3` separately admits an operator-provisioned hosted
  receiver: an exact HTTPS origin (`https://host` or `https://host:port`), the
  same optional database and an optional private CA certificate path.
  `executor/1` returns the one-argument executor that a `:durable`
  `Wotex.Lab.Metrics.Gateway` binding runs for each admitted descriptor.

  The executor accepts only the fixed `Wotex.Lab.Metrics.DurableQuery` range
  template and sends its four parameters as a form body to
  `POST /v1/prometheus/api/v1/query_range?db=<database>`. The database comes
  from host configuration alone; GreptimeDB 1.1.4 lets that query parameter
  override any header, and it ignores a `db` form field. Each exchange has a
  one-second connect and two-second receive deadline, no redirect or retry, and
  reads at most one MiB of response. Answers with status 200, 400 or 422 are
  decoded JSON for the template to admit or refuse; other statuses, oversized
  or undecodable bodies and transport failures are errors.

  The local profile sends no credential. The hosted profile sends each
  exchange through `Wotex.Lab.Metrics.ReqSink`'s hosted destination policy: the
  origin is re-resolved, private, link-local, metadata, multicast and mixed
  answers are refused, one public peer is pinned and TLS verifies the original
  hostname. Its Bearer credential is read from `WOTEX_LAB_GREPTIME_QUERY_TOKEN`
  inside each executor call and never enters options or state. It must be a
  43–128 character URL-safe token that differs from the export credentials
  `WOTEX_LAB_GREPTIME_TOKEN` and `WOTEX_LAB_OTLP_TOKEN`, the administrative
  credential `WOTEX_LAB_GREPTIME_ADMIN_TOKEN` and the operator listener
  credentials `WOTEX_LAB_METRICS_TOKEN` and `WOTEX_LAB_METRICS_QUERY_TOKEN`;
  otherwise the store is unavailable.

  GreptimeDB 1.1.4 answers a query against a database that does not exist with
  an empty success. When a selected database yields no series, the executor
  therefore sends the fixed read
  `SELECT schema_name FROM information_schema.schemata WHERE schema_name = '<database>'`
  to `POST /v1/sql?db=public` and reports a missing database as an error, so the
  gateway shows the store as unavailable rather than as having no data.

  `WOTEX_LAB_GREPTIME_QUERY_URL` selects this reader at boot and shares
  `WOTEX_LAB_GREPTIME_DATABASE` with the exporter;
  `WOTEX_LAB_GREPTIME_QUERY_PROFILE=hosted` and the optional
  `WOTEX_LAB_GREPTIME_QUERY_CA_CERTFILE` select the hosted profile. This is
  source proof for an admitted transport, not proof of a running hosted
  receiver or of its retention.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{ReqSink, Retention}

  @keys [:url, :database, :profile, :tls_ca_certfile]
  @path "/v1/prometheus/api/v1/query_range"
  @parameters ["query", "start", "end", "step"]
  @max_response_bytes 1_048_576
  @connect_timeout_ms 1_000
  @receive_timeout_ms 2_000
  @credential_env "WOTEX_LAB_GREPTIME_QUERY_TOKEN"
  @other_credentials ~w(WOTEX_LAB_GREPTIME_TOKEN WOTEX_LAB_OTLP_TOKEN WOTEX_LAB_GREPTIME_ADMIN_TOKEN
                        WOTEX_LAB_METRICS_TOKEN WOTEX_LAB_METRICS_QUERY_TOKEN)
  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/
  @form [{"content-type", "application/x-www-form-urlencoded"}]

  @doc "Admits the local receiver base URL and an optional database."
  @spec configure(term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(url, database) do
    with {:ok, base} <- base_url(url),
         options = [url: base, database: database],
         :ok <- validate(options) do
      {:ok, options}
    end
  end

  @doc "Admits a hosted receiver's exact HTTPS origin, an optional database and an optional CA file."
  @spec configure_hosted(term(), term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure_hosted(origin, database, tls_ca_certfile \\ nil) do
    options = [url: origin, database: database, profile: :hosted, tls_ca_certfile: tls_ca_certfile]
    with :ok <- validate(options), do: {:ok, options}
  end

  @doc "Validates closed reader options without opening a connection."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @keys),
         true <- Keyword.has_key?(opts, :url) and Keyword.has_key?(opts, :database),
         true <- destination?(opts),
         true <- database?(Keyword.fetch!(opts, :database)) do
      :ok
    else
      _ -> invalid()
    end
  end

  def validate(_), do: invalid()

  @doc "The durable gateway executor for validated reader options."
  @spec executor(keyword()) :: (map() -> {:ok, map()} | {:error, atom()})
  def executor(opts) do
    :ok = validate(opts)
    transport = transport(opts)
    database = Keyword.fetch!(opts, :database)
    fn template -> execute(transport, database, template) end
  end

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

  defp transport(opts) do
    case Keyword.get(opts, :profile, :local) do
      :local ->
        {:local, Keyword.fetch!(opts, :url)}

      :hosted ->
        {:hosted, Keyword.fetch!(opts, :url), Keyword.get(opts, :tls_ca_certfile)}
    end
  end

  defp execute(transport, database, %{path: @path, params: params}) when is_list(params) do
    if Enum.map(params, &parameter/1) == @parameters do
      path = @path <> "?" <> URI.encode_query(db: database || "public")

      transport
      |> post(path, params)
      |> verify_database(transport, database)
    else
      {:error, :invalid_template}
    end
  end

  defp execute(_, _, _), do: {:error, :invalid_template}

  defp parameter({name, value}) when is_binary(name) and is_binary(value), do: name
  defp parameter(_), do: nil

  defp verify_database(
         {:ok, %{"status" => "success", "data" => %{"result" => []}}} = answer,
         transport,
         database
       )
       when is_binary(database) do
    statement =
      "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '#{database}'"

    case post(transport, "/v1/sql?db=public", [{"sql", statement}]) do
      {:ok, %{"output" => [%{"records" => %{"rows" => [[^database]]}}]}} -> answer
      {:ok, %{"output" => [%{"records" => %{"rows" => []}}]}} -> {:error, :database_missing}
      _ -> {:error, :unavailable}
    end
  end

  defp verify_database(answer, _, _), do: answer

  defp post({:local, base}, path, form) do
    [
      method: :post,
      url: base <> path,
      form: form,
      redirect: false,
      retry: false,
      decode_body: false,
      receive_timeout: @receive_timeout_ms,
      connect_options: [timeout: @connect_timeout_ms],
      into: &collect/2
    ]
    |> Req.request()
    |> answer()
  end

  defp post({:hosted, origin, tls_ca_certfile}, path, form) do
    config = %{
      url: origin <> path,
      profile: :hosted,
      audience: origin,
      tls_ca_certfile: tls_ca_certfile,
      receive_timeout: @receive_timeout_ms,
      connect_timeout: @connect_timeout_ms,
      max_response_bytes: @max_response_bytes
    }

    with {:ok, credential} <- credential(),
         {:ok, response} <-
           ReqSink.write(%{body: URI.encode_query(form), headers: @form}, credential, config) do
      answer({:ok, response})
    else
      _ -> {:error, :unavailable}
    end
  end

  defp credential do
    case lookup_credential() do
      {:ok, credential} -> {:ok, credential}
      :error -> {:error, :credential_unavailable}
    end
  end

  defp collect({:data, data}, {request, %{body: body} = response}) when is_binary(body) do
    if byte_size(body) + byte_size(data) > @max_response_bytes,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: body <> data}}}
  end

  defp collect({:data, _}, accumulator), do: {:halt, accumulator}

  defp answer({:ok, %{body: :too_large}}), do: {:error, :too_large}

  defp answer({:ok, %{status: status, body: body}})
       when status in [200, 400, 422] and is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, :invalid_response}
    end
  end

  defp answer(_), do: {:error, :unavailable}

  defp destination?(opts) do
    case {Keyword.get(opts, :profile, :local), Keyword.get(opts, :tls_ca_certfile)} do
      {:local, nil} ->
        url = Keyword.fetch!(opts, :url)
        match?({:ok, ^url}, base_url(url))

      {:hosted, ca} when is_nil(ca) or (is_binary(ca) and byte_size(ca) in 1..2_048) ->
        origin?(Keyword.fetch!(opts, :url))

      _ ->
        false
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

  defp origin?(origin) when is_binary(origin) and byte_size(origin) in 1..2_048 do
    case URI.new(origin) do
      {:ok,
       %URI{
         scheme: "https",
         host: host,
         port: port,
         path: nil,
         query: nil,
         fragment: nil,
         userinfo: nil
       }} ->
        is_binary(host) and byte_size(host) > 0 and port in 1..65_535 and
          not String.ends_with?(origin, "/")

      _ ->
        false
    end
  end

  defp origin?(_), do: false

  defp database?(nil), do: true
  defp database?(database), do: match?({:ok, _}, Retention.database(database))

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_durable_reads, :construction, "durable reader configuration is invalid")}
end
