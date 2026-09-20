defmodule WotexThreadArchiveConsumer.Credentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(%{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}}, _, _, _),
    do: {:ok, nil}

  def resolve(_, _, _, _), do: {:error, Wotex.Thread.Error.new(:unsupported_security)}
end

defmodule WotexThreadArchiveConsumer.Transport do
  @moduledoc false

  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Transport
  def request(request, execution, config) do
    {observer, config} = Keyword.pop!(config, :observer)
    send(observer, {:selected_request, request})
    Wotex.Thread.Transport.request(request, execution, config)
  end

  @impl Wotex.Runtime.Transport
  def subscribe(request, owner, execution, config) do
    {_, config} = Keyword.pop!(config, :observer)
    Wotex.Thread.Transport.subscribe(request, owner, execution, config)
  end

  @impl Wotex.Runtime.Transport
  def unsubscribe(handle, request, execution, config) do
    {_, config} = Keyword.pop!(config, :observer)
    Wotex.Thread.Transport.unsubscribe(handle, request, execution, config)
  end
end

defmodule WotexThreadArchiveConsumer.Peer do
  @moduledoc false

  @spec start(String.t()) :: {String.t(), Task.t()}
  def start(reply) do
    path =
      Path.join(
        System.tmp_dir!(),
        "wotex-thread-archive-peer-#{System.pid()}-#{System.unique_integer([:positive])}.sock"
      )

    owner = self()

    task =
      Task.async(fn ->
        {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ifaddr: {:local, path}])
        send(owner, {:archive_peer_listening, path})

        try do
          {:ok, socket} = :gen_tcp.accept(listener, 1_000)

          try do
            {:ok, command} = :gen_tcp.recv(socket, 0, 1_000)
            :ok = :gen_tcp.send(socket, reply <> "\nDone\n")
            {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)
            %{commands: [String.trim_trailing(command, "\n")], closed_connections: 1}
          after
            :gen_tcp.close(socket)
          end
        after
          :gen_tcp.close(listener)
          File.rm(path)
        end
      end)

    receive do
      {:archive_peer_listening, ^path} -> {path, task}
    after
      1_000 -> raise "archive reference peer did not start"
    end
  end
end

defmodule WotexThreadArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.{Form, ThingDescription}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}
  alias WotexThreadArchiveConsumer.{Credentials, Peer, Transport}

  @archive_roots String.split(System.fetch_env!("WOTEX_ARCHIVE_ROOTS"), "\n")
  @live_roots String.split(System.fetch_env!("WOTEX_LIVE_ROOTS"), "\n")
  @apps [:wotex, :wotex_runtime, :wotex_thread]
  @modules [Wotex, Wotex.Runtime.ConsumedThing, Wotex.Thread]

  test "WTH-I06 exact archives are the only Wotex compile and load sources" do
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

  test "WTH-I06 packaged core, Runtime, Thread, corpus and daemon execute the exact read" do
    fixture = integration_case("WTH-I-F01")
    input = fixture["input"]
    reply = input["peer_reply"]["value"]
    {socket_path, peer} = Peer.start(reply)

    try do
      {:ok, thing_description} = ThingDescription.from_map(input["thing_description"])
      profile = Wotex.Thread.profile()

      {:ok, consumed} =
        ConsumedThing.new(thing_description,
          profiles: [profile],
          transports: %{
            BindingProfile.id(profile) =>
              {Transport,
               client: Wotex.Thread.Daemon,
               observer: self(),
               socket_path: socket_path,
               target: input["transport_options"]["target"],
               timeout: input["transport_options"]["timeout"]}
          },
          credentials: {Credentials, []}
        )

      clock = input["clock"]

      deadline =
        System.monotonic_time(:millisecond) + clock["deadline"] - clock["start"]

      context = Context.new!(request_id: input["request_id"], deadline: deadline)

      assert {:ok, %Result{} = result} =
               ConsumedThing.read_property(consumed, input["affordance"], context)

      assert_receive {:selected_request, request}, 1_000
      peer_result = Task.await(peer, 1_000)

      actual = %{
        "profile_id" => Atom.to_string(BindingProfile.id(request.profile)),
        "resolved_href" => request.resolved_href,
        "command" => %{"type" => List.first(peer_result.commands)},
        "result" => %{
          "request_id" => result.request_id,
          "operation" => Atom.to_string(result.operation),
          "status" => Atom.to_string(result.status),
          "payload" => result.payload,
          "metadata" => result.metadata
        },
        "extension" => Form.to_map(request.form)["example:extension"],
        "request_count" => length(peer_result.commands),
        "owned_resources_after" =>
          if(peer_result.closed_connections == 1 and not File.exists?(socket_path), do: 0, else: 1)
      }

      assert actual == fixture["expectation"]["value"]
      refute Process.alive?(peer.pid)
    after
      if Process.alive?(peer.pid), do: Task.shutdown(peer, :brutal_kill)
      File.rm(socket_path)
    end
  end

  defp integration_case(id) do
    path = Application.app_dir(:wotex_thread, "priv/fixtures/wotex-integration-v1.json")

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
