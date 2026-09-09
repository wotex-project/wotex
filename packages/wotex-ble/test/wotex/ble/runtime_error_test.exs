defmodule Wotex.BLE.RuntimeErrorTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE.{Error, PortCall, RuntimeErrorPort}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Retry}
  alias Wotex.ThingDescription

  @corpus Path.expand("../../..", __DIR__) <> "/docs/specs/fixtures/wotex-integration-v1.json"
  @external_resource @corpus
  @cases @corpus
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("cases")

  for vector <- Enum.filter(@cases, &(&1["operation"] == "error_retry_projection")) do
    @vector vector
    test "WBL-I04 WBL-I06 #{vector["id"]} class and retry cross real ConsumedThing" do
      input = @vector["input"]
      error = fault(input["fault"])
      assert Atom.to_string(error.code) == input["native_error"]["code"]
      assert Atom.to_string(error.effect) == input["native_error"]["effect"]
      operation = String.to_existing_atom(input["wot_operation"])
      result = runtime(error, operation)

      opts =
        Enum.map(input["retry_options"], fn {key, value} ->
          {String.to_existing_atom(key), value}
        end)

      decision =
        case Retry.decision(operation, result, opts) do
          :stop -> "stop"
          {:retry, delay} -> %{"retry" => delay}
        end

      assert %{
               "class" => Atom.to_string(result.class),
               "cause_code" => Atom.to_string(result.details.cause.code),
               "retained_native_effect" => Map.has_key?(result.details.cause, :effect),
               "retry_decision" => decision
             } == @vector["expectation"]["value"]
    end
  end

  test "WBL-I04 unknown mutations stop even with explicit idempotency and attempts" do
    for code <- [:timeout, :disconnected, :busy, :invalid_response, :unclassified] do
      error = Error.unknown_effect(Error.new(code))
      assert error.class == :permanent
      refute error.retryable
      result = runtime(error, :writeproperty)

      assert :stop =
               Retry.decision(:writeproperty, result,
                 attempt: 1,
                 max_attempts: 2,
                 idempotent?: true
               )

      assert result.details.cause == %{module: Error, code: code, phase: nil, class: :permanent}
    end
  end

  test "WBL-I04 malformed, unclassified, default mutation and exhausted attempts stop" do
    for {code, class} <- [
          {:invalid_response, :protocol},
          {:unclassified, nil},
          {:unsupported_security, :permanent},
          {:invalid_value, :permanent}
        ] do
      error = Error.new(code)
      assert error.class == class

      assert Retry.decision(:readproperty, runtime(error, :readproperty),
               attempt: 1,
               max_attempts: 2
             ) == :stop
    end

    for code <- [:timeout, :connection_failed, :busy] do
      error = Error.new(code)
      assert Retry.decision(:readproperty, runtime(error, :readproperty)) == :stop

      assert Retry.decision(:writeproperty, runtime(error, :writeproperty),
               attempt: 1,
               max_attempts: 2
             ) == :stop

      assert Retry.decision(:readproperty, runtime(error, :readproperty),
               attempt: 2,
               max_attempts: 2
             ) == :stop
    end
  end

  test "WBL-I04 custom client errors cannot smuggle a transient unknown-effect class" do
    forged = %{
      Error.new(:timeout, nil, %{private: "ERROR_SECRET"})
      | class: :timeout,
        retryable: true,
        effect: :unknown
    }

    assert {:error, error} = PortCall.invoke(RuntimeErrorPort, :request, [nil, nil, forged])
    assert error.class == :permanent
    refute error.retryable
    result = runtime(error, :writeproperty)
    refute inspect(result) =~ "ERROR_SECRET"
    refute Map.has_key?(result.details.cause, :details)
    refute Map.has_key?(result.details.cause, :retryable)
  end

  defp fault("read_timeout"), do: Error.new(:deadline_exceeded)
  defp fault("peer_unavailable"), do: Error.new(:connection_failed)
  defp fault("admission_full"), do: Error.new(:busy)
  defp fault("wrong_correlation"), do: Error.new(:response_mismatch)
  defp fault("invalid_route"), do: Error.new(:target_mismatch)
  defp fault("sent_write_timeout"), do: Error.unknown_effect(Error.new(:deadline_exceeded))

  defp runtime(error, operation) do
    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Error projection fixture",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{"reading" => %{"forms" => [%{"href" => "ble://peer/180f/2a19"}]}}
      })

    {:ok, profile} =
      BindingProfile.new(id: :error_fixture, schemes: ["ble"], operations: [operation])

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{error_fixture: {RuntimeErrorPort, error}},
        credentials: {RuntimeErrorPort, nil}
      )

    context = Context.new!(request_id: "error-projection")

    result =
      case operation do
        :readproperty -> ConsumedThing.read_property(consumed, "reading", context)
        :writeproperty -> ConsumedThing.write_property(consumed, "reading", <<42>>, context)
      end

    assert {:error, %Wotex.Runtime.Error{code: :transport_request_failed} = projected} = result
    projected
  end
end
