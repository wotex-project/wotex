defmodule Wotex.Modbus.RuntimeIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.{Form, Modbus}

  alias Wotex.Modbus.{
    Error,
    RuntimeCredentials,
    RuntimeFixture,
    RuntimeTransport,
    TestPeer,
    Transport
  }

  alias Wotex.Runtime.{
    BindingProfile,
    ConsumedThing,
    Context,
    ExecutionContext,
    Request,
    Result,
    Retry
  }

  alias Wotex.Runtime.Error, as: RuntimeError

  @fixture_path Path.expand("../../../docs/specs/fixtures/wotex-integration-v1.json", __DIR__)
  @fixture Jason.decode!(File.read!(@fixture_path))
  @digest Base.encode16(:crypto.hash(:sha256, File.read!(@fixture_path)), case: :lower)

  for fixture <- @fixture["cases"] do
    @tag fixture_sha256: @digest
    test "WMB-I04 WMB-I06 #{fixture["id"]} runs its input through actual core and Runtime APIs" do
      fixture = unquote(Macro.escape(fixture))
      actual = RuntimeFixture.run(Map.take(fixture, ["operation", "input"]))
      assert actual == fixture["expectation"]["value"]
    end
  end

  test "WMB-I01 WMB-I02 profiles are explicit pure declarations with no native streaming cells" do
    profile = Modbus.profile()
    assert {:ok, ^profile} = Modbus.profile(:tcp)
    assert BindingProfile.id(profile) == :modbus
    assert profile.schemes == MapSet.new(["modbus+tcp"])
    assert profile.operations == MapSet.new([:readproperty, :writeproperty, :invokeaction])
    assert profile.media_types == MapSet.new()

    for mode <- [:rtu, :tls, :tcp_secure, nil, "tcp", %{}] do
      assert {:error, %Error{code: :unsupported_profile, class: :permanent}} = Modbus.profile(mode)
    end

    for operation <- Wotex.Runtime.operations() -- [:readproperty, :writeproperty, :invokeaction],
        do: refute(BindingProfile.supports_operation?(profile, operation))
  end

  test "WMB-I02 WMB-I03 WMB-I06 Runtime chooses the compatible Form and resolves its exact relative route" do
    test = self()

    {peer, port} =
      TestPeer.start(fn _, unit, <<3, offset::16, quantity::16>> ->
        send(test, {:route, unit, offset, quantity})
        <<3, 2, 0, 0>>
      end)

    selected = %{
      "href" => "2/11?quantity=1",
      "modv:entity" => "HoldingRegister",
      "example:extension" => %{"keep" => [false, 0, nil]}
    }

    description =
      RuntimeFixture.td(selected)
      |> Map.put("base", "modbus+tcp://127.0.0.1:#{port}/")
      |> put_in(["properties", "reading", "forms"], [
        %{"href" => "https://example.invalid/"},
        selected
      ])

    consumed = RuntimeFixture.consumed(description, {RuntimeTransport, {:record, self(), []}})
    {:ok, context} = Context.new(request_id: "zero")

    assert {:ok, %Result{request_id: "zero", payload: [0], metadata: %{function: 3}, status: :ok}} =
             ConsumedThing.read_property(consumed, "reading", context)

    assert_receive {:route, 2, 10, 1}
    assert_receive {:runtime_request, request}
    assert request.resolved_href == "modbus+tcp://127.0.0.1:#{port}/2/11?quantity=1"
    assert Form.to_map(request.form) == selected
    assert_receive {:runtime_resources, []}
    assert :ok = Task.await(peer)
  end

  test "WMB-I02 WMB-I03 all declared write and Action cells require correlated acknowledgments" do
    for operation <- [:writeproperty, :invokeaction],
        {function, name, input, quantity} <- [
          {5, "writeSingleCoil", false, 1},
          {6, "writeSingleHoldingRegister", 0, 1},
          {15, "writeMultipleCoils", [false, true], 2},
          {16, "writeMultipleHoldingRegisters", [0, 42], 2}
        ] do
      test = self()

      {peer, port} =
        TestPeer.start(fn _, _, pdu ->
          send(test, {:write, pdu})

          case pdu do
            <<f, offset::16, count::16, _::binary>> when f in [15, 16] ->
              <<f, offset::16, count::16>>

            echo ->
              echo
          end
        end)

      form = %{
        "href" => "modbus+tcp://127.0.0.1:#{port}/1/1?quantity=#{quantity}",
        "modv:function" => name
      }

      td = RuntimeFixture.td(form)

      td =
        if operation == :invokeaction,
          do: Map.put(Map.delete(td, "properties"), "actions", %{"write" => %{"forms" => [form]}}),
          else: td

      consumed = RuntimeFixture.consumed(td, {Transport, []})
      {:ok, context} = Context.new(request_id: "ack")

      result =
        case operation do
          :writeproperty -> ConsumedThing.write_property(consumed, "reading", input, context)
          :invokeaction -> ConsumedThing.invoke_action(consumed, "write", input, context)
        end

      assert {:ok,
              %Result{
                operation: ^operation,
                request_id: "ack",
                status: :ok,
                payload: :written,
                metadata: %{function: ^function}
              }} = result

      assert_receive {:write, <<^function, _::binary>>}
      assert :ok = Task.await(peer)
    end
  end

  test "WMB-I03 WMB-I04 unsupported media, route, conversion, credentials and input acquire no socket" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    form = %{"href" => "modbus+tcp://127.0.0.1:#{port}/1/1", "modv:entity" => "HoldingRegister"}

    for {changes, config, credential, expected} <- [
          {%{"contentType" => "application/json"}, [], nil, :unsupported_content_type},
          {%{"href" => "modbus+tcp://127.0.0.1:#{port}/1//1"}, [], nil, :invalid_href},
          {%{"modv:type" => "xsd:float"}, [], nil, :quantity_mismatch},
          {%{}, [security: :tls], nil, :unsupported_security},
          {%{}, [], "private-test-credential", :invalid_transport_context},
          {%{}, [timeout: 0], nil, :invalid_timeout},
          {%{}, [:bad | :tail], nil, :invalid_options}
        ] do
      td = RuntimeFixture.td(Map.merge(form, changes))
      consumed = RuntimeFixture.consumed(td, {Transport, config}, credential)
      {:ok, context} = Context.new(request_id: "reject")

      assert {:error,
              %RuntimeError{class: :permanent, details: %{cause: %{code: ^expected}}} = error} =
               ConsumedThing.read_property(consumed, "reading", context)

      refute inspect(error) =~ "private-test-credential"
    end

    consumed = RuntimeFixture.consumed(RuntimeFixture.td(form), {Transport, []})
    {:ok, context} = Context.new(request_id: "invalid-value")

    assert {:error, %RuntimeError{class: :permanent}} =
             ConsumedThing.write_property(consumed, "reading", nil, context)

    assert {:error, :timeout} = :gen_tcp.accept(listener, 20)
    :ok = :gen_tcp.close(listener)
  end

  test "WMB-I03 WMB-I04 selected security definitions are enforced by the credential port" do
    form = %{"href" => "modbus+tcp://127.0.0.1/1/1", "modv:entity" => "HoldingRegister"}

    td =
      RuntimeFixture.td(form)
      |> Map.put("securityDefinitions", %{"auth" => %{"scheme" => "basic"}})
      |> Map.put("security", ["auth"])

    consumed = RuntimeFixture.consumed(td, {RuntimeTransport, {:record, self(), []}})
    {:ok, context} = Context.new(request_id: "security")

    assert {:error,
            %RuntimeError{
              phase: :credentials,
              class: :permanent,
              details: %{cause: %{code: :unsupported_security}}
            }} =
             ConsumedThing.read_property(consumed, "reading", context)

    refute_received {:runtime_request, _}

    assert {:error, %Error{code: :unsupported_security}} =
             RuntimeCredentials.resolve(
               %{names: ["none"], definitions: %{"none" => %{"scheme" => "basic"}}},
               nil,
               nil,
               nil
             )
  end

  test "WMB-I02 Action Forms require explicit valid mutation functions" do
    form = %{"href" => "modbus+tcp://127.0.0.1/1/1", "modv:entity" => "HoldingRegister"}

    for changes <- [
          %{},
          %{"modv:function" => "readHoldingRegisters"},
          %{"modv:function" => "unknown"}
        ] do
      td =
        RuntimeFixture.td(form)
        |> Map.delete("properties")
        |> Map.put("actions", %{"write" => %{"forms" => [Map.merge(form, changes)]}})

      consumed = RuntimeFixture.consumed(td, {Transport, []})
      {:ok, context} = Context.new(request_id: "action")

      assert {:error,
              %RuntimeError{class: :permanent, details: %{cause: %{code: :missing_function}}}} =
               ConsumedThing.invoke_action(consumed, "write", 42, context)
    end
  end

  test "WMB-I03 conflicting Action entity and explicit function cannot choose a different mutation" do
    form = %{
      "href" => "modbus+tcp://127.0.0.1/1/1",
      "modv:entity" => "HoldingRegister",
      "modv:function" => "writeSingleCoil"
    }

    assert {:error, %Error{code: :operation_mismatch}} =
             Wotex.Modbus.Mapping.command(form, :invokeaction, 42)
  end

  test "WMB-I03 native false is preserved and an absent representation cannot become null success" do
    for {pdu, expected} <- [{<<1, 1, 0>>, {:ok, [false]}}, {<<1, 0>>, {:error, :protocol}}] do
      {peer, port} = TestPeer.start(fn _, _, _ -> pdu end)
      form = %{"href" => "modbus+tcp://127.0.0.1:#{port}/1/1", "modv:entity" => "Coil"}
      consumed = RuntimeFixture.consumed(RuntimeFixture.td(form), {Transport, []})
      {:ok, context} = Context.new(request_id: "false")

      case expected do
        {:ok, value} ->
          assert {:ok, %Result{payload: ^value}} =
                   ConsumedThing.read_property(consumed, "reading", context)

        {:error, class} ->
          assert {:error, %RuntimeError{class: ^class}} =
                   ConsumedThing.read_property(consumed, "reading", context)
      end

      assert :ok = Task.await(peer)
    end
  end

  test "WMB-I04 expired Runtime budgets fail before acquisition and preserve mutation effect none" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    form = %{"href" => "modbus+tcp://127.0.0.1:#{port}/1/1", "modv:entity" => "HoldingRegister"}
    consumed = RuntimeFixture.consumed(RuntimeFixture.td(form), {Transport, []})

    for deadline <- [System.monotonic_time(:millisecond) - 1, DateTime.add(DateTime.utc_now(), -1)] do
      {:ok, context} = Context.new(request_id: "expired", deadline: deadline)

      assert {:error, %RuntimeError{class: :timeout} = read_error} =
               ConsumedThing.read_property(consumed, "reading", context)

      assert {:retry, 0} = Retry.decision(:readproperty, read_error, attempt: 1, max_attempts: 2)

      assert {:error, %RuntimeError{class: :timeout} = write_error} =
               ConsumedThing.write_property(consumed, "reading", 42, context)

      assert :stop = Retry.decision(:writeproperty, write_error, attempt: 1, max_attempts: 2)
    end

    assert {:error, :timeout} = :gen_tcp.accept(listener, 20)
    :ok = :gen_tcp.close(listener)
  end

  test "WMB-I04 actual transmitted write timeout remains non-retryable through Runtime" do
    {peer, port} =
      TestPeer.start(fn _, _, _ ->
        receive do
        after
          100 -> <<6, 0, 0, 0, 42>>
        end
      end)

    td =
      RuntimeFixture.td(%{
        "href" => "modbus+tcp://127.0.0.1:#{port}/1/1",
        "modv:entity" => "HoldingRegister"
      })

    consumed = RuntimeFixture.consumed(td, {Transport, [timeout: 20]})
    {:ok, context} = Context.new(request_id: "uncertain")

    assert {:error, %RuntimeError{} = error} =
             ConsumedThing.write_property(consumed, "reading", 42, context)

    assert error.class == :permanent
    assert error.details.cause.code == :transport_error

    assert :stop =
             Retry.decision(:writeproperty, error, attempt: 1, max_attempts: 2, idempotent?: true)

    refute Map.has_key?(error.details.cause, :effect)
    assert :ok = Task.await(peer)
  end

  test "WMB-I04 complete finite class table and unclassified errors retain default mutation restrictions" do
    for {code, details, effect, expected} <- [
          {:deadline_exceeded, %{}, :none, :timeout},
          {:transport_error, %{reason: :timeout}, :none, :timeout},
          {:transport_error, %{reason: :closed}, :none, :unavailable},
          {:connection_closed, %{}, :none, :unavailable},
          {:busy, %{}, :none, :rate_limited},
          {:invalid_response, %{}, :none, :protocol},
          {:invalid_form, %{}, :none, :permanent},
          {:unclassified_fixture_failure, %{}, :none, nil},
          {:transport_error, %{reason: :closed}, :unknown, :permanent}
        ] do
      native = Error.with_effect(Error.new(code, nil, details), effect)
      form = %{"href" => "modbus+tcp://127.0.0.1/1/1", "modv:entity" => "HoldingRegister"}

      consumed =
        RuntimeFixture.consumed(RuntimeFixture.td(form), {RuntimeTransport, {:fault, native}})

      {:ok, context} = Context.new(request_id: "failure")

      assert {:error, %RuntimeError{class: ^expected} = error} =
               ConsumedThing.read_property(consumed, "reading", context)

      transient = expected in [:timeout, :unavailable, :rate_limited]

      assert Retry.decision(:readproperty, error, attempt: 1, max_attempts: 2) ==
               if(transient, do: {:retry, 0}, else: :stop)

      assert {:error, %RuntimeError{class: ^expected} = mutation_error} =
               ConsumedThing.write_property(consumed, "reading", 42, context)

      assert :stop = Retry.decision(:writeproperty, mutation_error, attempt: 1, max_attempts: 2)
      if effect == :unknown, do: refute(native.retryable)
    end
  end

  test "WMB-I03 WMB-I06 Runtime preserves explicit false/zero/null and rejects misattributed Results" do
    form = %{"href" => "modbus+tcp://127.0.0.1/1/1", "modv:entity" => "HoldingRegister"}
    {:ok, context} = Context.new(request_id: "identity")

    for value <- [false, 0, nil, "", []] do
      consumed =
        RuntimeFixture.consumed(RuntimeFixture.td(form), {RuntimeTransport, {:result, value, []}})

      assert {:ok, %Result{request_id: "identity", payload: ^value}} =
               ConsumedThing.read_property(consumed, "reading", context)
    end

    for change <- [[request_id: "other"], [operation: :writeproperty]] do
      consumed =
        RuntimeFixture.consumed(RuntimeFixture.td(form), {RuntimeTransport, {:result, 42, change}})

      assert {:error, %RuntimeError{code: :mismatched_transport_result}} =
               ConsumedThing.read_property(consumed, "reading", context)
    end
  end

  test "WMB-I05 no-stream profile rejects actual Runtime observation specs without native acquisition" do
    form = %{
      "href" => "modbus+tcp://127.0.0.1/1/1",
      "modv:entity" => "HoldingRegister",
      "op" => ["observeproperty", "unobserveproperty"]
    }

    td = RuntimeFixture.td(form) |> put_in(["properties", "reading", "observable"], true)
    consumed = RuntimeFixture.consumed(td, {RuntimeTransport, {:record, self(), []}})
    {:ok, context} = Context.new(request_id: "stream")

    assert {:error, %RuntimeError{phase: :selection}} =
             ConsumedThing.observation_child_spec(consumed, "reading", context,
               id: :observation,
               receiver: self(),
               max_queue_length: 1000,
               overflow: :stop,
               restart: :temporary
             )

    assert {:error, %Error{code: :not_supported}} = Transport.subscribe(nil, nil, nil, self())
    assert {:error, %Error{code: :not_supported}} = Transport.unsubscribe(nil, nil, nil, nil)
    refute_received {:runtime_request, _}
  end

  test "WMB-I03 direct Transport validates selected context, profile, identity and Form before I/O" do
    {:ok, form} =
      Form.new(%{"href" => "modbus+tcp://127.0.0.1/1/1", "modv:entity" => "HoldingRegister"})

    {:ok, context} = Context.new(request_id: "shape")
    execution = ExecutionContext.new(context, nil)

    request = %Request{
      request_id: "shape",
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "reading",
      form: form,
      resolved_href: Form.href(form),
      profile: Modbus.profile(),
      deadline: nil,
      input: nil
    }

    for changes <- [
          %{profile: nil},
          %{affordance_type: :action},
          %{resolved_href: nil},
          %{request_id: ""},
          %{form: nil},
          %{form: %Form{value: %{}}}
        ] do
      assert {:error, %Error{class: :permanent}} =
               Transport.request(struct!(request, changes), execution, [])
    end

    for deadline <- [System.monotonic_time(:millisecond) - 1, DateTime.add(DateTime.utc_now(), -1)] do
      assert {:error, %Error{code: :deadline_exceeded, class: :timeout}} =
               Transport.request(%{request | deadline: deadline}, execution, [])
    end
  end
end
