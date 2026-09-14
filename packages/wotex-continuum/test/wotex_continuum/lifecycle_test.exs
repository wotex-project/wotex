defmodule WotexContinuum.LifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{Error, Lifecycle, Mode}

  @transitions %{
    staged: [:ready, :removed],
    ready: [:active, :stopped, :removed],
    active: [:degraded, :draining, :stopped],
    degraded: [:active, :draining, :stopped],
    draining: [:stopped],
    stopped: [:ready, :removed],
    removed: []
  }

  test "applies allowed transitions with monotonic generation" do
    assert {:ok, staged} =
             Lifecycle.new(%{
               subject_id: "worker-example-1",
               state: :staged,
               generation: 0,
               changed_at: "2026-09-02T10:00:00Z"
             })

    assert {:ok, ready} =
             Lifecycle.transition(staged, :ready, "2026-09-02T10:00:01Z", reason: "validated")

    assert ready.state == :ready
    assert ready.generation == 1
    assert ready.reason == "validated"
  end

  test "rejects forbidden and time-reversing transitions" do
    assert {:ok, active} =
             Lifecycle.new(%{
               subject_id: "worker-example-1",
               state: :active,
               generation: 8,
               changed_at: "2026-09-02T10:00:00Z"
             })

    assert {:error, %Error{code: :invalid_transition}} =
             Lifecycle.transition(active, :ready, "2026-09-02T10:00:01Z")

    assert {:error, %Error{code: :invalid_time_order}} =
             Lifecycle.transition(active, :stopped, "2026-09-02T09:59:59Z")

    assert {:error, %Error{code: :invalid_enum}} =
             Lifecycle.transition(%{active | state: :unknown}, :stopped, "2026-09-02T10:00:01Z")

    assert {:error, %Error{code: :invalid_options}} =
             Lifecycle.transition(active, :stopped, "2026-09-02T10:00:01Z", [:malformed])

    assert {:error, %Error{code: :unknown_field}} =
             Lifecycle.transition(active, :stopped, "2026-09-02T10:00:01Z", unknown: true)

    assert {:error, %Error{code: :invalid_options, path: nil}} =
             Lifecycle.transition(active, :stopped, "2026-09-02T10:00:01Z",
               reason: "first",
               reason: "second"
             )

    assert {:error, %Error{code: :invalid_type, path: "/reason"}} =
             Lifecycle.transition(active, :stopped, "2026-09-02T10:00:01Z", reason: nil)
  end

  test "the complete transition matrix is exact and removed is terminal" do
    assert Enum.sort(Map.keys(@transitions)) == Enum.sort(Lifecycle.states())

    for from <- Lifecycle.states(), to <- Lifecycle.states() do
      assert {:ok, current} =
               Lifecycle.new(%{
                 subject_id: "worker-example-1",
                 state: from,
                 generation: 41,
                 changed_at: "2026-09-02T10:00:00Z",
                 extensions: %{"urn:example:trace" => "retained"}
               })

      case Lifecycle.transition(current, to, "2026-09-02T10:00:00Z") do
        {:ok, next} ->
          assert to in Map.fetch!(@transitions, from), "unexpected #{from} -> #{to}"
          assert next.state == to
          assert next.generation == 42
          assert next.changed_at == current.changed_at
          assert next.extensions == current.extensions
          assert next.reason == nil

        {:error, %Error{} = error} ->
          refute to in Map.fetch!(@transitions, from), "missing #{from} -> #{to}"
          assert error.code == :invalid_transition
          assert error.phase == :validation
          assert error.path == "/state"
          assert error.details == %{from: from, to: to}
      end
    end
  end

  test "air-gapped mode makes upstream disconnection explicit" do
    assert {:ok, %Mode{deployment: :air_gapped, connectivity: :disconnected}} =
             Mode.new(%{deployment: :air_gapped, connectivity: :disconnected})

    assert {:error, %Error{code: :invalid_mode}} =
             Mode.new(%{deployment: :air_gapped, connectivity: :intermittent})
  end
end
