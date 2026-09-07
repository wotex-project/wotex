defmodule Wotex.Lab.Test.MqttBroker do
  @moduledoc false

  # A disposable eclipse-mosquitto:2 container for the MQTT lane. Each broker
  # binds an ephemeral loopback port, keeps no persistence, and is removed in
  # `on_exit`. Every run also gets its own topic prefix so concurrent tests and
  # repeated runs never share retained state.

  @image "eclipse-mosquitto:2"
  @loopback ~c"127.0.0.1"

  @type t :: %{
          required(:host) => String.t(),
          required(:port) => pos_integer(),
          required(:container) => String.t(),
          required(:prefix) => String.t()
        }

  @spec start(keyword()) :: t()
  def start(opts \\ []) do
    directory = configure(opts)
    container = run(directory)

    ExUnit.Callbacks.on_exit(fn ->
      halt(container)
      File.rm_rf(directory)
    end)

    port = mapped_port(container, 40)
    :ok = await_port(port, 100)
    %{host: "127.0.0.1", port: port, container: container, prefix: "lab/" <> token()}
  end

  @spec halt(String.t()) :: :ok
  def halt(container) do
    _removed =
      System.cmd("docker", ["rm", "--force", "--volumes", container], stderr_to_stdout: true)

    :ok
  end

  @spec stop(String.t()) :: :ok
  def stop(container) do
    _stopped = System.cmd("docker", ["stop", "--time", "2", container], stderr_to_stdout: true)
    :ok
  end

  @spec href(t()) :: String.t()
  def href(broker), do: "mqtt://#{broker.host}:#{broker.port}"

  @spec publish(t(), String.t(), binary(), keyword()) :: :ok
  def publish(broker, topic, payload, opts \\ []) do
    {:ok, client} =
      :emqtt.start_link(fixture_options(broker) ++ Keyword.take(opts, [:username, :password]))

    {:ok, _properties} = :emqtt.connect(client)

    {:ok, _packet_id} =
      :emqtt.publish(client, topic, %{}, payload,
        qos: 1,
        retain: Keyword.get(opts, :retain, false)
      )

    :ok = :emqtt.disconnect(client)
    :ok
  end

  @spec listen(t(), String.t(), keyword()) :: pid()
  def listen(broker, filter, opts \\ []) do
    credentials = Keyword.take(opts, [:username, :password])
    {:ok, client} = :emqtt.start_link(fixture_options(broker) ++ credentials)
    {:ok, _properties} = :emqtt.connect(client)
    {:ok, _properties, _codes} = :emqtt.subscribe(client, %{}, [{filter, [qos: 1]}])
    client
  end

  @spec fixture_options(t()) :: keyword()
  def fixture_options(broker) do
    [
      host: @loopback,
      port: broker.port,
      clientid: "lab-fixture-" <> token(),
      proto_ver: :v5,
      clean_start: true,
      reconnect: false,
      connect_timeout: 5
    ]
  end

  @spec token() :: String.t()
  def token, do: Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

  defp configure(opts) do
    directory = Path.join(System.tmp_dir!(), "wotex-lab-mqtt-" <> token())
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o755)

    lines =
      ["listener 1883", "persistence false", "sys_interval 1"] ++ authentication(directory, opts)

    configuration = Path.join(directory, "mosquitto.conf")
    File.write!(configuration, Enum.join(lines, "\n") <> "\n")
    File.chmod!(configuration, 0o644)
    directory
  end

  defp authentication(directory, opts) do
    case Keyword.get(opts, :credentials) do
      nil ->
        ["allow_anonymous true"]

      {user, password} ->
        {_output, 0} =
          System.cmd(
            "docker",
            ["run", "--rm", "--volume", directory <> ":/work", @image] ++
              ["mosquitto_passwd", "-b", "-c", "/work/passwd", user, password],
            stderr_to_stdout: true
          )

        File.chmod!(Path.join(directory, "passwd"), 0o644)
        ["allow_anonymous false", "password_file /mosquitto/config/passwd"]
    end
  end

  defp run(directory) do
    {output, 0} =
      System.cmd(
        "docker",
        ["run", "--detach", "--rm", "--publish", "127.0.0.1::1883"] ++
          ["--volume", directory <> ":/mosquitto/config:ro", @image],
        stderr_to_stdout: true
      )

    String.trim(output)
  end

  defp mapped_port(container, 0), do: raise("broker #{container} published no mapped port")

  defp mapped_port(container, attempts) do
    case System.cmd("docker", ["port", container, "1883"], stderr_to_stdout: true) do
      {output, 0} ->
        case String.split(String.trim(output), "\n", trim: true) do
          [] -> retry_port(container, attempts)
          [mapping | _rest] -> mapping |> String.split(":") |> List.last() |> String.to_integer()
        end

      {_output, _status} ->
        retry_port(container, attempts)
    end
  end

  defp retry_port(container, attempts) do
    Process.sleep(50)
    mapped_port(container, attempts - 1)
  end

  defp await_port(port, 0), do: raise("broker on port #{port} never accepted a connection")

  defp await_port(port, attempts) do
    case :gen_tcp.connect(@loopback, port, [:binary, active: false], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)

      {:error, _reason} ->
        Process.sleep(50)
        await_port(port, attempts - 1)
    end
  end
end
