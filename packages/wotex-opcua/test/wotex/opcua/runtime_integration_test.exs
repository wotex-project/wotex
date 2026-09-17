defmodule Wotex.OPCUA.RuntimeIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.OPCUA.{Error, TestFailureTransport, TestNosecCredentials, Transport}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, ExecutionContext, Request, Retry}

  @corpus "docs/specs/fixtures/wotex-integration-v1.json"
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
