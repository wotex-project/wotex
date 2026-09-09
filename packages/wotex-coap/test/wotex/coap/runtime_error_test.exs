Code.require_file("../../support/error_transport.ex", __DIR__)

defmodule Wotex.CoAP.RuntimeErrorTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.{Codec, Error, RuntimeFrame, Transport}
  alias Wotex.CoAP.Test.{ErrorTransport, RuntimeCredentials}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Retry}

  @corpus Path.expand("../../../docs/specs/fixtures/wotex-integration-v1.json", __DIR__)
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @faults %{
    "read_timeout" => {:deadline_exceeded, :none},
    "pre_send_acquisition_failure" => {:socket_failed, :none},
    "admission_full" => {:busy, :none},
    "malformed_response_encoding" => {:invalid_header, :none},
    "invalid_route" => {:invalid_form, :none},
    "sent_write_timeout" => {:deadline_exceeded, :unknown}
  }
  @operations %{"readproperty" => :readproperty, "writeproperty" => :writeproperty}
  @options %{
    "attempt" => :attempt,
    "max_attempts" => :max_attempts,
    "delay" => :delay,
    "idempotent?" => :idempotent?
  }

  for entry <- @cases, entry["operation"] == "error_retry_projection" do
    @entry entry
    test "#{entry["id"]} WCO-I04 actual Runtime cause and retry projection" do
      input = @entry["input"]
      {code, effect} = Map.fetch!(@faults, input["fault"])
      native = Error.with_effect(Error.new(code), effect)
      operation = Map.fetch!(@operations, input["wot_operation"])
      error = through_runtime(native, operation)

      options =
        Enum.map(input["retry_options"], fn {key, value} -> {Map.fetch!(@options, key), value} end)

      decision =
        case Retry.decision(operation, error, options) do
          {:retry, delay} -> %{"retry" => delay}
          :stop -> "stop"
        end

      actual = %{
        "class" => Atom.to_string(error.class),
        "cause_code" => Atom.to_string(error.details.cause.code),
        "retained_native_effect" => Map.has_key?(error.details.cause, :effect),
        "retry_decision" => decision
      }

      assert actual == @entry["expectation"]["value"]
      refute native.retryable
    end
  end

  test "WCO-I04 complete class table preserves default mutation restrictions" do
    for {native, expected} <- [
          {Error.new(:timeout), :timeout},
          {Error.new(:transport_error, nil, %{reason: :timeout}), :timeout},
          {Error.new(:connection_closed), :unavailable},
          {Error.new(:busy), :rate_limited},
          {Error.new(:invalid_response), :protocol},
          {Error.new(:invalid_security), :permanent},
          {Error.new(:unclassified_fixture_failure), nil}
        ] do
      read = through_runtime(native, :readproperty)
      assert read.class == expected

      assert Retry.decision(:readproperty, read, attempt: 1, max_attempts: 2) ==
               if(expected in [:timeout, :unavailable, :rate_limited], do: {:retry, 0}, else: :stop)

      write = through_runtime(native, :writeproperty)
      assert :stop = Retry.decision(:writeproperty, write, attempt: 1, max_attempts: 2)
      uncertain = Error.with_effect(native, :unknown)
      assert uncertain.class == :permanent and uncertain.effect == :unknown
      refute uncertain.retryable
      rejected = through_runtime(uncertain, :writeproperty)

      assert :stop =
               Retry.decision(:writeproperty, rejected,
                 attempt: 1,
                 max_attempts: 2,
                 idempotent?: true
               )
    end
  end

  test "WCO-I04 sent UDP mutations never become retryable through real Runtime" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)
    consumed = consumed({Transport, [timeout: 30]}, port)
    {:ok, context} = Context.new(request_id: "uncertain")

    for operation <- [:readproperty, :writeproperty] do
      request = Task.async(fn -> invoke(consumed, operation, context) end)
      assert {:ok, {_, _, bytes}} = :gen_udp.recv(peer, 0, 1000)
      assert {:ok, message} = Codec.decode(bytes)
      assert message.code == if(operation == :readproperty, do: 1, else: 3)
      assert {:error, error} = Task.await(request)
      assert error.class == if(operation == :readproperty, do: :timeout, else: :permanent)
      refute Map.has_key?(error.details.cause, :effect)
      decision = Retry.decision(operation, error, attempt: 1, max_attempts: 2, idempotent?: true)
      assert decision == if(operation == :readproperty, do: {:retry, 0}, else: :stop)
    end
  end

  test "WCO-I04 Runtime frame validation rejects forged classifications and secret detail shapes" do
    native = Error.new(:timeout)
    assert RuntimeFrame.error(native) == native
    uncertain = Error.with_effect(native, :unknown)
    assert RuntimeFrame.error(uncertain) == uncertain

    for forged <- [
          %{uncertain | class: :timeout},
          %{uncertain | retryable: true},
          %{native | details: %{credential: "retained-secret"}},
          %{native | details: MapSet.new()},
          Map.put(native, :extra, true)
        ] do
      assert %Error{code: :invalid_runtime_frame, class: :protocol} = RuntimeFrame.error(forged)
      refute inspect(RuntimeFrame.error(forged)) =~ "retained-secret"
    end
  end

  defp through_runtime(native, operation) do
    {:ok, context} = Context.new(request_id: "classified")
    assert {:error, error} = invoke(consumed({ErrorTransport, native}, 5683), operation, context)
    error
  end

  defp invoke(consumed, :readproperty, context),
    do: ConsumedThing.read_property(consumed, "reading", context)

  defp invoke(consumed, :writeproperty, context),
    do: ConsumedThing.write_property(consumed, "reading", 42, context)

  defp consumed(transport, port) do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Failure fixture",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "reading" => %{
            "forms" => [
              %{"href" => "coap://127.0.0.1:#{port}/value", "contentType" => "application/json"}
            ]
          }
        }
      })

    {:ok, profile} =
      BindingProfile.new(
        id: :coap_failure,
        schemes: ["coap"],
        operations: [:readproperty, :writeproperty],
        media_types: ["application/json"]
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{coap_failure: transport},
        credentials: {RuntimeCredentials, []}
      )

    consumed
  end
end
