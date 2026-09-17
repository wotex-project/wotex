defmodule WotexLabWorkbench.Observability.Otlp do
  @moduledoc """
  Closed Workbench activation of the base library's OTLP exporter.

  `configure/2` admits the exact local receiver base URL
  `http://127.0.0.1:<port>/v1/otlp`, without query, fragment or userinfo, and
  an optional database identifier admitted by
  `Wotex.Lab.Metrics.Retention.database/1`. `configure_hosted/4` separately
  admits an authenticated hosted receiver: an exact HTTPS base URL ending in
  `/v1/otlp`, an audience that is exactly that URL's origin, the same optional
  database and an optional private CA certificate path. `child_options/1`
  builds the `Wotex.Lab.Otlp.Exporter` options for the host: service instance
  `workbench`, both signals, a five-second interval and deadline, 512 buffered
  records per signal and 256 records per request, writing through
  `Wotex.Lab.Otlp.GreptimeSink`. The exporter observes the Lab spans of every
  session on this host; its records carry closed vocabularies only.

  The local profile sends no credential. The hosted profile writes through the
  hosted destination policy of `Wotex.Lab.Metrics.ReqSink`, so every export
  re-resolves the receiver, refuses private, link-local, metadata, multicast
  and mixed answers, pins one public peer and verifies the original hostname
  through TLS. Its Bearer credential is read from `WOTEX_LAB_OTLP_TOKEN` for
  every write and never enters options or exporter state. It must be a 43–128
  character URL-safe token that differs from the query credentials
  `WOTEX_LAB_GREPTIME_QUERY_TOKEN`, `WOTEX_LAB_METRICS_TOKEN` and
  `WOTEX_LAB_METRICS_QUERY_TOKEN`; otherwise the batch fails as
  `credential_unavailable`.

  `WOTEX_LAB_OTLP_URL` and optional `WOTEX_LAB_OTLP_DATABASE` select the local
  profile at boot. `WOTEX_LAB_OTLP_PROFILE=hosted` additionally requires
  `WOTEX_LAB_OTLP_AUDIENCE` and the token, and accepts
  `WOTEX_LAB_OTLP_CA_CERTFILE`. Neither profile needs PromEx or history
  activation. Hosted source is not proof of a running receiver or of retained
  records.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{ReqSink, Retention}
  alias Wotex.Lab.Otlp.GreptimeSink

  @keys [:url, :database, :profile, :audience, :tls_ca_certfile]
  @credential_env "WOTEX_LAB_OTLP_TOKEN"
  @query_credentials ~w(WOTEX_LAB_GREPTIME_QUERY_TOKEN WOTEX_LAB_METRICS_TOKEN WOTEX_LAB_METRICS_QUERY_TOKEN)
  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/

  @doc "Admits the local receiver base URL and an optional database."
  @spec configure(term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(url, database) do
    options = [url: url, database: database]
    with :ok <- validate(options), do: {:ok, options}
  end

  @doc "Admits an authenticated hosted HTTPS receiver, its exact audience, a database and a CA file."
  @spec configure_hosted(term(), term(), term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure_hosted(url, audience, database, tls_ca_certfile \\ nil) do
    options = [
      url: url,
      database: database,
      profile: :hosted,
      audience: audience,
      tls_ca_certfile: tls_ca_certfile
    ]

    with :ok <- validate(options), do: {:ok, options}
  end

  @doc "Validates closed activation options without opening a connection."
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

  @doc "The exporter options for validated activation options."
  @spec child_options(keyword()) :: keyword()
  def child_options(opts) do
    :ok = validate(opts)

    {:ok, sink} =
      opts
      |> sink_config()
      |> Map.merge(%{
        url: Keyword.fetch!(opts, :url),
        database: Keyword.fetch!(opts, :database),
        receive_timeout: 5_000,
        connect_timeout: 5_000
      })
      |> GreptimeSink.new()

    [
      id: "workbench",
      name: __MODULE__.Exporter,
      sink: sink,
      service_instance: "workbench",
      interval_ms: 5_000,
      max_buffer: 512,
      max_batch: 256,
      deadline_ms: 5_000
    ]
  end

  @doc false
  @spec lookup_credential() :: {:ok, ReqSink.credential()} | :error
  def lookup_credential do
    with {:ok, token} <- System.fetch_env(@credential_env),
         true <- Regex.match?(@token, token),
         false <- Enum.any?(@query_credentials, &(System.get_env(&1) == token)) do
      {:ok, {:bearer, token}}
    else
      _ -> :error
    end
  end

  defp sink_config(opts) do
    case Keyword.get(opts, :profile, :local) do
      :local ->
        %{}

      :hosted ->
        %{
          profile: :hosted,
          audience: Keyword.fetch!(opts, :audience),
          tls_ca_certfile: Keyword.get(opts, :tls_ca_certfile),
          credential: &__MODULE__.lookup_credential/0
        }
    end
  end

  defp destination?(opts) do
    case Keyword.get(opts, :profile, :local) do
      :local ->
        is_nil(Keyword.get(opts, :audience)) and is_nil(Keyword.get(opts, :tls_ca_certfile)) and
          url?(Keyword.fetch!(opts, :url))

      :hosted ->
        ca?(Keyword.get(opts, :tls_ca_certfile)) and
          hosted?(Keyword.fetch!(opts, :url), Keyword.get(opts, :audience))

      _ ->
        false
    end
  end

  defp url?(url) when is_binary(url) and byte_size(url) <= 64,
    do: Regex.match?(~r/\Ahttp:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}\/v1\/otlp\z/, url) and port?(url)

  defp url?(_), do: false

  defp port?(url) do
    [_, port] = Regex.run(~r/:([0-9]+)\/v1\/otlp\z/, url)
    String.to_integer(port) <= 65_535
  end

  defp hosted?(url, audience)
       when is_binary(url) and byte_size(url) in 1..2_048 and is_binary(audience) and
              byte_size(audience) in 1..2_048 do
    with {:ok,
          %URI{scheme: "https", path: "/v1/otlp", query: nil, fragment: nil, userinfo: nil} =
            uri} <- URI.new(url),
         {:ok, %URI{scheme: "https", path: nil, query: nil, fragment: nil, userinfo: nil} = origin} <-
           URI.new(audience),
         true <- is_binary(uri.host) and uri.host != "" do
      {uri.host, uri.port} == {origin.host, origin.port}
    else
      _ -> false
    end
  end

  defp hosted?(_, _), do: false

  defp ca?(nil), do: true
  defp ca?(path), do: is_binary(path) and byte_size(path) in 1..2_048

  defp database?(nil), do: true
  defp database?(database), do: match?({:ok, _}, Retention.database(database))

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_otlp_export, :construction, "OTLP export configuration is invalid")}
end
