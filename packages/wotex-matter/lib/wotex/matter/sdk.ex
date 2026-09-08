defmodule Wotex.Matter.SDK do
  @moduledoc """
  Opt-in external-process adapter for the Matter SDK v1.6.0.0 Python controller API.

  The caller supplies an absolute Python executable and a trusted controller
  factory. The adapter does not install the SDK, commission a fabric, validate
  attestation, provide CASE/PASE, or prove the provenance of either dependency.
  """

  @behaviour Wotex.Matter.Client
  alias Wotex.Matter.{Address, Error}

  @impl Wotex.Matter.Client
  def connect(opts) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: connect_options(opts),
      else: {:error, Error.new(:controller_configuration_required)}
  end

  def connect(_), do: {:error, Error.new(:controller_configuration_required)}

  defp connect_options(opts) do
    executable = Keyword.get(opts, :executable)
    factory = Keyword.get(opts, :factory)
    settings = Keyword.get(opts, :settings, %{})
    fabric = Keyword.get(opts, :fabric_id)
    allowed = [:executable, :factory, :settings, :fabric_id, :timeout]

    if Keyword.keys(opts) -- allowed == [] and absolute?(executable) and
         factory?(factory) and is_map(settings) and is_integer(fabric) and
         fabric in 1..0xFFFFFFFFFFFFFFFF do
      config = %{factory: factory, settings: settings, fabric_id: fabric}
      {:ok, %{executable: executable, config: config}}
    else
      {:error, Error.new(:controller_configuration_required)}
    end
  end

  @impl Wotex.Matter.Client
  def request(
        %{executable: executable, config: %{fabric_id: fabric} = config},
        message,
        timeout
      )
      when is_binary(executable) and is_integer(timeout) and timeout in 1..60_000 do
    with :ok <- Address.validate_message(message),
         {:ok, address} <- Address.new(message),
         true <- address.fabric_id == fabric,
         id = System.unique_integer([:positive]),
         wire = %{
           id: id,
           config: config,
           timeout_ms: timeout,
           message: message
         },
         {:ok, json} <- Jason.encode(wire),
         true <- byte_size(json) < 131_072 do
      run(executable, json <> "\n", id, timeout)
    else
      _ -> {:error, Error.new(:invalid_request)}
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @impl Wotex.Matter.Client
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
    script = Path.join(:code.priv_dir(:wotex_matter), "matter_bridge.py")

    port =
      Port.open(
        {:spawn_executable, executable},
        [:binary, :exit_status, :stderr_to_stdout, args: [script]]
      )

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

  defp absolute?(value), do: is_binary(value) and Path.type(value) == :absolute

  defp factory?(value) when is_binary(value) and byte_size(value) <= 255,
    do: Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_.]*:[a-zA-Z_][a-zA-Z0-9_]*\z/, value)

  defp factory?(_), do: false
end
