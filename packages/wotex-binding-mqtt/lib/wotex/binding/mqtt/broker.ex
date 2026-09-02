defmodule Wotex.Binding.MQTT.Broker do
  @moduledoc """
  Immutable, credential-free MQTT broker value.

  The href contains only an `mqtt` or `mqtts` broker endpoint. Topic Names and
  Topic Filters belong to their dedicated Form terms and are rejected here.
  """

  alias Wotex.Binding.MQTT.Error

  @derive {Inspect, only: [:scheme, :host, :port]}
  @opaque t :: %__MODULE__{
            href: String.t(),
            scheme: :mqtt | :mqtts,
            host: String.t(),
            port: 1..65_535 | nil
          }

  @enforce_keys [:href, :scheme, :host]
  defstruct [:href, :scheme, :host, :port]

  @doc "Builds a broker from a broker-only MQTT href."
  @spec new(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(href) when is_binary(href) do
    with :ok <- validate_unpadded(href),
         {:ok, uri} <- parse(href),
         {:ok, scheme} <- validate_scheme(uri.scheme),
         :ok <- validate_host(uri.host),
         :ok <- validate_port(uri.port),
         :ok <- validate_credential_free(uri.userinfo),
         :ok <- validate_authority(uri.authority, uri.host, uri.port),
         :ok <- validate_broker_only(uri.path, uri.query, uri.fragment) do
      {:ok,
       %__MODULE__{
         href: href,
         scheme: scheme,
         host: uri.host,
         port: uri.port
       }}
    end
  end

  def new(_href),
    do: {:error, Error.new(:invalid_broker_href, :broker, "broker href must be a string")}

  @doc "Returns the original validated broker href."
  @spec href(t()) :: String.t()
  def href(%__MODULE__{href: href}), do: href

  @doc "Returns the normalized broker scheme."
  @spec scheme(t()) :: :mqtt | :mqtts
  def scheme(%__MODULE__{scheme: scheme}), do: scheme

  @doc "Returns the broker host."
  @spec host(t()) :: String.t()
  def host(%__MODULE__{host: host}), do: host

  @doc "Returns the explicit port, or `nil` when the Form omitted it."
  @spec port(t()) :: 1..65_535 | nil
  def port(%__MODULE__{port: port}), do: port

  defp validate_unpadded(href) do
    if href != "" and href == String.trim(href) do
      :ok
    else
      {:error, Error.new(:invalid_broker_href, :broker, "broker href must be non-empty")}
    end
  end

  defp parse(href) do
    {:ok, URI.parse(href)}
  rescue
    URI.Error ->
      {:error, Error.new(:invalid_broker_href, :broker, "broker href is not a valid URI")}
  end

  defp validate_scheme(scheme) when is_binary(scheme) do
    case String.downcase(scheme) do
      "mqtt" -> {:ok, :mqtt}
      "mqtts" -> {:ok, :mqtts}
      _other -> invalid_scheme()
    end
  end

  defp validate_scheme(_scheme), do: invalid_scheme()

  defp invalid_scheme do
    {:error, Error.new(:unsupported_broker_scheme, :broker, "broker scheme must be mqtt or mqtts")}
  end

  defp validate_host(host) when is_binary(host) and byte_size(host) > 0, do: :ok

  defp validate_host(_host),
    do: {:error, Error.new(:missing_broker_host, :broker, "broker href must include a host")}

  defp validate_port(nil), do: :ok
  defp validate_port(port) when is_integer(port) and port in 1..65_535, do: :ok

  defp validate_port(_port),
    do: {:error, Error.new(:invalid_broker_port, :broker, "broker port is invalid")}

  defp validate_credential_free(nil), do: :ok

  defp validate_credential_free(_userinfo) do
    {:error,
     Error.new(
       :broker_credentials_forbidden,
       :broker,
       "broker href must not contain user information"
     )}
  end

  defp validate_authority(authority, host, port) do
    rendered_host = if String.contains?(host, ":"), do: "[#{host}]", else: host
    expected = if is_integer(port), do: "#{rendered_host}:#{port}", else: rendered_host

    if authority == expected do
      :ok
    else
      {:error, Error.new(:invalid_broker_port, :broker, "broker port is invalid")}
    end
  end

  defp validate_broker_only(path, query, fragment)
       when path in [nil, "", "/"] and is_nil(query) and is_nil(fragment),
       do: :ok

  defp validate_broker_only(_path, _query, _fragment) do
    {:error,
     Error.new(
       :broker_href_not_endpoint_only,
       :broker,
       "broker href must not contain a topic, filter, query, or fragment"
     )}
  end
end
