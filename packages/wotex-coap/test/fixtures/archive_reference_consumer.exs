defmodule WotexCoAPArchiveConsumer.Credentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(%{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}}, _, _, _),
    do: {:ok, nil}

  def resolve(_, _, _, _), do: {:error, Wotex.CoAP.Error.new(:unsupported_security)}
end

defmodule WotexCoAPArchiveConsumer.Transport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Transport
  def request(request, execution, config) do
    {observer, config} = Keyword.pop!(config, :observer)
    send(observer, {:selected_request, request})
    Wotex.CoAP.Transport.request(request, execution, config)
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, config) do
    {_, config} = Keyword.pop!(config, :observer)
    Wotex.CoAP.Transport.subscribe(request, owner, execution, config)
  end

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, config) do
    {_, config} = Keyword.pop!(config, :observer)
    Wotex.CoAP.Transport.unsubscribe(handle, request, execution, config)
  end
end

defmodule WotexCoAPArchiveConsumer.Peer do
  @moduledoc false

  alias Wotex.CoAP.{Codec, Message}

  @spec start(map()) :: {pos_integer(), Task.t()}
  def start(reply) do
    owner = self()

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
        {:ok, {_, port}} = :inet.sockname(socket)
        send(owner, {:archive_peer_listening, port})

        try do
          {:ok, {host, source, bytes}} = :gen_udp.recv(socket, 0, 1_000)
          {:ok, request} = Codec.decode(bytes)

          response = %Message{
            type: :ack,
            code: reply["code"],
            message_id: request.message_id,
            token: request.token,
            options: [{12, Codec.uint(reply["content_format"])}],
            payload: Base.decode16!(reply["payload_hex"], case: :mixed)
          }

          {:ok, encoded} = Codec.encode(response)
          :ok = :gen_udp.send(socket, host, source, encoded)
          {:error, :timeout} = :gen_udp.recv(socket, 0, 50)
          %{requests: [request]}
        after
          :gen_udp.close(socket)
        end
      end)

    receive do
      {:archive_peer_listening, port} -> {port, task}
    after
      1_000 -> raise "archive reference peer did not start"
    end
  end
end

defmodule WotexCoAPArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP.Codec
  alias Wotex.{Form, ThingDescription}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}
  alias WotexCoAPArchiveConsumer.{Credentials, Peer, Transport}

  @archive_roots String.split(System.fetch_env!("WOTEX_ARCHIVE_ROOTS"), "\n")
  @live_roots String.split(System.fetch_env!("WOTEX_LIVE_ROOTS"), "\n")
  @apps [:wotex, :wotex_runtime, :wotex_coap]
  @modules [Wotex, Wotex.Runtime.ConsumedThing, Wotex.CoAP]

  test "WCO-I06 exact archives are the only Wotex compile and load sources" do
    build_root = Path.expand("_build", File.cwd!())

    Enum.zip(@apps, @modules)
    |> Enum.each(fn {app, module} ->
      assert Application.load(app) in [:ok, {:error, {:already_loaded, app}}]
      assert Application.spec(app, :mod) in [nil, [], :undefined]

      source = Path.expand(List.to_string(module.module_info(:compile)[:source]))
      beam = Path.expand(List.to_string(:code.which(module)))

      assert Enum.any?(@archive_roots, &inside?(source, &1))
      assert inside?(beam, build_root)
      refute Enum.any?(@live_roots, &inside?(source, &1))
      refute Enum.any?(@live_roots, &inside?(beam, &1))
    end)

    code_paths = Enum.map(:code.get_path(), &Path.expand(List.to_string(&1)))
    refute Enum.any?(code_paths, &Enum.any?(@live_roots, fn root -> inside?(&1, root) end))
  end

  test "WCO-I-F01 packaged core, Runtime, CoAP, corpus and UDP adapter execute one read" do
    fixture = integration_case("WCO-I-F01")
    input = fixture["input"]
    {port, peer} = Peer.start(input["peer_reply"])
    before_ports = MapSet.new(Port.list())

    try do
      affordance = input["affordance"]
      [form] = get_in(input, ["thing_description", "properties", affordance, "forms"])
      original_uri = URI.parse(form["href"])
      actual_href = URI.to_string(%{original_uri | port: port})

      description =
        put_in(input["thing_description"], ["properties", affordance, "forms"], [
          Map.put(form, "href", actual_href)
        ])

      {:ok, thing_description} = ThingDescription.from_map(description)
      {:ok, profile} = Wotex.CoAP.profile(:udp)

      {:ok, consumed} =
        ConsumedThing.new(thing_description,
          profiles: [profile],
          transports: %{
            BindingProfile.id(profile) =>
              {Transport, observer: self(), timeout: input["transport_options"]["timeout"]}
          },
          credentials: {Credentials, []}
        )

      clock = input["clock"]

      deadline =
        System.monotonic_time(:millisecond) + clock["deadline"] - clock["start"]

      context = Context.new!(request_id: input["request_id"], deadline: deadline)

      assert {:ok, %Result{} = result} =
               ConsumedThing.read_property(consumed, affordance, context)

      assert_receive {:selected_request, request}, 1_000
      %{requests: [protocol_request]} = Task.await(peer, 1_000)
      [accept] = Codec.option(protocol_request, 17)
      methods = %{1 => "get", 2 => "post", 3 => "put", 4 => "delete"}

      actual = %{
        "profile_id" => Atom.to_string(BindingProfile.id(request.profile)),
        "resolved_href" =>
          URI.to_string(%{URI.parse(request.resolved_href) | port: original_uri.port}),
        "command" => %{
          "method" => Map.fetch!(methods, protocol_request.code),
          "path" => "/" <> Enum.join(Codec.option(protocol_request, 11), "/"),
          "accept" => :binary.decode_unsigned(accept)
        },
        "result" => %{
          "request_id" => result.request_id,
          "operation" => Atom.to_string(result.operation),
          "status" => Atom.to_string(result.status),
          "payload" => result.payload,
          "metadata" => %{"code" => result.metadata.code}
        },
        "extension" => Form.to_map(request.form)["example:extension"],
        "request_count" => 1,
        "owned_resources_after" =>
          MapSet.size(MapSet.difference(MapSet.new(Port.list()), before_ports))
      }

      assert actual == fixture["expectation"]["value"]
      refute Process.alive?(peer.pid)
    after
      if Process.alive?(peer.pid), do: Task.shutdown(peer, :brutal_kill)
    end
  end

  defp integration_case(id) do
    path = Application.app_dir(:wotex_coap, "priv/fixtures/wotex-integration-v1.json")

    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
    |> Enum.find(&(&1["id"] == id))
  end

  defp inside?(path, root) do
    expanded_path = canonical(path)
    expanded_root = canonical(root)
    expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/")
  end

  defp canonical(path) do
    path
    |> Path.expand()
    |> String.replace_prefix("/private/var/", "/var/")
  end
end
