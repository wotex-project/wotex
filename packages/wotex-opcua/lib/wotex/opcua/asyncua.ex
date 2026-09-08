defmodule Wotex.OPCUA.Asyncua do
  @moduledoc "Explicit asyncua 2.0.1 bridge using SignAndEncrypt, pinned server identity and verified CRLs."
  @behaviour Wotex.OPCUA.Client
  alias Wotex.OPCUA.{Address, Error}
  @paths [:certificate, :private_key, :server_certificate, :issuer_certificate, :crl]
  @strings [:endpoint, :client_uri, :server_uri]

  @impl Wotex.OPCUA.Client
  def connect(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: connect_options(opts), else: configuration_error()
  end

  def connect(_), do: configuration_error()

  defp connect_options(opts) do
    config = Map.new(Keyword.take(opts, [:trust_certificates | @paths ++ @strings]))
    executable = Keyword.get(opts, :executable)

    with true <- known_options?(opts),
         true <- absolute?(executable),
         true <- Enum.all?(@paths, &absolute?(Map.get(config, &1))),
         true <- Enum.all?(@strings, &text?(Map.get(config, &1))),
         true <- valid_trust?(Map.get(config, :trust_certificates)),
         %URI{scheme: "opc.tcp", host: host, userinfo: nil} when is_binary(host) <-
           URI.parse(config.endpoint),
         true <- Keyword.get(opts, :security_mode, :sign_and_encrypt) == :sign_and_encrypt do
      {:ok, %{executable: executable, config: config}}
    else
      _ -> configuration_error()
    end
  end

  @impl Wotex.OPCUA.Client
  def request(
        %{executable: executable, config: config},
        %{node_id: node_id} = message,
        timeout
      )
      when is_binary(executable) and is_map(config) and is_integer(timeout) and
             timeout in 1..60_000 do
    with {:ok, node} <- Address.new(node_id),
         id = System.unique_integer([:positive]),
         wire = %{
           id: id,
           config: config,
           timeout_ms: timeout,
           message: Map.put(message, :node_id, Address.to_string(node))
         },
         {:ok, json} <- Jason.encode(wire),
         true <- byte_size(json) < 131_072 do
      run(executable, json <> "\n", id, timeout)
    else
      _ -> {:error, Error.new(:invalid_request)}
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @impl Wotex.OPCUA.Client
  def disconnect(_), do: :ok

  @doc "Decodes one correlated bridge result; foreign IDs, logs and errors never count as success."
  @spec decode(term(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def decode(bytes, id) when is_binary(bytes) and byte_size(bytes) <= 131_072 do
    case Jason.decode(bytes) do
      {:ok, %{"id" => ^id, "ok" => value} = response} when map_size(response) == 2 -> {:ok, value}
      _ -> {:error, Error.new(:exchange_failed)}
    end
  end

  def decode(_, _), do: {:error, Error.new(:response_limit)}

  defp run(executable, json, id, timeout) do
    script = Path.join(:code.priv_dir(:wotex_opcua), "opcua_bridge.py")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [script]
      ])

    try do
      true = Port.command(port, json)
      collect(port, <<>>, id, System.monotonic_time(:millisecond) + timeout)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ -> {:error, Error.new(:transport_unavailable)}
  end

  defp collect(port, output, id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0,
      do: receive_output(port, output, id, deadline, remaining),
      else: {:error, Error.new(:timeout)}
  end

  defp receive_output(port, output, id, deadline, remaining) do
    receive do
      {^port, {:data, data}} when byte_size(output) + byte_size(data) <= 131_072 ->
        collect(port, output <> data, id, deadline)

      {^port, {:data, _}} ->
        {:error, Error.new(:response_limit)}

      {^port, {:exit_status, 0}} ->
        decode(output, id)

      {^port, {:exit_status, _}} ->
        {:error, Error.new(:exchange_failed)}
    after
      remaining -> {:error, Error.new(:timeout)}
    end
  end

  defp known_options?(opts) do
    allowed = [:executable, :timeout, :security_mode, :trust_certificates | @paths ++ @strings]
    keys = Keyword.keys(opts)
    keys -- allowed == [] and length(keys) == MapSet.size(MapSet.new(keys))
  end

  defp absolute?(value), do: is_binary(value) and Path.type(value) == :absolute
  defp text?(value), do: is_binary(value) and byte_size(value) in 1..4096

  defp valid_trust?(values) when is_list(values) and length(values) in 1..16,
    do: Enum.all?(values, &absolute?/1)

  defp valid_trust?(_), do: false

  defp configuration_error, do: {:error, Error.new(:security_configuration_required)}
end
