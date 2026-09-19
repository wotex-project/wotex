defmodule Wotex.OPCUA.RuntimeIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.OPCUA.{
    Address,
    Error,
    TestFailureTransport,
    TestNosecCredentials,
    TestRecordingTransport,
    TestScriptedClient,
    Transport
  }

  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, ExecutionContext, Request, Retry}

  @corpus "priv/fixtures/wotex-integration-v1.json"
  @corpus_sha256 :crypto.hash(:sha256, File.read!(@corpus)) |> Base.encode16(case: :lower)
  @cases @corpus
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("cases")
         |> Map.new(&{&1["id"], &1})
  @codes Map.new(
           ~w(deadline_exceeded connection_failed busy response_mismatch target_mismatch
              transport_exception native_process_terminated invalid_native_frame
              unsupported_type authentication_failed remote_error)a,
           &{Atom.to_string(&1), &1}
         )
  @effects %{"none" => :none, "unknown" => :unknown}
  @operations %{"readproperty" => :readproperty, "writeproperty" => :writeproperty}
  @href "opc.tcp://127.0.0.1:4840/server?id=ns%3D2%3Bi%3D42"

  @tag case: "WOP-I-F01", corpus_sha256: @corpus_sha256
  test "WOP-I02 WOP-I03 WOP-I06 WOP-I-F01 one-shot Runtime read through the public packages" do
    %{"input" => input, "expectation" => %{"value" => expected}} = Map.fetch!(@cases, "WOP-I-F01")
    assert {:ok, td} = Wotex.ThingDescription.from_map(input["thing_description"])
    assert "oneshot" == input["profile_mode"]
    profile = Wotex.OPCUA.profile()
    origin = System.monotonic_time(:millisecond)
    clock = input["clock"]
    options = input["transport_options"]
    assert %{"kind" => "client_return", "value" => reply} = input["peer_reply"]
    assert "scripted_client" == options["client"]

    transport = [
      client: TestScriptedClient,
      target: options["target"],
      timeout: options["timeout"],
      reply: reply,
      test: self()
    ]

    assert {:ok, consumed} =
             ConsumedThing.new(td,
               profiles: [profile],
               transports: %{BindingProfile.id(profile) => {TestRecordingTransport, transport}},
               credentials: {TestNosecCredentials, nil}
             )

    assert {:ok, context} =
             Context.new(
               request_id: input["request_id"],
               deadline: origin + clock["deadline"] - clock["start"]
             )

    assert {:ok, result} = ConsumedThing.read_property(consumed, input["affordance"], context)
    assert_received {:runtime_request, request}
    messages = scripted_messages([])

    observed = %{
      "profile_id" => Atom.to_string(BindingProfile.id(profile)),
      "resolved_href" => request.resolved_href,
      "command" =>
        Enum.find_value(messages, fn
          {:request, %{type: type, node_id: node}} ->
            %{"type" => Atom.to_string(type), "node_id" => Address.to_string(node)}

          _ ->
            nil
        end),
      "result" => %{
        "request_id" => result.request_id,
        "operation" => Atom.to_string(result.operation),
        "status" => Atom.to_string(result.status),
        "payload" => result.payload,
        "metadata" => Map.new(result.metadata, fn {key, value} -> {Atom.to_string(key), value} end)
      },
      "extension" => Wotex.Form.to_map(request.form)["example:extension"],
      "request_count" => Enum.count(messages, &match?({:request, _}, &1)),
      "owned_resources_after" =>
        Enum.count(messages, &(&1 == :connect)) - Enum.count(messages, &(&1 == :disconnect))
    }

    assert observed == expected
  end

  test "WOP-I02 profiles are static and a supplied contentType acquires nothing" do
    oneshot = Wotex.OPCUA.profile()
    assert {:ok, session} = Wotex.OPCUA.profile(:session)
    assert %BindingProfile{id: :opcua} = oneshot
    assert %BindingProfile{id: :opcua_session} = session

    for {profile, operations} <- [
          {oneshot, [:readproperty, :writeproperty]},
          {session, [:observeproperty, :readproperty, :unobserveproperty, :writeproperty]}
        ] do
      assert Enum.sort(profile.operations) == operations
      assert Enum.to_list(profile.schemes) == ["opc.tcp"]
      assert Enum.empty?(profile.media_types)
    end

    for mode <- [:oneshot_json, "session", nil] do
      assert {:error, %Error{code: :unsupported_profile}} = Wotex.OPCUA.profile(mode)
    end

    form = %{"href" => @href, "op" => ["readproperty"], "contentType" => "application/json"}

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "title" => "Media",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{"reading" => %{"forms" => [form]}}
      })

    transport = [
      client: TestScriptedClient,
      target: "opc.tcp://127.0.0.1:4840/server",
      reply: %{"type" => "Boolean", "value" => true, "status" => 0},
      test: self()
    ]

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [Wotex.OPCUA.profile()],
        transports: %{opcua: {TestRecordingTransport, transport}},
        credentials: {TestNosecCredentials, nil}
      )

    {:ok, context} = Context.new(request_id: "media")

    assert {:error, %Wotex.Runtime.Error{details: %{cause: %{code: :unsupported_content_type}}}} =
             ConsumedThing.read_property(consumed, "reading", context)

    assert scripted_messages([]) == []
  end

  test "WOP-I02 session profile projects persistent Read and Write results" do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "title" => "Session",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "reading" => %{
            "forms" => [
              %{
                "href" => @href,
                "op" => ["readproperty", "writeproperty"],
                "wotex:variantType" => "Double"
              }
            ]
          }
        }
      })

    {:ok, profile} = Wotex.OPCUA.profile(:session)
    {:ok, context} = Context.new(request_id: "session")

    for {reply, operation, expected} <- [
          {%{
             "has_value" => true,
             "status" => 0,
             "value" => %{"type" => "Double", "array" => false, "value" => 2.5},
             "source_timestamp" => 7
           }, :read, {:ok, 2.5, %{opcua_type: "Double", status: 0, source_timestamp: 7}}},
          {%{"status" => 0x4000_0000}, :write, {:ok, nil, %{status: 0x4000_0000}}},
          {%{"has_value" => true, "status" => 0x8034_0000}, :read, :bad_status}
        ] do
      transport = [
        client: TestScriptedClient,
        target: "opc.tcp://127.0.0.1:4840/server",
        reply: reply,
        test: self()
      ]

      {:ok, consumed} =
        ConsumedThing.new(td,
          profiles: [profile],
          transports: %{opcua_session: {TestRecordingTransport, transport}},
          credentials: {TestNosecCredentials, nil}
        )

      result =
        if operation == :read,
          do: ConsumedThing.read_property(consumed, "reading", context),
          else: ConsumedThing.write_property(consumed, "reading", 1.5, context)

      case expected do
        {:ok, payload, metadata} ->
          assert {:ok, %Wotex.Runtime.Result{payload: ^payload, metadata: ^metadata}} = result

        code ->
          assert {:error, %Wotex.Runtime.Error{details: %{cause: %{code: ^code}}}} = result
      end

      assert [:connect, {:request, _}, :disconnect] = scripted_messages([])
    end
  end

  test "WOP-S05 session profile reads and writes validated typed arrays" do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "title" => "Session arrays",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "samples" => %{"forms" => [%{"href" => @href, "op" => ["readproperty", "writeproperty"]}]}
        }
      })

    {:ok, profile} = Wotex.OPCUA.profile(:session)
    {:ok, context} = Context.new(request_id: "session-arrays")

    consumed = fn reply ->
      transport = [
        client: TestScriptedClient,
        target: "opc.tcp://127.0.0.1:4840/server",
        reply: reply,
        test: self()
      ]

      {:ok, consumed} =
        ConsumedThing.new(td,
          profiles: [profile],
          transports: %{opcua_session: {TestRecordingTransport, transport}},
          credentials: {TestNosecCredentials, nil}
        )

      consumed
    end

    matrix = %{
      "has_value" => true,
      "status" => 0,
      "value" => %{
        "type" => "Int32",
        "array" => true,
        "value" => [1, 2, 3, 4],
        "dimensions" => [2, 2]
      }
    }

    assert {:ok, %Wotex.Runtime.Result{payload: [1, 2, 3, 4], metadata: metadata}} =
             ConsumedThing.read_property(consumed.(matrix), "samples", context)

    assert metadata == %{opcua_type: "Int32", status: 0, opcua_dimensions: [2, 2]}
    assert [:connect, {:request, %{type: :read}}, :disconnect] = scripted_messages([])

    out_of_range = put_in(matrix["value"]["value"], [1, 2, 3, 2_147_483_648])

    assert {:error, %Wotex.Runtime.Error{details: %{cause: %{code: :unsupported_type}}}} =
             ConsumedThing.read_property(consumed.(out_of_range), "samples", context)

    assert [:connect, {:request, _}, :disconnect] = scripted_messages([])

    array = %{"type" => "Double", "array" => true, "value" => [-0.0, 2.5]}

    assert {:ok, %Wotex.Runtime.Result{payload: nil, metadata: %{status: 0}}} =
             ConsumedThing.write_property(consumed.(%{"status" => 0}), "samples", array, context)

    assert [:connect, {:request, %{type: :write, value: written}}, :disconnect] =
             scripted_messages([])

    assert written == %{type: "Double", array: true, value: [-0.0, 2.5]}

    # An element outside its declared type fails before any client I/O.
    invalid = %{"type" => "Byte", "array" => true, "value" => [255, 256]}

    assert {:error, %Wotex.Runtime.Error{details: %{cause: %{code: :variant_type_required}}}} =
             ConsumedThing.write_property(consumed.(%{"status" => 0}), "samples", invalid, context)

    assert [] = scripted_messages([])
  end

  for number <- 2..7 do
    id = "WOP-I-F0#{number}"

    @tag case: id, corpus_sha256: @corpus_sha256
    test "WOP-I04 #{id} native failure class reaches Runtime retry" do
      %{"input" => input, "expectation" => %{"value" => expected}} =
        Map.fetch!(@cases, unquote(id))

      assert project(input) == expected
    end
  end

  test "WOP-I04 unclassified, default mutation and admission budget cases" do
    for {input, expected} <- [
          {case_input("transport_exception", "none", "readproperty", attempt: 1, max_attempts: 2),
           %{"class" => nil, "retry_decision" => "stop"}},
          {case_input("remote_error", "none", "readproperty", attempt: 1, max_attempts: 2),
           %{"class" => nil, "retry_decision" => "stop"}},
          {case_input("deadline_exceeded", "none", "writeproperty", attempt: 1, max_attempts: 2),
           %{"class" => "timeout", "retry_decision" => "stop"}},
          {case_input("connection_failed", "unknown", "writeproperty",
             attempt: 1,
             max_attempts: 2,
             idempotent?: true
           ), %{"class" => "permanent", "retry_decision" => "stop"}},
          {case_input("busy", "none", "writeproperty",
             attempt: 1,
             max_attempts: 2,
             idempotent?: true
           ), %{"class" => "rate_limited", "retry_decision" => %{"retry" => 0}}},
          {case_input("busy", "none", "readproperty", attempt: 2, max_attempts: 2),
           %{"class" => "rate_limited", "retry_decision" => "stop"}},
          {case_input("invalid_native_frame", "none", "readproperty", attempt: 1, max_attempts: 2),
           %{"class" => "protocol", "retry_decision" => "stop"}},
          {case_input("native_process_terminated", "none", "readproperty",
             attempt: 1,
             max_attempts: 2
           ), %{"class" => "unavailable", "retry_decision" => %{"retry" => 0}}},
          {case_input("authentication_failed", "none", "readproperty", attempt: 1, max_attempts: 2),
           %{"class" => "permanent", "retry_decision" => "stop"}}
        ] do
      assert Map.take(project(input), ["class", "retry_decision"]) == expected
    end

    assert %Error{class: :unavailable, retryable: true} =
             Error.classify(Error.new(:connection_failed))

    assert %Error{class: :permanent, retryable: false} =
             Error.classify(%{Error.new(:busy) | effect: :unknown})
  end

  test "WOP-I04 production Transport failures carry the Runtime class" do
    {:ok, form} = Wotex.Form.new(%{"href" => @href})
    {:ok, context} = Context.new(request_id: "classified")
    execution = ExecutionContext.new(context, nil)

    request = %Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "reading",
      form: form,
      resolved_href: @href,
      profile: nil,
      request_id: "classified",
      deadline: nil,
      input: nil
    }

    config = [client: Wotex.OPCUA.TestClient, target: "opc.tcp://127.0.0.1:4840/server"]

    assert {:error, %Error{code: :target_mismatch, class: :permanent}} =
             Transport.request(request, execution, Keyword.put(config, :target, "other"))

    assert {:error, %Error{code: :transport_error, class: :unavailable}} =
             Transport.request(request, execution, Keyword.put(config, :mode, :error))

    assert {:error, %Error{code: :remote_error, effect: :unknown, class: :permanent}} =
             Transport.request(
               %{request | operation: :writeproperty, input: %{type: "Double", value: 1.0}},
               execution,
               Keyword.put(config, :mode, :typed)
             )

    assert {:error, %Error{code: :unsupported_operation, class: :permanent}} =
             Transport.subscribe(%{request | operation: :subscribeevent}, self(), execution, [])

    assert {:error, %Error{code: :invalid_subscription, class: nil}} =
             Transport.unsubscribe(:handle, request, execution, [])

    assert {:error, %Error{code: :deadline_exceeded, class: :timeout}} =
             Transport.decode_frame({:error, Error.new(:deadline_exceeded)}, request, [])
  end

  defp scripted_messages(messages) do
    receive do
      {:scripted, message} -> scripted_messages([message | messages])
      {:runtime_request, _} -> scripted_messages(messages)
    after
      0 -> Enum.reverse(messages)
    end
  end

  defp case_input(code, effect, operation, options),
    do: %{
      "native_error" => %{"code" => code, "effect" => effect},
      "wot_operation" => operation,
      "retry_options" => Map.new(options, fn {key, value} -> {Atom.to_string(key), value} end)
    }

  # Runs the named native failure through a Runtime Transport and ConsumedThing.
  defp project(%{"native_error" => native, "wot_operation" => name, "retry_options" => options}) do
    operation = Map.fetch!(@operations, name)

    failure = %{
      code: Map.fetch!(@codes, native["code"]),
      effect: Map.fetch!(@effects, native["effect"])
    }

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:opcua:retry",
        "title" => "Retry",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "reading" => %{
            "type" => "number",
            "forms" => [%{"href" => @href, "op" => [name]}]
          }
        }
      })

    {:ok, profile} =
      BindingProfile.new(id: :opcua_retry, schemes: ["opc.tcp"], operations: [operation])

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{opcua_retry: {TestFailureTransport, failure}},
        credentials: {TestNosecCredentials, nil}
      )

    {:ok, context} = Context.new(request_id: "retry-1")

    result =
      if operation == :readproperty,
        do: ConsumedThing.read_property(consumed, "reading", context),
        else: ConsumedThing.write_property(consumed, "reading", 1.5, context)

    assert {:error, %Wotex.Runtime.Error{details: %{cause: cause}} = error} = result

    retry_options =
      for {key, value} <- options,
          do:
            {Map.fetch!(
               %{
                 "attempt" => :attempt,
                 "max_attempts" => :max_attempts,
                 "delay" => :delay,
                 "idempotent?" => :idempotent?
               },
               key
             ), value}

    decision =
      case Retry.decision(operation, error, retry_options) do
        :stop -> "stop"
        {:retry, delay} -> %{"retry" => delay}
      end

    %{
      "class" => if(error.class, do: Atom.to_string(error.class)),
      "cause_code" => Atom.to_string(cause.code),
      "retained_native_effect" => Map.has_key?(cause, :effect),
      "retry_decision" => decision
    }
  end
end
