defmodule WotexLabWorkbench.Observability.Otlp do
  @moduledoc """
  Closed Workbench activation of the base library's OTLP exporter.

  `configure/2` admits the exact local receiver base URL
  `http://127.0.0.1:<port>/v1/otlp`, without query, fragment or userinfo, and
  an optional database identifier admitted by
  `Wotex.Lab.Metrics.Retention.database/1`. `child_options/1` builds the
  `Wotex.Lab.Otlp.Exporter` options for the host: service instance
  `workbench`, both signals, a five-second interval and deadline, 512 buffered
  records per signal and 256 records per request, writing through
  `Wotex.Lab.Otlp.GreptimeSink`. The exporter observes the Lab spans of every
  session on this host; its records carry closed vocabularies only.

  `WOTEX_LAB_OTLP_URL` and optional `WOTEX_LAB_OTLP_DATABASE` select this
  profile at boot. It needs no PromEx or history activation and sends no
  credential; authenticated hosted receivers are not part of it.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.Retention
  alias Wotex.Lab.Otlp.GreptimeSink

  @keys [:url, :database]

  @doc "Admits the local receiver base URL and an optional database."
  @spec configure(term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(url, database) do
    options = [url: url, database: database]
    with :ok <- validate(options), do: {:ok, options}
  end

  @doc "Validates closed activation options without opening a connection."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @keys),
         true <- Keyword.has_key?(opts, :url) and Keyword.has_key?(opts, :database),
         true <- url?(Keyword.fetch!(opts, :url)),
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
      GreptimeSink.new(%{
        url: Keyword.fetch!(opts, :url),
        database: Keyword.fetch!(opts, :database),
        receive_timeout: 5_000,
        connect_timeout: 5_000
      })

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

  defp url?(url) when is_binary(url) and byte_size(url) <= 64,
    do: Regex.match?(~r/\Ahttp:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}\/v1\/otlp\z/, url) and port?(url)

  defp url?(_), do: false

  defp port?(url) do
    [_, port] = Regex.run(~r/:([0-9]+)\/v1\/otlp\z/, url)
    String.to_integer(port) <= 65_535
  end

  defp database?(nil), do: true
  defp database?(database), do: match?({:ok, _}, Retention.database(database))

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_otlp_export, :construction, "OTLP export configuration is invalid")}
end
