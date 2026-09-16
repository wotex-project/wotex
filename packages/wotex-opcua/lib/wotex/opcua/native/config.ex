defmodule Wotex.OPCUA.Native.Config do
  @moduledoc """
  Validates explicit native Session configuration and snapshots credential files.

  `new/1` checks only option shape and does no file or network I/O. The caller
  passes one original monotonic deadline to `open_parameters/2`; that function
  reads only named regular files, bounds each input to 64 KiB, and returns the
  closed native `open` map. The native executable performs DER, trust and peer
  verification before service admission. One-shot callers can defer file reads
  until an operation without introducing a Python runtime dependency.
  """

  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.HostOptions

  @policies %{
    basic256sha256: "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
    aes128_sha256_rsaoaep: "http://opcfoundation.org/UA/SecurityPolicy#Aes128_Sha256_RsaOaep",
    aes256_sha256_rsapss: "http://opcfoundation.org/UA/SecurityPolicy#Aes256_Sha256_RsaPss"
  }
  @files [:certificate, :private_key, :server_certificate, :trust_certificate, :crl]
  @required [
    :executable,
    :executable_digest,
    :guardian,
    :guardian_digest,
    :endpoint,
    :security_policy,
    :security_mode,
    :client_uri,
    :server_uri,
    :certificate,
    :private_key,
    :server_certificate,
    :trust_certificate,
    :crl,
    :authentication
  ]
  @optional [:lifecycle, :timeout, :session_timeout_ms]
  @keys @required ++ @optional
  @derive {Inspect,
           only: [:security_policy, :security_mode, :lifecycle, :timeout, :session_timeout_ms]}
  @enforce_keys @required
  defstruct @required ++ [lifecycle: :persistent, timeout: 5000, session_timeout_ms: 60_000]

  @type t :: %__MODULE__{}

  @doc "Checks the exact native option keys and values without reading files."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         keys = Keyword.keys(options),
         true <- length(keys) == length(Enum.uniq(keys)),
         true <- keys -- @keys == [] and @required -- keys == [],
         values = Map.new(options),
         {:ok, _} <-
           HostOptions.new(
             Keyword.take(options, [
               :executable,
               :executable_digest,
               :guardian,
               :guardian_digest,
               :timeout
             ])
           ),
         true <- endpoint?(values.endpoint),
         true <- text?(values.client_uri, 4096) and text?(values.server_uri, 4096),
         true <- Enum.all?(@files, &path?(Map.get(values, &1))),
         true <- Map.has_key?(@policies, values.security_policy),
         true <- values.security_mode == :sign_and_encrypt,
         true <- authentication?(values.authentication),
         true <- Map.get(values, :lifecycle, :persistent) in [:persistent, :oneshot],
         timeout when is_integer(timeout) and timeout in 1..60_000 <-
           Map.get(values, :timeout, 5000),
         session_timeout
         when is_integer(session_timeout) and
                session_timeout in 1000..3_600_000 <-
           Map.get(values, :session_timeout_ms, 60_000) do
      {:ok,
       struct!(
         __MODULE__,
         values
         |> Map.put(:timeout, timeout)
         |> Map.put(:session_timeout_ms, session_timeout)
         |> Map.put_new(:lifecycle, :persistent)
       )}
    else
      _ -> configuration_error()
    end
  end

  def new(_), do: configuration_error()

  @doc "Returns the exact native open parameters from bounded files before the caller's deadline."
  @spec open_parameters(t(), integer()) :: {:ok, map()} | {:error, Error.t()}
  def open_parameters(%__MODULE__{} = config, deadline) when is_integer(deadline) do
    with {:ok, validated} <- new(Map.to_list(Map.from_struct(config))),
         :ok <- within_deadline(deadline),
         {:ok, files} <- read_files(validated, deadline),
         {:ok, authentication} <- authentication_parameters(validated.authentication, deadline) do
      parameters = %{
        "endpoint" => validated.endpoint,
        "security_policy" => Map.fetch!(@policies, validated.security_policy),
        "security_mode" => "SignAndEncrypt",
        "client_uri" => validated.client_uri,
        "server_uri" => validated.server_uri,
        "certificate" => files.certificate,
        "private_key" => files.private_key,
        "server_certificate" => files.server_certificate,
        "trust_certificate" => files.trust_certificate,
        "crl" => files.crl,
        "authentication" => authentication,
        "session_timeout_ms" => validated.session_timeout_ms
      }

      case Jason.encode(parameters) do
        {:ok, bytes} when byte_size(bytes) < 130_000 -> {:ok, parameters}
        _ -> {:error, Error.new(:request_too_large)}
      end
    end
  end

  def open_parameters(_, _), do: configuration_error()

  defp read_files(config, deadline) do
    Enum.reduce_while(@files, {:ok, %{}}, fn field, {:ok, values} ->
      case read_file(Map.fetch!(config, field), 65_536, deadline) do
        {:ok, bytes} -> {:cont, {:ok, Map.put(values, field, envelope(bytes))}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp authentication_parameters(%{type: :anonymous}, _), do: {:ok, %{"type" => "anonymous"}}

  defp authentication_parameters(%{type: :username, username: username, password: password}, _) do
    {:ok, %{"type" => "username", "username" => username, "password" => envelope(password)}}
  end

  defp authentication_parameters(
         %{type: :certificate, certificate: certificate, private_key: key},
         deadline
       ) do
    with {:ok, certificate_bytes} <- read_file(certificate, 65_536, deadline),
         {:ok, key_bytes} <- read_file(key, 65_536, deadline) do
      {:ok,
       %{
         "type" => "certificate",
         "certificate" => envelope(certificate_bytes),
         "private_key" => envelope(key_bytes)
       }}
    end
  end

  defp authentication_parameters(_, _), do: configuration_error()

  defp read_file(path, maximum, deadline) do
    with :ok <- within_deadline(deadline),
         {:ok, before} <- File.stat(path),
         true <- before.type == :regular and before.size in 1..maximum,
         {:ok, file} <- File.open(path, [:read, :binary]) do
      result = IO.binread(file, maximum + 1)
      File.close(file)

      with bytes when is_binary(bytes) and byte_size(bytes) == before.size <- result,
           {:ok, after_read} <- File.stat(path),
           true <-
             after_read.type == :regular and after_read.size == before.size and
               after_read.mtime == before.mtime and after_read.inode == before.inode,
           :ok <- within_deadline(deadline) do
        {:ok, bytes}
      else
        {:error, %Error{}} = error -> error
        _ -> configuration_error()
      end
    else
      {:error, %Error{}} = error -> error
      _ -> configuration_error()
    end
  end

  defp within_deadline(limit) do
    if System.monotonic_time(:millisecond) < limit,
      do: :ok,
      else: {:error, Error.new(:deadline_exceeded, :deadline)}
  end

  defp envelope(bytes), do: %{"type" => "bytes", "base64" => Base.encode64(bytes)}

  defp authentication?(%{type: :anonymous} = value), do: map_size(value) == 1

  defp authentication?(%{type: :username, username: username, password: password} = value),
    do:
      map_size(value) == 3 and text?(username, 1024) and is_binary(password) and
        byte_size(password) <= 4096

  defp authentication?(%{type: :certificate, certificate: certificate, private_key: key} = value),
    do: map_size(value) == 3 and path?(certificate) and path?(key)

  defp authentication?(_), do: false

  defp endpoint?(endpoint) do
    if text?(endpoint, 4096) do
      match?(
        %URI{scheme: "opc.tcp", host: host, userinfo: nil} when is_binary(host),
        URI.parse(endpoint)
      )
    else
      false
    end
  end

  defp text?(value, maximum),
    do:
      is_binary(value) and byte_size(value) in 1..maximum and String.valid?(value) and
        not String.contains?(value, <<0>>)

  defp path?(value),
    do: text?(value, 4096) and Path.type(value) == :absolute

  defp configuration_error, do: {:error, Error.new(:invalid_native_configuration)}
end
