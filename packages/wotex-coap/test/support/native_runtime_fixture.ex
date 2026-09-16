defmodule Wotex.CoAP.Test.NativeRuntimeFixture do
  @moduledoc false

  alias Wotex.CoAP.Security

  @revision "7cf7465b784baded4de183290c547d582becfd28"

  @type fixture :: %{
          root: binary(),
          store: binary(),
          backend: %{executable: binary(), manifest: binary()},
          security: Security.t(),
          options: keyword()
        }

  @spec create(:request | :observe) :: fixture()
  def create(mode) do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-runtime-native-#{System.unique_integer([:positive])}"
      )

    store = Path.join(root, "context")
    executable = Path.join(root, "wotex-coap-oscore")
    manifest = Path.join(root, "native-manifest.json")
    File.mkdir_p!(store)
    File.write!(Path.join(store, "mode"), Atom.to_string(mode))
    File.write!(executable, source())
    File.chmod!(executable, 0o700)
    File.write!(manifest, manifest(digest(executable)))

    backend = %{executable: executable, manifest: manifest}
    security = security(store)

    %{
      root: root,
      store: store,
      backend: backend,
      security: security,
      options: [host: "127.0.0.1", port: 5683, security: security, native_backend: backend]
    }
  end

  @spec remove(fixture()) :: {:ok, [binary()]} | {:error, File.posix(), binary()}
  def remove(fixture), do: File.rm_rf!(fixture.root)

  @spec command(fixture(), binary()) :: map()
  def command(fixture, name) do
    path = Path.join(fixture.store, name)
    wait(path, System.monotonic_time(:millisecond) + 1_000)

    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp wait(path, deadline) do
    if not File.exists?(path) and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(5)
      wait(path, deadline)
    end
  end

  defp security(store) do
    {:ok, security} =
      Security.new(%{
        mode: :oscore,
        master_secret: <<0::128>>,
        master_salt: <<>>,
        sender_id: <<>>,
        recipient_id: <<1>>,
        context_store: store
      })

    security
  end

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end

  defp manifest(hash) do
    Jason.encode!(%{
      "schema" => "wotex.coap.native@1",
      "backend" => %{"name" => "libcoap", "version" => "4.3.5", "revision" => @revision},
      "executables" => %{"wotex-coap-oscore" => %{"sha256" => hash}}
    })
  end

  defp source do
    """
    #!/usr/bin/env elixir
    :logger.remove_handler(:default)
    revision = "#{@revision}"
    ["--custody", directory] = System.argv()
    mode = directory |> Path.join("mode") |> File.read!() |> String.trim()

    read = fn name ->
      line = IO.read(:stdio, :line)
      if line == :eof, do: System.halt(0)
      File.write!(Path.join(directory, name), line)
      line
    end

    id = fn command ->
      [_, value] = Regex.run(~r/"id":"([^"]+)"/, command)
      value
    end

    reply = fn command, result ->
      IO.write(~s({"version":1,"id":"\#{id.(command)}","ok":true,"result":\#{result}}\n))
    end

    IO.write(~s({"version":1,"event":"ready","backend":"libcoap","revision":"\#{revision}"}\n))
    open = read.("open.json")
    [_, generation] = Regex.run(~r/"generation":([0-9]+)/, open)
    reply.(open, "null")

    case mode do
      "request" ->
        request = read.("request.json")

        reply.(request, ~s({"type":"ack","code":69,"message_id":321,"token":{"type":"bytes","base64":"AQ=="},"options":[{"number":12,"value":{"type":"bytes","base64":"Mg=="}}],"payload":{"type":"bytes","base64":"NDI="}}))

        close = read.("close.json")
        reply.(close, "null")

      "observe" ->
        observe = read.("observe.json")
        subscription_id = id.(observe)
        reply.(observe, ~s({"subscription_id":"\#{subscription_id}","generation":\#{generation}}))
        credit = read.("credit-0.json")
        reply.(credit, "null")

        IO.write(~s({"version":1,"subscription_id":"\#{subscription_id}","generation":\#{generation},"report_seq":1,"event":"report","value":{"type":"ack","code":69,"message_id":401,"token":{"type":"bytes","base64":"Ag=="},"options":[{"number":6,"value":{"type":"bytes","base64":"Cg=="}},{"number":12,"value":{"type":"bytes","base64":"Mg=="}}],"payload":{"type":"bytes","base64":"NDI="}},"metadata":{"code":69,"observe":10,"etag":null,"content_format":50,"max_age":60}}\n))
        credit = read.("credit-1.json")
        reply.(credit, "null")
        cancel = read.("cancel.json")
        reply.(cancel, "null")
        Process.sleep(:infinity)
    end
    """
  end
end
