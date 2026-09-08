defmodule WotexLabWorkbench.Observability.Durable do
  @moduledoc """
  Closed configuration for the optional local GreptimeDB remote-write exporter.

  The endpoint is an exact IPv4-loopback HTTP path. Remote and TLS deployments
  need a separate destination-pinning profile and are deliberately refused.
  When bearer authentication is selected, only a fixed environment reference
  enters supervision; the token is resolved inside each disposable export
  worker and is never retained in application or bridge state.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.ReqSink
  alias Wotex.Lab.Options
  alias WotexLabWorkbench.Observability.Capture

  @credential_env "WOTEX_LAB_GREPTIME_TOKEN"
  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/
  @keys ~w(url bearer interval_ms queue_limit deadline_ms)a
  @defaults [interval_ms: 5_000, queue_limit: 16, deadline_ms: 5_000]

  @doc "Admits an exact local write URL and whether just-in-time Bearer lookup is required."
  @spec configure(term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(url, bearer?) when is_binary(url) and is_boolean(bearer?) do
    options = [url: url, bearer: bearer?] ++ @defaults
    with :ok <- validate(options), do: {:ok, options}
  end

  def configure(_url, _bearer), do: invalid()

  @doc "Validates the closed local exporter configuration without opening a connection."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @keys),
         true <- local_write_url?(Keyword.get(opts, :url)),
         true <- is_boolean(Keyword.get(opts, :bearer)),
         true <- integer?(opts, :interval_ms, 1_000, 60_000),
         true <- integer?(opts, :queue_limit, 1, 256),
         true <- integer?(opts, :deadline_ms, 100, 60_000) do
      :ok
    else
      _invalid -> invalid()
    end
  end

  def validate(_opts), do: invalid()

  @doc "Builds the base bridge child options, optionally writing the same captures to local history."
  @spec child_options(keyword(), GenServer.server() | nil) :: keyword()
  def child_options(opts, history) do
    sink_config = %{
      url: Keyword.fetch!(opts, :url),
      receive_timeout: Keyword.fetch!(opts, :deadline_ms),
      connect_timeout: Keyword.fetch!(opts, :deadline_ms),
      max_response_bytes: 4_096
    }

    [
      id: :workbench,
      name: __MODULE__.Bridge,
      scrape: &Capture.sample/0,
      sink: fn request, credential -> ReqSink.write(request, credential, sink_config) end,
      credential: credential(Keyword.fetch!(opts, :bearer)),
      history: history,
      interval_ms: Keyword.fetch!(opts, :interval_ms),
      queue_limit: Keyword.fetch!(opts, :queue_limit),
      deadline_ms: Keyword.fetch!(opts, :deadline_ms),
      labels: [{"instance", "workbench"}],
      profile: :greptime,
      restart: :permanent
    ]
  end

  @doc false
  @spec lookup_credential(atom()) :: {:ok, ReqSink.credential()} | :error
  def lookup_credential(:greptime_bearer) do
    case System.fetch_env(@credential_env) do
      {:ok, token} when is_binary(token) ->
        if Regex.match?(@token, token), do: {:ok, {:bearer, token}}, else: :error

      :error ->
        :error
    end
  end

  def lookup_credential(_reference), do: :error

  defp credential(false), do: nil

  defp credential(true),
    do: %{reference: :greptime_bearer, lookup: &__MODULE__.lookup_credential/1}

  defp local_write_url?(url) when is_binary(url) and byte_size(url) in 1..2_048 do
    case URI.new(url) do
      {:ok,
       %URI{
         scheme: "http",
         host: "127.0.0.1",
         path: "/v1/prometheus/write",
         query: nil,
         fragment: nil,
         userinfo: nil,
         port: port
       }} ->
        is_integer(port) and port in 1..65_535

      _invalid ->
        false
    end
  end

  defp local_write_url?(_url), do: false

  defp integer?(opts, key, minimum, maximum) do
    value = Keyword.get(opts, key)
    is_integer(value) and value in minimum..maximum
  end

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_durable_metrics, :construction, "local durable exporter is invalid")}
end
