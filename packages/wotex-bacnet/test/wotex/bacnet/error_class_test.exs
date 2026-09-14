defmodule Wotex.BACnet.ErrorClassTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.{Batch, Error, PortCall, Transport, Value}
  alias Wotex.BACnet.Test.{NativeHelpersClient, RuntimeCredentials}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Retry}
  alias Wotex.Runtime.Error, as: RuntimeError

  @corpus Path.expand("../../../docs/specs/fixtures/wotex-integration-v1.json", __DIR__)
  @external_resource @corpus
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @moduletag corpus_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)
  @codes [:deadline_exceeded, :connection_failed, :busy, :response_mismatch, :target_mismatch]

  test "WBA-I06 the integration corpus accounts for every declared local case" do
    corpus = Jason.decode!(File.read!(@corpus))
    expected_ids = Enum.map(1..7, &"WBA-I-F0#{&1}")
    assert Enum.map(@cases, & &1["id"]) == expected_ids
    assert corpus["binding_scope"]["local_case_ids"] == expected_ids
    assert corpus["binding_scope"]["unexecuted_case_ids"] == []

    assert @cases
           |> Enum.filter(&(&1["operation"] == "error_retry_projection"))
           |> Enum.map(& &1["id"]) == tl(expected_ids)
  end

  for vector <- @cases, vector["operation"] == "error_retry_projection" do
    @tag corpus_case_id: vector["id"], requirements: ["WBA-I04", "WBA-I06"]
    test "#{vector["id"]} WBA-I04 WBA-I06 native errors retain their Runtime class and retry decision" do
      vector = unquote(Macro.escape(vector))
      input = vector["input"]
      code = Enum.find(@codes, &(Atom.to_string(&1) == input["native_error"]["code"]))
      effect = if input["native_error"]["effect"] == "unknown", do: :unknown, else: :none
      error = Error.new(code, :property, %{secret: "must-not-cross-runtime", status: 32})
      error = Error.with_effect(error, effect)
      consumed = consumed(error)
      {:ok, context} = Context.new(request_id: vector["id"])

      operation =
        if input["wot_operation"] == "writeproperty", do: :writeproperty, else: :readproperty

      outcome =
        case operation do
          :readproperty -> ConsumedThing.read_property(consumed, "reading", context)
          :writeproperty -> ConsumedThing.write_property(consumed, "reading", 1.0, context)
        end

      assert {:error, %RuntimeError{} = failure} = outcome
      assert_receive {:native_helper_call, %{type: native_operation}}

      assert native_operation ==
               if(operation == :readproperty, do: :read_property, else: :write_property)

      options =
        Enum.map(input["retry_options"], fn {key, value} ->
          {Enum.find([:attempt, :max_attempts, :delay, :idempotent?], &(Atom.to_string(&1) == key)),
           value}
        end)

      decision =
        case Retry.decision(operation, failure, options) do
          :stop -> "stop"
          {:retry, delay} -> %{"retry" => delay}
        end

      projection = %{
        "class" => Atom.to_string(failure.class),
        "cause_code" => Atom.to_string(failure.details.cause.code),
        "retained_native_effect" => Map.has_key?(failure.details.cause, :effect),
        "retry_decision" => decision
      }

      assert projection == vector["expectation"]["value"], vector["id"]
      expected_class = failure.class

      assert %{
               class: ^expected_class,
               code: ^code,
               module: Wotex.BACnet.Error,
               phase: nil
             } = failure.details.cause

      refute Map.has_key?(failure.details.cause, :effect)
      refute Map.has_key?(failure.details.cause, :details)
      refute Map.has_key?(failure.details.cause, :retryable)
      refute inspect(failure) =~ "must-not-cross-runtime"
      assert Retry.decision(operation, failure) == :stop
    end
  end

  test "WBA-C04 WBA-I04 error transitions preserve numeric details and normalize forged retry hints" do
    for code <- [
          :deadline_exceeded,
          :connection_closed,
          :busy,
          :remote_error,
          :invalid_address,
          :unclassified_bounded_failure
        ] do
      error = Error.new(code, :property, %{class: 2, code: 32})
      changed = Error.with_effect(error, :unknown)
      assert changed.class == :permanent
      refute changed.retryable
      assert changed.effect == :unknown
      assert changed.details == %{class: 2, code: 32}
      assert changed.code == code
      assert changed.field == :property
      assert Error.with_effect(changed, :none) == error
      forged = %{changed | class: :unavailable, retryable: true}
      options = [owner: self(), result: {:error, forged}]

      assert {:error, normalized} =
               PortCall.invoke(NativeHelpersClient, :request, [options, %{}, 100])

      assert_receive {:native_helper_call, %{}}
      assert normalized.class == :permanent
      refute normalized.retryable
    end

    for code <- [
          :invalid_form,
          :unsupported_profile,
          :not_supported,
          :missing_value,
          :value_type_required
        ] do
      assert Error.new(code).class == :permanent
    end

    assert Error.new(:unclassified_bounded_failure).class == nil
    assert Error.normalize(%{Error.new(:busy) | class: :forged}).class == :rate_limited
    assert Error.normalize(%{Error.new(:busy) | code: "forged", class: nil}).class == nil
  end

  test "WBA-I04 malformed native reply is protocol failure while malformed input is permanent" do
    malformed = %Encoding{encoding: :primitive, type: :real, value: :invalid, extras: []}
    assert {:error, %Error{class: :permanent}} = Value.encode(malformed, nil)

    {:ok, session} =
      BACnet.connect(
        client: NativeHelpersClient,
        owner: self(),
        result: {:ok, malformed},
        timeout: 100
      )

    assert {:error, %Error{class: :protocol, effect: :none}} =
             BACnet.read_property(session, 1, 0, 85)

    assert_receive {:native_helper_call, %{type: :read_property}}
    {:ok, requests} = Batch.new(1, 0, [85])

    assert {:error, %Error{class: :protocol, effect: :none}} =
             Batch.accept(Batch.start(requests, 100), {:ok, malformed}, 1)

    assert Error.protocol(Error.with_effect(Error.new(:invalid_value), :unknown)).class ==
             :permanent
  end

  test "WBA-I04 unavailable writes stop by default and unclassified Runtime failures always stop" do
    for code <- [:connection_failed, :deadline_exceeded, :busy, :unclassified_bounded_failure] do
      consumed = consumed(Error.new(code))
      {:ok, context} = Context.new(request_id: "unclassified")
      assert {:error, error} = ConsumedThing.read_property(consumed, "reading", context)
      assert_receive {:native_helper_call, _}
      assert Retry.decision(:writeproperty, error, attempt: 1, max_attempts: 2) == :stop

      if code == :unclassified_bounded_failure do
        assert error.class == nil
        assert Retry.decision(:readproperty, error, attempt: 1, max_attempts: 2) == :stop
      end
    end
  end

  defp consumed(error) do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Retry contract",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "reading" => %{
            "forms" => [
              %{
                "href" => "bacnet://1234/2,1/85",
                "op" => ["readproperty", "writeproperty"],
                "bacv:hasDataType" => %{"@type" => "bacv:Real"}
              }
            ]
          }
        }
      })

    {:ok, profile} =
      BindingProfile.new(
        id: :bacnet_retry,
        schemes: ["bacnet"],
        operations: [:readproperty, :writeproperty]
      )

    config = [
      client: NativeHelpersClient,
      owner: self(),
      result: {:error, error},
      target: "1234",
      timeout: 1000
    ]

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{bacnet_retry: {Transport, config}},
        credentials: {RuntimeCredentials, []}
      )

    consumed
  end
end
