defmodule WotexBACnetArchiveConsumer.Client do
  @moduledoc false

  @behaviour Wotex.BACnet.Client

  @impl Wotex.BACnet.Client
  def connect(options) do
    {:ok, handle} = Agent.start(fn -> options end)
    send(Keyword.fetch!(options, :observer), {:client_opened, handle})
    {:ok, handle}
  end

  @impl Wotex.BACnet.Client
  def request(handle, request, timeout) do
    options = Agent.get(handle, & &1)
    send(Keyword.fetch!(options, :observer), {:client_request, handle, request, timeout})
    Keyword.fetch!(options, :reply)
  end

  @impl Wotex.BACnet.Client
  def disconnect(handle) do
    options = Agent.get(handle, & &1)
    Agent.stop(handle)
    send(Keyword.fetch!(options, :observer), {:client_closed, handle})
    :ok
  end
end

defmodule WotexBACnetArchiveConsumer.Credentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(%{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}}, _, _, _),
    do: {:ok, nil}

  def resolve(_, _, _, _), do: {:error, :unsupported_security}
end

defmodule WotexBACnetArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}
  alias WotexBACnetArchiveConsumer.{Client, Credentials}

  @archive_roots String.split(System.fetch_env!("WOTEX_ARCHIVE_ROOTS"), "\n")
  @live_roots String.split(System.fetch_env!("WOTEX_LIVE_ROOTS"), "\n")
  @apps [:wotex, :wotex_runtime, :wotex_bacnet]
  @modules [Wotex, Wotex.Runtime.ConsumedThing, Wotex.BACnet]

  test "WBA-A01 exact archives are the only Wotex compile and load sources" do
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

  test "WBA-A02 packaged native API owns one accepted read and exact cleanup" do
    value = Encoding.create!({:real, 21.0})
    {:ok, session} = BACnet.connect(client: Client, observer: self(), reply: {:ok, value})

    assert {:ok, ^value} = BACnet.read_property(session, :analog_value, 1, :present_value)
    assert_receive {:client_opened, handle}
    assert_receive {:client_request, ^handle, request, timeout}
    assert request.type == :read_property
    assert request.object_type == 2
    assert request.instance == 1
    assert request.property == 85
    assert timeout in 1..5_000

    assert :ok = BACnet.disconnect(session)
    assert_receive {:client_closed, ^handle}
    refute Process.alive?(handle)
  end

  test "WBA-A03 packaged core, Runtime, and BACnet APIs execute one selected interaction" do
    value = Encoding.create!({:real, 22.5})
    {:ok, profile} = BACnet.profile(:ip)
    assert BindingProfile.id(profile) == :bacnet

    {:ok, consumed} =
      ConsumedThing.new(thing_description(),
        profiles: [profile],
        transports: %{
          bacnet:
            {Wotex.BACnet.Transport,
             [client: Client, observer: self(), reply: {:ok, value}, target: "1234"]}
        },
        credentials: {Credentials, []}
      )

    context = Context.new!(request_id: "archive-runtime-read")

    assert {:ok,
            %Result{
              request_id: "archive-runtime-read",
              operation: :readproperty,
              status: :ok,
              payload: 22.5,
              metadata: %{bacnet_type: :real}
            }} = ConsumedThing.read_property(consumed, "reading", context)

    assert_receive {:client_opened, handle}
    assert_receive {:client_request, ^handle, request, timeout}
    assert request.type == :read_property
    assert request.array_index == 0
    assert timeout in 1..5_000
    assert_receive {:client_closed, ^handle}
    refute Process.alive?(handle)

    [form] = thing_description().document["properties"]["reading"]["forms"]
    assert form["example:archive"] == %{"kept" => [false, 0, nil]}
  end

  test "WBA-A04 packaged client failures are finite and do not retain external terms" do
    secret = "archive-client-secret"

    {:ok, session} =
      BACnet.connect(
        client: Client,
        observer: self(),
        reply: {:error, {:nested, [%{credential: secret}, self(), make_ref()]}}
      )

    assert {:error, %Wotex.BACnet.Error{code: :transport_error} = error} =
             BACnet.read_property(session, :analog_value, 1, :present_value)

    refute :erlang.term_to_binary(error) =~ secret
    assert_receive {:client_opened, handle}
    assert_receive {:client_request, ^handle, _, _}
    assert :ok = BACnet.disconnect(session)
    assert_receive {:client_closed, ^handle}
  end

  defp thing_description do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:bacnet-archive-consumer",
        "title" => "BACnet archive consumer",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "reading" => %{
            "type" => "number",
            "readOnly" => true,
            "forms" => [
              %{
                "href" => "bacnet://1234/2,1/85/0",
                "op" => "readproperty",
                "bacv:hasDataType" => %{"@type" => "bacv:Real"},
                "example:archive" => %{"kept" => [false, 0, nil]}
              }
            ]
          }
        }
      })

    td
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
