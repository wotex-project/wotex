defmodule Wotex.CoAP.RuntimeOSCORETest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP
  alias Wotex.CoAP.{Error, RuntimeNative, RuntimeSecurity, Security, Transport}
  alias Wotex.CoAP.Native.Connection, as: NativeConnection
  alias Wotex.CoAP.Test.{NativeRuntimeFixture, RuntimeCredentials}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Subscription}

  defmodule Credentials do
    @moduledoc false

    @behaviour Wotex.Runtime.Credentials

    @impl Wotex.Runtime.Credentials
    def resolve(_, _, _, credential), do: {:ok, credential}
  end

  test "WCO-S06 WCO-I02 WCO-I04 Runtime unary dispatches an immediate OSCORE credential" do
    fixture = NativeRuntimeFixture.create(:request)
    on_exit(fn -> NativeRuntimeFixture.remove(fixture) end)
    {:ok, profile} = CoAP.profile(:oscore)
    assert BindingProfile.id(profile) == :coap_oscore
    {:ok, thing} = thing(profile, fixture, {Credentials, fixture.security})
    {:ok, context} = Context.new(request_id: "oscore-read")

    assert {:ok, result} = ConsumedThing.read_property(thing, "reading", context)
    assert result.payload == 42
    assert result.metadata == %{code: 69}

    request = NativeRuntimeFixture.command(fixture, "request.json")

    assert request["parameters"] == %{
             "method" => "GET",
             "path" => "/value",
             "confirmable" => true,
             "accept" => 50
           }

    assert NativeRuntimeFixture.command(fixture, "close.json")["operation"] == "close"
  end

  test "WCO-S06 WCO-I02 WCO-I05 Runtime Observe uses configured OSCORE custody and exact cancellation" do
    fixture = NativeRuntimeFixture.create(:observe)
    on_exit(fn -> NativeRuntimeFixture.remove(fixture) end)
    {:ok, profile} = CoAP.profile(:oscore)
    {:ok, thing} = thing(profile, fixture, {RuntimeCredentials, []}, security: fixture.security)
    {:ok, context} = Context.new(request_id: "oscore-observe")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(thing, "reading", context,
        id: :oscore,
        receiver: self(),
        restart: :temporary,
        max_queue_length: 1000,
        overflow: :stop
      )

    owner = start_supervised!(spec)

    assert_receive {:wotex_runtime, :oscore, {:ok, 42, metadata}}, 2_000

    assert metadata == %{
             code: 69,
             observe: 10,
             etag: nil,
             content_format: 50,
             max_age: 60
           }

    assert :ok = Subscription.stop(owner)

    observe = NativeRuntimeFixture.command(fixture, "observe.json")
    cancel = NativeRuntimeFixture.command(fixture, "cancel.json")
    open = NativeRuntimeFixture.command(fixture, "open.json")
    assert observe["parameters"]["path"] == "/value"
    assert observe["parameters"]["accept"] == 50
    assert cancel["parameters"]["subscription_id"] == observe["id"]
    assert cancel["parameters"]["generation"] == open["parameters"]["generation"]
  end

  test "WCO-C02 WCO-S06 Runtime security selects exactly one adapter credential" do
    fixture = NativeRuntimeFixture.create(:request)
    on_exit(fn -> NativeRuntimeFixture.remove(fixture) end)

    assert RuntimeSecurity.options(:coap, nil, []) == {:ok, [scheme: :coap]}

    assert RuntimeSecurity.options(:coap, fixture.security, []) ==
             {:ok, [scheme: :coap, security: fixture.security]}

    assert RuntimeSecurity.options(:coap, nil, security: fixture.security) ==
             {:ok, [scheme: :coap, security: fixture.security]}

    {:ok, psk} = Security.new(mode: :dtls_psk, identity: "runtime", key: <<0::128>>)

    for {scheme, immediate, config} <- [
          {:coap, fixture.security, [security: fixture.security]},
          {:coap, psk, []},
          {:coaps, fixture.security, []},
          {:coaps, nil, [security: fixture.security]},
          {:coap, nil, [security: :forged]}
        ] do
      assert {:error, %Error{code: :invalid_security}} =
               RuntimeSecurity.options(scheme, immediate, config)
    end

    assert {:error, %Error{code: :invalid_security}} = RuntimeSecurity.options(:http, nil, [])
  end

  test "WCO-C02 WCO-N02 Runtime OSCORE rejects a missing backend before process creation" do
    fixture = NativeRuntimeFixture.create(:request)
    on_exit(fn -> NativeRuntimeFixture.remove(fixture) end)
    {:ok, profile} = CoAP.profile(:oscore)

    {:ok, thing} =
      thing(profile, fixture, {Credentials, fixture.security}, native_backend: nil)

    {:ok, context} = Context.new(request_id: "missing-backend")
    assert {:error, error} = ConsumedThing.read_property(thing, "reading", context)
    assert error.details.cause.code == :unsupported_native_backend
    refute File.exists?(Path.join(fixture.store, "open.json"))
  end

  test "WCO-C02 WCO-N02 native Runtime verifies route normalization and aborts its exact adapter" do
    fixture = NativeRuntimeFixture.create(:observe)
    on_exit(fn -> NativeRuntimeFixture.remove(fixture) end)
    options = [scheme: :coap] ++ fixture.options
    deadline = System.monotonic_time(:millisecond) + 2_000
    generation = make_ref()

    {worker, monitor} =
      RuntimeNative.start(self(), generation, %{
        owner: self(),
        path: "/value",
        renew: true,
        max_queue_length: 1000,
        subscription_options: %{},
        connection_options: options,
        deadline: deadline
      })

    assert_receive {:runtime_session, ^generation, ^worker, session}, 2_000
    assert RuntimeNative.valid_session?(session, worker, self(), options)
    assert RuntimeNative.valid_session?(session, worker, self(), Keyword.delete(options, :scheme))
    duplicate_scheme = Enum.concat(options, scheme: :coap)
    refute RuntimeNative.valid_session?(session, worker, self(), duplicate_scheme)

    refute RuntimeNative.valid_session?(
             session,
             worker,
             self(),
             Keyword.put(options, :scheme, :coaps)
           )

    assert :ok = RuntimeNative.abort(session)
    assert :ok = NativeConnection.abort(session.pid)
    assert {:error, %Error{code: :invalid_session}} = NativeConnection.abort(self())
    assert {:error, %Error{code: :invalid_session}} = RuntimeNative.abort(%{pid: self()})
    assert {:error, %Error{code: :invalid_session}} = RuntimeNative.abort(:invalid)
    send(worker, {:subscribe, generation})
    assert_receive {:runtime_subscribed, ^generation, ^worker, {:error, %Error{}}}
    send(worker, {:halt, generation})
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
  end

  test "WCO-C02 WCO-N02 native public send admits only its complete-body ceiling" do
    fixture = NativeRuntimeFixture.create(:request)
    on_exit(fn -> NativeRuntimeFixture.remove(fixture) end)
    assert {:ok, session} = CoAP.connect([scheme: :coap] ++ fixture.options)
    request = %{method: :get, path: "/value"}

    assert {:error, %Error{code: :invalid_request}} =
             CoAP.send(session, request, block_size: 512)

    assert {:error, %Error{code: :invalid_request}} = CoAP.send(session, request, :invalid)
    assert {:ok, _} = CoAP.send(session, request, max_body_size: 32_768)
    assert :ok = CoAP.disconnect(session)
  end

  test "WCO-C02 WCO-S06 Runtime rejects datagram block tuning for the native SDK before I/O" do
    fixture = NativeRuntimeFixture.create(:request)
    on_exit(fn -> NativeRuntimeFixture.remove(fixture) end)
    {:ok, profile} = CoAP.profile(:oscore)

    for config <- [[block_size: 16], [max_blocks: 1], [max_body_size: 32_767]] do
      {:ok, thing} = thing(profile, fixture, {Credentials, fixture.security}, config)
      {:ok, context} = Context.new(request_id: "native-transfer-options")
      assert {:error, error} = ConsumedThing.read_property(thing, "reading", context)
      assert error.details.cause.code == :invalid_options
    end

    refute File.exists?(Path.join(fixture.store, "open.json"))
  end

  defp thing(profile, fixture, credentials, extra_config \\ []) do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "OSCORE Runtime fixture",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "reading" => %{
            "observable" => true,
            "forms" => [
              %{
                "href" => "coap://127.0.0.1:5683/value",
                "contentType" => "application/json",
                "op" => ["readproperty", "observeproperty", "unobserveproperty"]
              }
            ]
          }
        }
      })

    config =
      [timeout: 2_000, native_backend: fixture.backend]
      |> Keyword.merge(extra_config)

    ConsumedThing.new(td,
      profiles: [profile],
      transports: %{coap_oscore: {Transport, config}},
      credentials: credentials
    )
  end
end
