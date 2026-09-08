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
          required(:prefix) => String.t(),
          required(:scheme) => :mqtt | :mqtts,
          optional(:ca_certfile) => String.t()
        }

  @spec start(keyword()) :: t()
  def start(opts \\ []) do
    fixture = configure(opts)
    container = run(fixture.directory, fixture.listener)

    ExUnit.Callbacks.on_exit(fn ->
      halt(container)
      File.rm_rf(fixture.directory)
    end)

    port = mapped_port(container, fixture.listener, 40)
    :ok = await_port(port, 100)

    %{
      host: fixture.host,
      port: port,
      container: container,
      prefix: "lab/" <> token(),
      scheme: fixture.scheme,
      ca_certfile: fixture.ca_certfile
    }
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
  def href(broker), do: "#{broker.scheme}://#{broker.host}:#{broker.port}"

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
    base = [
      host: @loopback,
      port: broker.port,
      clientid: "lab-fixture-" <> token(),
      proto_ver: :v5,
      clean_start: true,
      reconnect: false,
      connect_timeout: 5
    ]

    base ++ tls_options(broker)
  end

  @spec token() :: String.t()
  def token, do: Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

  defp configure(opts) do
    directory = Path.join(System.tmp_dir!(), "wotex-lab-mqtt-" <> token())
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o755)

    tls? = Keyword.get(opts, :tls, false)
    listener = if tls?, do: 8_883, else: 1_883

    lines =
      ["listener #{listener}", "persistence false", "sys_interval 1"] ++
        authentication(directory, opts) ++ acl(directory, opts) ++ tls(directory, tls?)

    configuration = Path.join(directory, "mosquitto.conf")
    File.write!(configuration, Enum.join(lines, "\n") <> "\n")
    File.chmod!(configuration, 0o644)

    %{
      directory: directory,
      listener: listener,
      scheme: if(tls?, do: :mqtts, else: :mqtt),
      host: if(tls?, do: "localhost", else: "127.0.0.1"),
      ca_certfile: if(tls?, do: tls_fixture("ca-cert.pem"), else: nil)
    }
  end

  defp authentication(directory, opts) do
    case normalize_credentials(Keyword.get(opts, :credentials)) do
      [] ->
        ["allow_anonymous true"]

      credentials ->
        credentials
        |> Enum.with_index()
        |> Enum.each(&add_credential(directory, &1))

        File.chmod!(Path.join(directory, "passwd"), 0o644)
        ["allow_anonymous false", "password_file /mosquitto/config/passwd"]
    end
  end

  defp add_credential(directory, {{user, password}, index}) do
    create = if index == 0, do: ["-c"], else: []

    {_output, 0} =
      System.cmd(
        "docker",
        ["run", "--rm", "--volume", directory <> ":/work", @image] ++
          ["mosquitto_passwd", "-b"] ++ create ++ ["/work/passwd", user, password],
        stderr_to_stdout: true
      )
  end

  defp normalize_credentials(nil), do: []
  defp normalize_credentials({user, password}), do: [{user, password}]
  defp normalize_credentials(credentials) when is_list(credentials), do: credentials

  defp acl(directory, opts) do
    case Keyword.get(opts, :acl) do
      nil ->
        []

      rules when is_map(rules) ->
        contents =
          Enum.flat_map(rules, fn {user, topics} ->
            ["user #{user}" | Enum.map(topics, &"topic readwrite #{&1}")]
          end)
          |> Enum.join("\n")

        path = Path.join(directory, "acl")
        File.write!(path, contents <> "\n")
        File.chmod!(path, 0o644)
        ["acl_file /mosquitto/config/acl"]
    end
  end

  defp tls(_directory, false), do: []

  defp tls(directory, true) do
    for filename <- ["ca-cert.pem", "localhost-cert.pem", "localhost-key.pem"] do
      File.cp!(tls_fixture(filename), Path.join(directory, filename))
      File.chmod!(Path.join(directory, filename), 0o644)
    end

    [
      "cafile /mosquitto/config/ca-cert.pem",
      "certfile /mosquitto/config/localhost-cert.pem",
      "keyfile /mosquitto/config/localhost-key.pem",
      "tls_version tlsv1.2"
    ]
  end

  defp tls_fixture(filename),
    do: Path.expand(Path.join([__DIR__, "../fixtures/tls", filename]))

  defp tls_options(%{scheme: :mqtt}), do: []

  defp tls_options(%{scheme: :mqtts} = broker) do
    [
      ssl: true,
      ssl_opts: [
        verify: :verify_peer,
        cacertfile: String.to_charlist(broker.ca_certfile),
        server_name_indication: ~c"localhost",
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]
  end

  defp run(directory, listener) do
    {output, 0} =
      System.cmd(
        "docker",
        ["run", "--detach", "--rm", "--publish", "127.0.0.1::#{listener}"] ++
          ["--volume", directory <> ":/mosquitto/config:ro", @image],
        stderr_to_stdout: true
      )

    String.trim(output)
  end

  defp mapped_port(container, _listener, 0),
    do: raise("broker #{container} published no mapped port")

  defp mapped_port(container, listener, attempts) do
    case System.cmd("docker", ["port", container, Integer.to_string(listener)],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case String.split(String.trim(output), "\n", trim: true) do
          [] -> retry_port(container, listener, attempts)
          [mapping | _rest] -> mapping |> String.split(":") |> List.last() |> String.to_integer()
        end

      {_output, _status} ->
        retry_port(container, listener, attempts)
    end
  end

  defp retry_port(container, listener, attempts) do
    Process.sleep(50)
    mapped_port(container, listener, attempts - 1)
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
