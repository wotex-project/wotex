defmodule Wotex.Runtime.ImplementationLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.Implementation.{Error, Lifecycle}
  alias Wotex.Runtime.TestSupport.ImplementationFactory, as: F

  test "public lifecycle traverses startup, drain and verified cleanup, with no restart" do
    {:ok, admitted} = Lifecycle.new(F.plan())
    assert admitted.state == :admitted
    starting = step(admitted, :start)
    ready = step(starting, :ready)
    draining = step(ready, :drain)
    stopped = step(draining, :cleanup_confirmed)
    assert stopped.state == :stopped
    assert stopped.cleanup_outcome == :confirmed_local

    assert Lifecycle.to_map(stopped) == %{
             "instance_key" => %{
               "consumer_scope" => "consumer",
               "instance_id" => "codec.1",
               "generation" => 1
             },
             "admission_sha256" => admitted.admission_sha256,
             "state" => "stopped",
             "reason" => nil,
             "cleanup_outcome" => "confirmed_local"
           }

    assert {:error, %Error{code: :invalid_transition}} =
             Lifecycle.transition(stopped, event(stopped, :start))

    assert {:error, %Error{}} = Lifecycle.new(%{F.plan() | instance_key: F.key(2)})
  end

  test "the complete state/event matrix implements only the specified transitions" do
    {:ok, admitted} = Lifecycle.new(F.plan())
    starting = step(admitted, :start)
    ready = step(starting, :ready)
    draining = step(ready, :drain)
    failed = step(ready, :failure)
    stopped = step(draining, :cleanup_confirmed)
    rejected = step(admitted, :revoke)

    matrix = %{
      admitted: %{start: :starting, revoke: :rejected, expire: :rejected},
      starting: %{
        ready: :ready,
        cancel: :draining,
        revoke: :draining,
        expire: :failed,
        failure: :failed,
        owner_lost: :failed,
        transport_lost: :failed
      },
      ready: %{
        drain: :draining,
        revoke: :draining,
        expire: :draining,
        failure: :failed,
        owner_lost: :failed,
        transport_lost: :failed
      },
      draining: %{
        failure: :failed,
        owner_lost: :failed,
        transport_lost: :failed,
        cleanup_confirmed: :stopped,
        cleanup_failed: :failed
      },
      failed: %{cleanup_confirmed: :stopped, cleanup_failed: :failed},
      stopped: %{},
      rejected: %{}
    }

    types =
      ~w(start ready drain cancel revoke expire failure owner_lost transport_lost cleanup_confirmed cleanup_failed)a

    for lifecycle <- [admitted, starting, ready, draining, failed, stopped, rejected],
        type <- types do
      case Map.fetch(matrix[lifecycle.state], type) do
        {:ok, state} ->
          assert {:ok, next} = Lifecycle.transition(lifecycle, event(lifecycle, type))
          assert next.state == state
          assert :ok = Lifecycle.validate(next)

        :error ->
          assert {:error, %Error{code: :invalid_transition}} =
                   Lifecycle.transition(lifecycle, event(lifecycle, type))
      end
    end
  end

  test "uncertain effect survives cleanup failure and never becomes retryable" do
    {:ok, value} = Lifecycle.new(F.plan())

    ready =
      value
      |> step(:start)
      |> step(:ready)

    e = %{event(ready, :failure) | reason: :effect_unknown}
    {:ok, failed} = Lifecycle.transition(ready, e)
    assert failed.cleanup_outcome == :pending
    unconfirmed = step(failed, :cleanup_failed)
    assert unconfirmed.state == :failed and unconfirmed.reason == :effect_unknown
    assert unconfirmed.cleanup_outcome == :unconfirmed
    stopped = step(unconfirmed, :cleanup_confirmed)
    assert stopped.reason == :effect_unknown

    assert Wotex.Runtime.Retry.decision(:invokeaction, :permanent,
             idempotent?: true,
             max_attempts: 3
           ) == :stop
  end

  test "identity, forged structs and every wrong event field fail before transition" do
    {:ok, value} = Lifecycle.new(F.plan())

    assert {:error, %Error{code: :stale_generation}} =
             Lifecycle.transition(value, %{event(value, :start) | instance_key: F.key(2)})

    wrong = %{F.key() | consumer_scope: "other"}

    assert {:error, %Error{code: :invalid_instance}} =
             Lifecycle.transition(value, %{event(value, :start) | instance_key: wrong})

    for key <- Map.keys(event(value, :start)) do
      assert {:error, %Error{}} = Lifecycle.transition(value, Map.delete(event(value, :start), key))
    end

    for bad <- [
          %{type: :foreign},
          %{reason: "secret-canary"},
          %{cleanup_outcome: :confirmed_local},
          %{instance_key: nil},
          %{extra: "secret-canary"}
        ] do
      assert {:error, %Error{} = error} =
               Lifecycle.transition(value, Map.merge(event(value, :start), bad))

      refute inspect(error) =~ "secret-canary"
    end

    for forged <- [
          nil,
          %{__struct__: Lifecycle},
          %{value | state: :foreign},
          %{value | reason: :invalid_input},
          %{value | cleanup_outcome: :confirmed_local}
        ] do
      assert {:error, %Error{}} = Lifecycle.to_map(forged)
      assert {:error, %Error{}} = Lifecycle.transition(forged, event(value, :start))
    end

    assert {:error, %Error{}} = Lifecycle.new(nil)
    assert {:error, %Error{}} = Lifecycle.transition(value, nil)

    ready =
      value
      |> step(:start)
      |> step(:ready)

    assert {:error, %Error{}} = Lifecycle.transition(ready, %{event(ready, :failure) | reason: nil})

    assert {:error, %Error{}} =
             Lifecycle.transition(ready, %{event(ready, :failure) | cleanup_outcome: nil})
  end

  defp event(lifecycle, type) do
    {reason, cleanup} =
      case type do
        type when type in [:failure, :owner_lost, :transport_lost] -> {:session_lost, :pending}
        :cleanup_confirmed -> {nil, :confirmed_local}
        :cleanup_failed -> {nil, :unconfirmed}
        _ -> {nil, nil}
      end

    %{type: type, instance_key: lifecycle.instance_key, reason: reason, cleanup_outcome: cleanup}
  end

  defp step(lifecycle, type) do
    {:ok, next} = Lifecycle.transition(lifecycle, event(lifecycle, type))
    next
  end
end
