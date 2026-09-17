defmodule Wotex.Matter.RuntimeIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.Error, as: MatterError
  alias Wotex.Matter.{RuntimeClient, RuntimeCredentials, RuntimeResultTransport, Transport}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result, Retry}
  alias Wotex.Runtime.Error, as: RuntimeError

  @fixture "priv/fixtures/wotex-integration-v1.json"
  @context "https://www.w3.org/2022/wot/td/v1.1"
  @attribute_path %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 6, member: 0}
  @write_path %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 513, member: 17}
  @event_path %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 57, member: 3}
  @write_value %{tag: :anonymous, type: :i16, value: 2_150}
  @attribute_value %{tag: :anonymous, type: :boolean, value: false}
  @command_value %{tag: :anonymous, type: :structure, value: []}
  @event_value %{
    tag: :anonymous,
    type: :structure,
    value: [%{tag: {:context, 0}, type: :boolean, value: true}]
  }

  test "WMA-I01/I02 profile factories are pure and declare only implemented operations" do
    baseline = Matter.profile()
    assert BindingProfile.id(baseline) == :matter
    assert baseline.schemes == MapSet.new(["matter"])
    assert baseline.media_types == MapSet.new()

    assert baseline.operations ==
             MapSet.new([:readproperty, :writeproperty, :invokeaction])

    assert {:ok, controller} = Matter.profile(:controller)
    assert BindingProfile.id(controller) == :matter_controller
    assert controller.schemes == MapSet.new(["matter"])
    assert controller.media_types == MapSet.new()

    assert controller.operations ==
             MapSet.new([
               :readproperty,
               :writeproperty,
               :invokeaction,
               :observeproperty,
               :unobserveproperty,
               :subscribeevent,
               :unsubscribeevent
             ])

    assert {:ok, selected_baseline} = Matter.profile(:oneshot)
    assert selected_baseline == baseline

    for mode <- [:native, :commissioning, nil, "controller"] do
      assert {:error, %MatterError{code: :unsupported_profile, class: :permanent}} =
               Matter.profile(mode)
    end

    refute BindingProfile.supports_operation?(baseline, :readallproperties)
    refute BindingProfile.supports_operation?(controller, :commission_on_network)
    refute_receive {:matter_connect, _}
  end

  test "WMA-I03/I06 WMA-I-F01 and WMA-I-F08 execute through public consumer APIs" do
    fixture = fixture!()

    for id <- ["WMA-I-F01", "WMA-I-F08"] do
      test_case = case!(fixture, id)
      assert run_runtime_read(test_case["input"]) == test_case["expectation"]["value"]
    end
  end

  test "WMA-I04/I06 WMA-I-F02 through WMA-I-F07 retain only classified Runtime causes" do
    fixture = fixture!()

    for number <- 2..7 do
      id = "WMA-I-F#{String.pad_leading(Integer.to_string(number), 2, "0")}"
      test_case = case!(fixture, id)
      assert run_error_projection(test_case["input"]) == test_case["expectation"]["value"]
    end
  end

  test "WMA-I03 rejects content type, route, security and unsupported operations before protocol acquisition" do
    context = context("negative")

    content_type_td =
      td(%{
        "properties" => %{
          "reading" => %{
            "readOnly" => true,
            "forms" => [
              %{
                "href" => href(@attribute_path),
                "op" => "readproperty",
                "contentType" => "application/json"
              }
            ]
          }
        }
      })

    assert {:ok, content_type_consumed} =
             consumed(content_type_td, Matter.profile(), response: false)

    assert {:error,
            %RuntimeError{
              code: :transport_request_failed,
              class: :permanent,
              details: %{cause: %{code: :unsupported_content_type}}
            }} = ConsumedThing.read_property(content_type_consumed, "reading", context)

    assert_receive {:matter_credentials, _, "negative"}
    refute_receive {:matter_connect, _}

    wrong_route_td =
      td(%{
        "properties" => %{
          "reading" => %{
            "readOnly" => true,
            "forms" => [%{"href" => "matter://1/1234/1/6", "op" => "readproperty"}]
          }
        }
      })

    assert {:ok, wrong_route_consumed} = consumed(wrong_route_td, Matter.profile(), response: false)

    assert {:error, %RuntimeError{class: :permanent}} =
             ConsumedThing.read_property(wrong_route_consumed, "reading", context)

    assert_receive {:matter_credentials, _, "negative"}
    refute_receive {:matter_connect, _}

    secured_td =
      td(
        %{
          "securityDefinitions" => %{"token" => %{"scheme" => "bearer"}},
          "security" => ["token"],
          "properties" => %{
            "reading" => %{
              "readOnly" => true,
              "forms" => [%{"href" => href(@attribute_path), "op" => "readproperty"}]
            }
          }
        },
        security: false
      )

    assert {:ok, secured_consumed} = consumed(secured_td, Matter.profile(), response: false)

    assert {:error,
            %RuntimeError{
              code: :credential_resolution_failed,
              class: :permanent,
              details: %{cause: %{code: :unsupported_security}}
            }} = ConsumedThing.read_property(secured_consumed, "reading", context)

    refute_receive {:matter_connect, _}

    aggregate_td =
      td(%{
        "forms" => [%{"href" => href(@attribute_path), "op" => "readallproperties"}]
      })

    assert {:ok, aggregate_consumed} = consumed(aggregate_td, Matter.profile(), response: false)

    assert {:error, %RuntimeError{code: :compatible_form_not_found}} =
             ConsumedThing.read_all_properties(aggregate_consumed, context)

    refute_receive {:matter_credentials, _, _}
    refute_receive {:matter_connect, _}

    malformed_td =
      td(%{
        "properties" => %{
          "level" => %{
            "writeOnly" => true,
            "forms" => [%{"href" => href(@write_path), "op" => "writeproperty"}]
          }
        }
      })

    {:ok, controller} = Matter.profile(:controller)
    assert {:ok, malformed} = consumed(malformed_td, controller, response: :unused)

    assert {:error,
            %RuntimeError{
              class: :permanent,
              details: %{cause: %{code: :invalid_tlv}}
            }} =
             ConsumedThing.write_property(malformed, "level", %{value: self()}, context)

    assert_receive {:matter_credentials, _, "negative"}
    refute_receive {:matter_connect, _}

    for input <- [self(), :binary.copy("x", 131_072)] do
      assert {:ok, malformed_baseline} =
               consumed(malformed_td, Matter.profile(), response: :unused)

      assert {:error,
              %RuntimeError{
                class: :permanent,
                details: %{cause: %{code: :invalid_value}}
              }} =
               ConsumedThing.write_property(malformed_baseline, "level", input, context)

      assert_receive {:matter_credentials, _, "negative"}
      refute_receive {:matter_connect, _}
    end

    unsupported_td =
      td(%{
        "properties" => %{
          "unknown" => %{
            "readOnly" => true,
            "forms" => [
              %{
                "href" => href(%{@attribute_path | cluster: 7}),
                "op" => "readproperty"
              }
            ]
          }
        }
      })

    assert {:ok, unsupported} = consumed(unsupported_td, controller, response: :unused)

    assert {:error,
            %RuntimeError{
              class: :permanent,
              details: %{cause: %{code: :unsupported_schema}}
            }} = ConsumedThing.read_property(unsupported, "unknown", context)

    assert_receive {:matter_credentials, _, "negative"}
    refute_receive {:matter_connect, _}
  end

  test "WMA-I03 public one-shot results preserve false, zero and explicit null" do
    document =
      td(%{
        "properties" => %{
          "reading" => %{
            "readOnly" => true,
            "forms" => [%{"href" => href(@attribute_path), "op" => "readproperty"}]
          }
        }
      })

    for {value, id} <- [{false, "false"}, {0, "zero"}, {nil, "null"}, {"", "empty"}, {[], "list"}] do
      assert {:ok, consumed} = consumed(document, Matter.profile(), response: value)

      assert {:ok, %Result{payload: ^value, status: :ok}} =
               ConsumedThing.read_property(consumed, "reading", context(id))

      assert_receive {:matter_credentials, _, ^id}
      assert_receive {:matter_connect, _}
      assert_receive {:matter_request, %{type: :read}, _}
      assert_receive :disconnected
    end
  end

  test "WMA-I03/I06 profile precedence and Form choice reach public write and Action cells" do
    document =
      td(%{
        "properties" => %{
          "level" => %{
            "writeOnly" => true,
            "forms" => [
              %{"href" => "https://example.invalid/level", "op" => "writeproperty"},
              %{"href" => href(@write_path), "op" => "writeproperty"}
            ]
          }
        },
        "actions" => %{
          "switch" => %{
            "forms" => [
              %{"href" => "https://example.invalid/switch", "op" => "invokeaction"},
              %{"href" => href(@attribute_path), "op" => "invokeaction"}
            ]
          }
        }
      })

    {:ok, controller} = Matter.profile(:controller)
    baseline = Matter.profile()

    assert {:ok, write_consumed} =
             consumed_with_profiles(
               document,
               [controller, baseline],
               %{path: @write_path, status: 0}
             )

    assert {:ok,
            %Result{
              operation: :writeproperty,
              payload: :written,
              metadata: %{matter_kind: :attribute, path: @write_path, status: 0}
            }} =
             ConsumedThing.write_property(
               write_consumed,
               "level",
               @write_value,
               context("profile-write")
             )

    assert_receive {:matter_credentials, form, "profile-write"}
    assert form["href"] == href(@write_path)
    assert_receive {:matter_connect, _}

    assert_receive {:matter_request, %{type: :write, value: @write_value}, timeout}
                   when timeout > 0

    assert_receive :disconnected

    response = %{path: nil, value: nil, status: 0}

    assert {:ok, invoke_consumed} =
             consumed_with_profiles(document, [controller, baseline], response)

    assert {:ok,
            %Result{
              operation: :invokeaction,
              payload: nil,
              metadata: %{
                matter_kind: :command,
                path: @attribute_path,
                response_path: nil,
                status: 0
              }
            }} =
             ConsumedThing.invoke_action(
               invoke_consumed,
               "switch",
               @command_value,
               context("profile-invoke")
             )

    assert_receive {:matter_credentials, form, "profile-invoke"}
    assert form["href"] == href(@attribute_path)
    assert_receive {:matter_connect, _}

    assert_receive {:matter_request, %{type: :invoke, value: @command_value}, timeout}
                   when timeout > 0

    assert_receive :disconnected

    assert {:ok, baseline_consumed} =
             consumed_with_profiles(document, [baseline, controller], :acknowledged)

    assert {:ok, %Result{payload: :acknowledged, metadata: %{}}} =
             ConsumedThing.write_property(
               baseline_consumed,
               "level",
               @write_value,
               context("baseline-write")
             )

    assert_receive {:matter_credentials, _, "baseline-write"}
    assert_receive {:matter_connect, _}
    assert_receive {:matter_request, %{type: :write}, _}
    assert_receive :disconnected

    assert {:ok, baseline_action} =
             consumed_with_profiles(document, [baseline, controller], :baseline_action)

    assert {:ok, %Result{payload: :baseline_action, metadata: %{}}} =
             ConsumedThing.invoke_action(
               baseline_action,
               "switch",
               @command_value,
               context("baseline-invoke")
             )

    assert_receive {:matter_credentials, _, "baseline-invoke"}
    assert_receive {:matter_connect, _}
    assert_receive {:matter_request, %{type: :invoke}, _}
    assert_receive :disconnected
  end

  test "WMA-I04/I06 expired deadlines and malformed transport results stay public and bounded" do
    document =
      td(%{
        "properties" => %{
          "reading" => %{
            "readOnly" => true,
            "forms" => [%{"href" => href(@attribute_path), "op" => "readproperty"}]
          }
        }
      })

    assert {:ok, expired} = consumed(document, Matter.profile(), response: false)
    deadline = System.monotonic_time(:millisecond) - 1

    assert {:error,
            %RuntimeError{
              code: :transport_request_failed,
              class: :timeout,
              details: %{cause: %{code: :deadline_exceeded, class: :timeout}}
            } = error} =
             ConsumedThing.read_property(expired, "reading", context("expired", deadline))

    assert {:retry, 0} =
             Retry.decision(:readproperty, error, attempt: 1, max_attempts: 2, delay: 0)

    assert_receive {:matter_credentials, _, "expired"}
    refute_receive {:matter_connect, _}

    assert {:ok, maximum} = result_consumed(document, :maximum_metadata)

    assert {:ok, %Result{metadata: metadata}} =
             ConsumedThing.read_property(maximum, "reading", context("result-maximum"))

    assert map_size(metadata) == Wotex.Runtime.Limits.maximum(:metadata_entries)
    assert_receive {:matter_credentials, _, "result-maximum"}
    assert_receive {:result_transport_request, "result-maximum", :readproperty}

    for {mode, code} <- [
          wrong_identity: :mismatched_transport_result,
          wrong_operation: :mismatched_transport_result,
          oversized_metadata: :result_metadata_limit_exceeded
        ] do
      assert {:ok, malformed} = result_consumed(document, mode)
      request_id = "result-#{mode}"

      assert {:error, %RuntimeError{code: ^code} = error} =
               ConsumedThing.read_property(malformed, "reading", context(request_id))

      assert :stop =
               Retry.decision(:readproperty, error,
                 attempt: 1,
                 max_attempts: 2,
                 delay: 0
               )

      assert_receive {:matter_credentials, _, ^request_id}
      assert_receive {:result_transport_request, ^request_id, :readproperty}
    end
  end

  test "WMA-I04 unclassified failures and mutation defaults remain non-retryable" do
    assert MatterError.new(:unclassified).class == nil

    assert :stop =
             Retry.decision(
               :readproperty,
               %RuntimeError{
                 code: :failed,
                 phase: :transport,
                 message: "failed",
                 class: nil
               },
               attempt: 1,
               max_attempts: 2
             )

    assert :stop =
             Retry.decision(:writeproperty, :timeout,
               attempt: 1,
               max_attempts: 2,
               delay: 0
             )

    unknown = MatterError.new(:deadline_exceeded) |> MatterError.with_effect(:unknown)
    assert unknown.class == :permanent
    refute unknown.retryable
  end

  test "WMA-I05 public Property observation retains reports and original cancellation route" do
    document = stream_td()
    {:ok, profile} = Matter.profile(:controller)
    assert {:ok, consumed} = consumed(document, profile, response: :unused)

    assert {:ok, child_spec} =
             ConsumedThing.observation_child_spec(
               consumed,
               "reading",
               context("observation"),
               id: :matter_observation,
               receiver: self(),
               restart: :temporary,
               max_queue_length: 1_000,
               overflow: :stop
             )

    pid = start_supervised!(child_spec)
    assert_receive {:matter_credentials, start_form, "observation"}
    assert start_form["op"] == "observeproperty"
    assert_receive {:matter_connect, _}
    assert_receive {:matter_subscribe, relay, receiver, native, _, reference}
    assert receiver == relay
    assert native.paths == [@attribute_path]
    assert native.resubscribe == false

    first = %{kind: :attribute, path: @attribute_path, data_version: 7, initial: true}
    second = %{first | data_version: 8, initial: false}
    send(relay, {:wotex_matter, reference, {:ok, @attribute_value, first}})
    send(relay, {:wotex_matter, reference, {:ok, @attribute_value, second}})

    assert_receive {:wotex_runtime, :matter_observation,
                    {:ok, @attribute_value, %{data_version: 7, status: 0}}}

    assert_receive {:wotex_runtime, :matter_observation,
                    {:ok, @attribute_value, %{data_version: 8, status: 0}}}

    send(relay, {:wotex_matter, make_ref(), {:ok, @attribute_value, second}})
    send(pid, {:wotex_transport_frame, {:value, @attribute_value, %{data_version: 9}}})
    refute_receive {:wotex_runtime, :matter_observation, {:ok, _, %{data_version: 9}}}, 20

    assert :ok = Wotex.Runtime.Subscription.stop(pid)
    assert_receive {:matter_credentials, stop_form, "observation"}
    assert stop_form["op"] == "unobserveproperty"
    assert stop_form["href"] == href(%{@attribute_path | fabric_id: 2, node_id: 999})
    assert_receive {:matter_unsubscribe, ^relay, subscription, _}
    assert subscription.reference == reference
    assert_receive :disconnected
  end

  test "WMA-I05 public Event subscription preserves identity and terminal loss cleanup" do
    document = stream_td()
    {:ok, profile} = Matter.profile(:controller)
    assert {:ok, consumed} = consumed(document, profile, response: :unused)

    assert {:ok, child_spec} =
             ConsumedThing.event_subscription_child_spec(
               consumed,
               "reachable",
               context("event"),
               id: :matter_event,
               receiver: self(),
               restart: :temporary,
               max_queue_length: 1_000,
               overflow: :stop
             )

    pid = start_supervised!(child_spec)
    monitor = Process.monitor(pid)
    assert_receive {:matter_credentials, _, "event"}
    assert_receive {:matter_connect, _}
    assert_receive {:matter_subscribe, relay, receiver, native, _, reference}
    assert receiver == relay
    assert native.paths == [@event_path]

    metadata = %{
      kind: :event,
      path: @event_path,
      event_number: 42,
      priority: 2,
      timestamp: %{kind: :system, value: 1_000},
      initial: true
    }

    send(relay, {:wotex_matter, reference, {:ok, @event_value, metadata}})

    assert_receive {:wotex_runtime, :matter_event,
                    {:ok, @event_value,
                     %{
                       matter_kind: :event,
                       path: @event_path,
                       status: 0,
                       event_number: 42,
                       priority: 2,
                       timestamp: %{kind: :system, value: 1_000}
                     }}}

    send(relay, {:wotex_matter, reference, {:error, MatterError.new(:subscription_failed)}})

    assert_receive {:wotex_runtime, :matter_event, {:error, %RuntimeError{class: :unavailable}}}

    assert_receive {:matter_unsubscribe, ^relay, _, _}
    assert_receive :disconnected
    assert_receive {:wotex_runtime, :matter_event, {:status, :session_lost}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :session_lost}}
  end

  test "WMA-I05 failed open, receiver death and receiver overflow release only owned resources" do
    document = stream_td()
    {:ok, profile} = Matter.profile(:controller)

    assert {:ok, failed} =
             consumed(document, profile,
               connect_error: MatterError.new(:connection_failed),
               response: :unused
             )

    assert {:ok, failed_spec} =
             ConsumedThing.observation_child_spec(failed, "reading", context("failed-open"),
               id: :failed_open,
               receiver: self(),
               restart: :temporary
             )

    failed_pid = start_supervised!(failed_spec)
    failed_monitor = Process.monitor(failed_pid)
    assert_receive {:matter_credentials, _, "failed-open"}
    assert_receive {:matter_connect, _}
    assert_receive {:wotex_runtime, :failed_open, {:error, %RuntimeError{class: :unavailable}}}
    assert_receive {:DOWN, ^failed_monitor, :process, ^failed_pid, _}
    refute_receive {:matter_subscribe, _, _, _, _, _}
    refute_receive :disconnected

    parent = self()
    receiver = spawn(fn -> receive do: (_ -> :ok) end)
    assert {:ok, owned} = consumed(document, profile, response: :unused)

    assert {:ok, owned_spec} =
             ConsumedThing.observation_child_spec(owned, "reading", context("receiver-death"),
               id: :receiver_death,
               receiver: receiver,
               restart: :temporary
             )

    owned_pid = start_supervised!(owned_spec)
    owned_monitor = Process.monitor(owned_pid)
    assert_receive {:matter_credentials, _, "receiver-death"}
    assert_receive {:matter_connect, _}
    assert_receive {:matter_subscribe, relay, _, _, _, _}
    Process.exit(receiver, :kill)
    assert_receive {:matter_unsubscribe, ^relay, _, _}
    assert_receive :disconnected
    assert_receive {:DOWN, ^owned_monitor, :process, ^owned_pid, _}

    blocked = spawn(fn -> receive do: (:release -> send(parent, :released)) end)
    send(blocked, :queued)
    assert {:ok, overloaded} = consumed(document, profile, response: :unused)

    assert {:ok, overloaded_spec} =
             ConsumedThing.observation_child_spec(
               overloaded,
               "reading",
               context("overflow"),
               id: :overflow,
               receiver: blocked,
               restart: :temporary,
               max_queue_length: 1,
               overflow: :stop
             )

    overloaded_pid = start_supervised!(overloaded_spec)
    overloaded_monitor = Process.monitor(overloaded_pid)
    assert_receive {:matter_credentials, _, "overflow"}
    assert_receive {:matter_connect, _}
    assert_receive {:matter_subscribe, overflow_relay, _, _, _, overflow_reference}

    metadata = %{kind: :attribute, path: @attribute_path, data_version: 1, initial: true}

    send(
      overflow_relay,
      {:wotex_matter, overflow_reference, {:ok, @attribute_value, metadata}}
    )

    assert_receive {:matter_unsubscribe, ^overflow_relay, _, _}
    assert_receive :disconnected
    assert_receive {:DOWN, ^overloaded_monitor, :process, ^overloaded_pid, _}
    Process.exit(blocked, :kill)
  end

  test "WMA-I05 one-shot profile exposes no stream child" do
    assert {:ok, consumed} = consumed(stream_td(), Matter.profile(), response: :unused)

    assert {:error, %RuntimeError{code: :compatible_form_not_found}} =
             ConsumedThing.observation_child_spec(
               consumed,
               "reading",
               context("no-stream"),
               id: :no_stream,
               receiver: self()
             )

    refute_receive {:matter_credentials, _, _}
    refute_receive {:matter_connect, _}
  end

  test "WMA-I03/I05 unsupported controller stream descriptors acquire no client" do
    {:ok, controller} = Matter.profile(:controller)

    document =
      td(%{
        "properties" => %{
          "unknown" => %{
            "readOnly" => true,
            "observable" => true,
            "forms" => [
              %{
                "href" => href(%{@attribute_path | cluster: 7}),
                "op" => "observeproperty"
              },
              %{
                "href" => href(%{@attribute_path | cluster: 7}),
                "op" => "unobserveproperty"
              }
            ]
          }
        }
      })

    assert {:ok, consumed} = consumed(document, controller, response: :unused)

    assert {:ok, child_spec} =
             ConsumedThing.observation_child_spec(
               consumed,
               "unknown",
               context("unsupported-stream"),
               id: :unsupported_stream,
               receiver: self(),
               restart: :temporary
             )

    pid = start_supervised!(child_spec)
    monitor = Process.monitor(pid)
    assert_receive {:matter_credentials, _, "unsupported-stream"}

    assert_receive {:wotex_runtime, :unsupported_stream,
                    {:error,
                     %RuntimeError{
                       class: :permanent,
                       details: %{cause: %{code: :unsupported_schema}}
                     }}}

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}
    refute_receive {:matter_connect, _}
  end

  defp run_runtime_read(input) do
    mode = profile_mode(input["profile_mode"])
    {:ok, profile} = Matter.profile(mode)
    {:ok, document} = Wotex.ThingDescription.from_map(input["thing_description"])
    response = peer_response(input["peer_reply"])
    transport = transport_options(input["transport_options"], response)

    {:ok, consumed} =
      ConsumedThing.new(document,
        profiles: [profile],
        transports: %{BindingProfile.id(profile) => {Transport, transport}},
        credentials: {RuntimeCredentials, %{test_pid: self()}}
      )

    context = fixture_context(input)
    {:ok, result} = ConsumedThing.read_property(consumed, input["affordance"], context)

    assert_receive {:matter_credentials, form, request_id}
    assert_receive {:matter_connect, _}
    assert_receive {:matter_request, command, timeout}
    assert timeout > 0
    assert timeout <= input["transport_options"]["timeout"]
    assert_receive :disconnected
    refute_receive {:matter_request, _, _}

    %{
      "profile_id" => atom_string(BindingProfile.id(profile)),
      "resolved_href" => command_href(command),
      "command" => json_value(Map.take(command, [:type | Map.keys(@attribute_path)])),
      "result" => result_projection(result),
      "extension" => form["example:extension"],
      "request_count" => 1,
      "owned_resources_after" => 0
    }
    |> tap(fn _ -> assert request_id == input["request_id"] end)
  end

  defp run_error_projection(input) do
    operation = operation(input["wot_operation"])
    native = native_error(input["native_error"])
    profile = Matter.profile()
    document = error_td(operation)
    options = fault_options(input["fault"], native)
    {:ok, consumed} = consumed(document, profile, options)

    result =
      case operation do
        :readproperty ->
          ConsumedThing.read_property(consumed, "value", context("error"))

        :writeproperty ->
          ConsumedThing.write_property(consumed, "value", @write_value, context("error"))
      end

    {:error, %RuntimeError{} = error} = result
    assert_receive {:matter_credentials, _, "error"}
    assert_fault_lifecycle(input["fault"])
    cause = error.details.cause
    retry = Retry.decision(operation, error, retry_options(input["retry_options"]))

    %{
      "class" => atom_string(error.class),
      "cause_code" => atom_string(cause.code),
      "retained_native_effect" => Map.has_key?(cause, :effect),
      "retry_decision" => retry_projection(retry)
    }
  end

  defp consumed(document, profile, options) do
    transport =
      [client: RuntimeClient, target: "1", test_pid: self(), timeout: 500]
      |> Keyword.merge(options)

    ConsumedThing.new(document,
      profiles: [profile],
      transports: %{BindingProfile.id(profile) => {Transport, transport}},
      credentials: {RuntimeCredentials, %{test_pid: self()}}
    )
  end

  defp consumed_with_profiles(document, profiles, response) do
    transport =
      {Transport,
       [client: RuntimeClient, target: "1", test_pid: self(), timeout: 500, response: response]}

    ConsumedThing.new(document,
      profiles: profiles,
      transports: Map.new(profiles, &{BindingProfile.id(&1), transport}),
      credentials: {RuntimeCredentials, %{test_pid: self()}}
    )
  end

  defp result_consumed(document, mode) do
    profile = Matter.profile()

    ConsumedThing.new(document,
      profiles: [profile],
      transports: %{
        BindingProfile.id(profile) => {RuntimeResultTransport, %{mode: mode, test_pid: self()}}
      },
      credentials: {RuntimeCredentials, %{test_pid: self()}}
    )
  end

  defp td(extra, options \\ []) do
    base = %{
      "@context" => @context,
      "id" => "urn:example:matter:integration",
      "title" => "Matter integration fixture",
      "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
      "security" => ["none"]
    }

    document =
      if Keyword.get(options, :security, true),
        do: Map.merge(base, extra),
        else: Map.merge(Map.drop(base, ["securityDefinitions", "security"]), extra)

    {:ok, td} = Wotex.ThingDescription.from_map(document)
    td
  end

  defp error_td(:readproperty) do
    td(%{
      "properties" => %{
        "value" => %{
          "readOnly" => true,
          "forms" => [%{"href" => href(@attribute_path), "op" => "readproperty"}]
        }
      }
    })
  end

  defp error_td(:writeproperty) do
    td(%{
      "properties" => %{
        "value" => %{
          "writeOnly" => true,
          "forms" => [%{"href" => href(@write_path), "op" => "writeproperty"}]
        }
      }
    })
  end

  defp stream_td do
    stop_attribute = %{@attribute_path | fabric_id: 2, node_id: 999}
    stop_event = %{@event_path | fabric_id: 2, node_id: 999}

    td(%{
      "properties" => %{
        "reading" => %{
          "readOnly" => true,
          "observable" => true,
          "forms" => [
            %{"href" => href(@attribute_path), "op" => "observeproperty"},
            %{"href" => href(stop_attribute), "op" => "unobserveproperty"}
          ]
        }
      },
      "events" => %{
        "reachable" => %{
          "forms" => [
            %{"href" => href(@event_path), "op" => "subscribeevent"},
            %{"href" => href(stop_event), "op" => "unsubscribeevent"}
          ]
        }
      }
    })
  end

  defp fault_options("peer_unavailable", error), do: [connect_error: error]
  defp fault_options("admission_full", error), do: [connect_error: error]
  defp fault_options("invalid_route", _), do: [target: "different", response: :unused]
  defp fault_options(_, error), do: [response: {:error, error}]

  defp assert_fault_lifecycle("invalid_route") do
    refute_receive {:matter_connect, _}
    refute_receive {:matter_request, _, _}
    refute_receive :disconnected
  end

  defp assert_fault_lifecycle(fault) when fault in ["peer_unavailable", "admission_full"] do
    assert_receive {:matter_connect, _}
    refute_receive {:matter_request, _, _}
    refute_receive :disconnected
  end

  defp assert_fault_lifecycle(_) do
    assert_receive {:matter_connect, _}
    assert_receive {:matter_request, _, _}
    assert_receive :disconnected
  end

  defp native_error(%{"code" => code, "effect" => effect}) do
    code
    |> error_code()
    |> MatterError.new()
    |> MatterError.with_effect(error_effect(effect))
  end

  defp error_code("deadline_exceeded"), do: :deadline_exceeded
  defp error_code("connection_failed"), do: :connection_failed
  defp error_code("busy"), do: :busy
  defp error_code("response_mismatch"), do: :response_mismatch
  defp error_code("target_mismatch"), do: :target_mismatch
  defp error_effect("none"), do: :none
  defp error_effect("unknown"), do: :unknown

  defp peer_response(%{"kind" => "client_return", "value" => value}), do: value

  defp peer_response(%{
         "kind" => "attribute_report",
         "path" => path,
         "value" => value,
         "data_version" => version,
         "status" => 0
       }) do
    %{path: atom_path(path), value: element(value), data_version: version}
  end

  defp transport_options(options, response) do
    base = [
      client: RuntimeClient,
      test_pid: self(),
      target: options["target"],
      timeout: options["timeout"],
      response: response
    ]

    if options["lifecycle"] == "persistent",
      do: Keyword.put(base, :lifecycle, :persistent),
      else: base
  end

  defp fixture_context(input) do
    clock = input["clock"]
    remaining = clock["deadline"] - clock["start"]

    context(input["request_id"], System.monotonic_time(:millisecond) + remaining)
  end

  defp context(id, deadline \\ nil) do
    {:ok, context} = Context.new(request_id: id, deadline: deadline)
    context
  end

  defp retry_options(options) do
    [
      attempt: options["attempt"],
      max_attempts: options["max_attempts"],
      delay: options["delay"]
    ]
    |> maybe_idempotent(options)
  end

  defp maybe_idempotent(options, %{"idempotent?" => value}),
    do: Keyword.put(options, :idempotent?, value)

  defp maybe_idempotent(options, _), do: options

  defp retry_projection({:retry, delay}), do: %{"retry" => delay}
  defp retry_projection(:stop), do: "stop"

  defp result_projection(result) do
    %{
      "request_id" => result.request_id,
      "operation" => atom_string(result.operation),
      "status" => atom_string(result.status),
      "payload" => json_value(result.payload),
      "metadata" => json_value(result.metadata)
    }
  end

  defp command_href(command) do
    "matter://#{command.fabric_id}/#{command.node_id}/#{command.endpoint}/#{command.cluster}/#{command.member}"
  end

  defp href(path) do
    "matter://#{path.fabric_id}/#{path.node_id}/#{path.endpoint}/#{path.cluster}/#{path.member}"
  end

  defp atom_path(path) do
    %{
      fabric_id: path["fabric_id"],
      node_id: path["node_id"],
      endpoint: path["endpoint"],
      cluster: path["cluster"],
      member: path["member"]
    }
  end

  defp element(%{"tag" => "anonymous", "type" => type, "value" => value}),
    do: %{tag: :anonymous, type: element_type(type), value: value}

  defp element_type("boolean"), do: :boolean

  defp profile_mode("oneshot"), do: :oneshot
  defp profile_mode("controller"), do: :controller
  defp operation("readproperty"), do: :readproperty
  defp operation("writeproperty"), do: :writeproperty

  defp json_value(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {atom_string(key), json_value(item)} end)

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(value) when is_boolean(value), do: value
  defp json_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp json_value(value), do: value

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value) when is_binary(value), do: value

  defp fixture!,
    do:
      @fixture
      |> File.read!()
      |> Jason.decode!()

  defp case!(fixture, id), do: Enum.find(fixture["cases"], &(&1["id"] == id))
end
