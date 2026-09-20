defmodule Wotex.Thread.RuntimeErrorTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Retry}
  alias Wotex.Thread.{Error, RuntimeErrorPort}

  @corpus Path.expand("../../../priv/fixtures/wotex-integration-v1.json", __DIR__)
  @external_resource @corpus
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @faults %{
    "read_timeout" => {:deadline_exceeded, :none},
    "peer_unavailable" => {:connection_failed, :none},
    "admission_full" => {:busy, :none},
    "wrong_correlation" => {:response_mismatch, :none},
    "invalid_route" => {:target_mismatch, :none},
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
    test "#{entry["id"]} WTH-I04 WTH-I06 class and retry cross real ConsumedThing" do
      input = @entry["input"]
      {code, effect} = Map.fetch!(@faults, input["fault"])
      native = effect(Error.new(code), effect)
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

  test "WTH-I04 complete class table preserves read defaults and mutation restrictions" do
    for {native, expected} <- [
          {Error.new(:timeout), :timeout},
          {Error.new(:connection_closed), :unavailable},
          {Error.new(:busy), :rate_limited},
          {Error.new(:invalid_response), :protocol},
          {Error.new(:remote_error), :protocol},
          {Error.new(:invalid_request), :permanent},
          {Error.new(:unclassified_bounded_failure), nil}
        ] do
      read = through_runtime(native, :readproperty)
      assert read.class == expected

      assert Retry.decision(:readproperty, read, attempt: 1, max_attempts: 2) ==
               if(expected in [:timeout, :unavailable, :rate_limited], do: {:retry, 0}, else: :stop)

      write = through_runtime(native, :writeproperty)
      assert :stop = Retry.decision(:writeproperty, write, attempt: 1, max_attempts: 2)

      uncertain = Error.unknown_effect(native)
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

  test "WTH-I04 typed client errors cannot forge a transient unknown-effect class" do
    forged = %{
      Error.new(:timeout, nil, %{private: "ERROR_SECRET"})
      | class: :timeout,
        retryable: true,
        effect: :unknown
    }

    assert Error.classify(forged) == Error.unknown_effect(forged)
    projected = through_runtime(Error.classify(forged), :writeproperty)
    assert projected.class == :permanent
    refute inspect(projected) =~ "ERROR_SECRET"
    refute Map.has_key?(projected.details.cause, :details)
    refute Map.has_key?(projected.details.cause, :retryable)
    refute Map.has_key?(projected.details.cause, :effect)
  end

  defp effect(error, :none), do: error
  defp effect(error, :unknown), do: Error.unknown_effect(error)

  defp through_runtime(native, operation) do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Thread error projection",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "reading" => %{
            "forms" => [
              %{
                "href" => "thread+unix://controller-a/state",
                "op" => ["readproperty", "writeproperty"]
              }
            ]
          }
        }
      })

    {:ok, profile} =
      BindingProfile.new(
        id: :thread_failure,
        schemes: ["thread+unix"],
        operations: [operation],
        media_types: []
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{thread_failure: {RuntimeErrorPort, native}},
        credentials: {RuntimeErrorPort, nil}
      )

    context = Context.new!(request_id: "classified")

    result =
      case operation do
        :readproperty -> ConsumedThing.read_property(consumed, "reading", context)
        :writeproperty -> ConsumedThing.write_property(consumed, "reading", 42, context)
      end

    assert {:error, %Wotex.Runtime.Error{code: :transport_request_failed} = projected} = result
    projected
  end
end
