defmodule WotexLabWorkbench.Observability.DurableReader do
  @moduledoc """
  Closed Workbench executor for durable metric reads from a local GreptimeDB
  receiver.

  `configure/2` admits the receiver's exact IPv4-loopback base URL
  (`http://127.0.0.1:<port>`, without path, query, fragment or userinfo) and an
  optional database identifier admitted by
  `Wotex.Lab.Metrics.Retention.database/1`; without one, reads use `public`.
  `executor/1` returns the one-argument executor that a `:durable`
  `Wotex.Lab.Metrics.Gateway` binding runs for each admitted descriptor.

  The executor accepts only the fixed `Wotex.Lab.Metrics.DurableQuery` range
  template and sends its four parameters as a form body to
  `POST /v1/prometheus/api/v1/query_range?db=<database>`. The database comes
  from host configuration alone; GreptimeDB 1.1.4 lets that query parameter
  override any header, and it ignores a `db` form field. Each exchange has a
  one-second connect and two-second receive deadline, no redirect, retry or
  credential, and reads at most one MiB of response. Answers with status 200,
  400 or 422 are decoded JSON for the template to admit or refuse; other
  statuses, oversized or undecodable bodies and transport failures are errors.

  GreptimeDB 1.1.4 answers a query against a database that does not exist with
  an empty success. When a selected database yields no series, the executor
  therefore sends the fixed read
  `SELECT schema_name FROM information_schema.schemata WHERE schema_name = '<database>'`
  to `POST /v1/sql?db=public` and reports a missing database as an error, so the
  gateway shows the store as unavailable rather than as having no data.

  `WOTEX_LAB_GREPTIME_QUERY_URL` selects this reader at boot and shares
  `WOTEX_LAB_GREPTIME_DATABASE` with the exporter. Hosted receivers and query
  credentials are not part of this profile.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.Retention

  @keys [:url, :database]
  @path "/v1/prometheus/api/v1/query_range"
  @parameters ["query", "start", "end", "step"]
  @max_response_bytes 1_048_576
  @connect_timeout_ms 1_000
  @receive_timeout_ms 2_000

  @doc "Admits the local receiver base URL and an optional database."
  @spec configure(term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(url, database) do
    with {:ok, base} <- base_url(url),
         options = [url: base, database: database],
         :ok <- validate(options) do
      {:ok, options}
    end
  end

  @doc "Validates closed reader options without opening a connection."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @keys),
         true <- Keyword.has_key?(opts, :url) and Keyword.has_key?(opts, :database),
         {:ok, url} <- base_url(Keyword.fetch!(opts, :url)),
         true <- url == Keyword.fetch!(opts, :url),
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
    base = Keyword.fetch!(opts, :url)
    database = Keyword.fetch!(opts, :database)
    fn template -> execute(base, database, template) end
  end

  defp execute(base, database, %{path: @path, params: params}) when is_list(params) do
    if Enum.map(params, &parameter/1) == @parameters do
      url = base <> @path <> "?" <> URI.encode_query(db: database || "public")
      url |> post(params) |> answer() |> verify_database(base, database)
    else
      {:error, :invalid_template}
    end
  end

  defp execute(_, _, _), do: {:error, :invalid_template}

  defp parameter({name, value}) when is_binary(name) and is_binary(value), do: name
  defp parameter(_), do: nil

  defp verify_database(
         {:ok, %{"status" => "success", "data" => %{"result" => []}}} = answer,
         base,
         database
       )
       when is_binary(database) do
    statement =
      "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '#{database}'"

    case answer(post(base <> "/v1/sql?db=public", sql: statement)) do
      {:ok, %{"output" => [%{"records" => %{"rows" => [[^database]]}}]}} -> answer
      {:ok, %{"output" => [%{"records" => %{"rows" => []}}]}} -> {:error, :database_missing}
      _ -> {:error, :unavailable}
    end
  end

  defp verify_database(answer, _, _), do: answer

  defp post(url, form) do
    Req.request(
      method: :post,
      url: url,
      form: form,
      redirect: false,
      retry: false,
      decode_body: false,
      receive_timeout: @receive_timeout_ms,
      connect_options: [timeout: @connect_timeout_ms],
      into: &collect/2
    )
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

  defp database?(nil), do: true
  defp database?(database), do: match?({:ok, _}, Retention.database(database))

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_durable_reads, :construction, "durable reader configuration is invalid")}
end
