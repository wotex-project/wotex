defmodule WotexContinuum.ValueStateTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{
    ActionResult,
    Artifact,
    Capability,
    CapabilityRequirement,
    Compatibility,
    Degradation,
    Delivery,
    Error,
    EvidenceReference,
    ExitReceipt,
    Failure,
    Manifest
  }

  test "nested value constructors are idempotent and reject incomplete input" do
    assert {:ok, artifact} =
             Artifact.new(%{
               name: "example",
               version: "1.0.0",
               digest: "sha256:" <> String.duplicate("a", 64)
             })

    assert {:ok, ^artifact} = Artifact.new(artifact)
    assert Artifact.to_map(artifact)["name"] == "example"
    assert {:error, %Error{code: :required}} = Artifact.new(%{})

    assert {:ok, requirement} =
             CapabilityRequirement.new(%{id: "example", version_requirement: "~> 1.0"})

    assert {:ok, ^requirement} = CapabilityRequirement.new(requirement)
    assert CapabilityRequirement.to_map(requirement)["id"] == "example"

    assert {:ok, failure} = Failure.new(%{code: "example", message: "failed", details: nil})
    assert {:ok, ^failure} = Failure.new(failure)
    assert Failure.to_map(failure)["details"] == nil
    assert {:error, %Error{code: :required}} = Failure.new(%{message: "missing"})
  end

  test "Action result invariants cover progress, success, failure, cancellation, and unknown" do
    base = action_result_base()

    for status <- [:accepted, :running, :unknown] do
      assert {:ok, result} = ActionResult.new(Map.put(base, :status, status))
      assert result.status == status
      assert {:ok, ^result} = ActionResult.new(result)
    end

    assert {:ok, failed} =
             ActionResult.new(
               base
               |> Map.put(:status, :failed)
               |> Map.put(:completed_at, "2026-09-02T10:00:02Z")
               |> Map.put(:error, %{code: "rejected", message: "example"})
             )

    assert failed.error.code == "rejected"

    assert {:ok, cancelled} =
             ActionResult.new(
               base
               |> Map.put(:status, :cancelled)
               |> Map.put(:completed_at, "2026-09-02T10:00:02Z")
             )

    refute Map.has_key?(ActionResult.to_map(cancelled), "output")

    assert {:ok, succeeded_with_null} =
             ActionResult.new(
               base
               |> Map.put(:status, :succeeded)
               |> Map.put(:output, nil)
               |> Map.put(:completed_at, "2026-09-02T10:00:02Z")
             )

    assert Map.has_key?(ActionResult.to_map(succeeded_with_null), "output")

    assert {:error, %Error{code: :invalid_result_state}} =
             ActionResult.new(Map.put(base, :status, :succeeded))

    assert {:error, %Error{code: :invalid_time_order}} =
             ActionResult.new(
               base
               |> Map.put(:status, :cancelled)
               |> Map.put(:started_at, "2026-09-02T10:00:03Z")
               |> Map.put(:completed_at, "2026-09-02T10:00:02Z")
             )
  end

  test "delivery invariants cover progress, failure, and invalid order" do
    base = delivery_base()

    for status <- [:pending, :in_flight, :delivered, :unknown] do
      assert {:ok, delivery} = Delivery.new(Map.put(base, :status, status))
      assert delivery.status == status
      assert {:ok, ^delivery} = Delivery.new(delivery)
    end

    assert {:ok, failed} =
             Delivery.new(
               base
               |> Map.put(:status, :failed)
               |> Map.put(:error, %{code: "unreachable", message: "example"})
             )

    assert Delivery.to_map(failed)["error"]["code"] == "unreachable"

    assert {:error, %Error{code: :unknown_kind}} =
             Delivery.new(Map.put(base, :item_kind, "not_registered"))

    assert {:error, %Error{code: :invalid_delivery_state}} =
             Delivery.new(Map.put(base, :status, :acknowledged))

    assert {:error, %Error{code: :invalid_time_order}} =
             Delivery.new(
               base
               |> Map.put(:status, :acknowledged)
               |> Map.put(:acknowledged_at, "2026-09-02T09:59:59Z")
             )
  end

  test "exit receipts cover requested, export, partial, and failed outcomes" do
    base = exit_base()

    for status <- [:requested, :running] do
      assert {:ok, receipt} = ExitReceipt.new(Map.put(base, :status, status))
      assert receipt.status == status
      assert {:ok, ^receipt} = ExitReceipt.new(receipt)
    end

    assert {:ok, exported} =
             ExitReceipt.new(
               base
               |> Map.put(:operation, :export)
               |> Map.put(:status, :completed)
               |> Map.put(:completed_at, "2026-09-02T10:00:01Z")
               |> Map.put(:residuals, ["consumer-retained-copy"])
             )

    assert exported.residuals == ["consumer-retained-copy"]

    assert {:ok, partial} =
             ExitReceipt.new(
               base
               |> Map.put(:status, :partial)
               |> Map.put(:completed_at, "2026-09-02T10:00:01Z")
               |> Map.put(:residuals, ["temporary-cache"])
             )

    assert partial.status == :partial

    assert {:ok, failed} =
             ExitReceipt.new(
               base
               |> Map.put(:status, :failed)
               |> Map.put(:completed_at, "2026-09-02T10:00:01Z")
               |> Map.put(:error, %{code: "blocked", message: "example"})
             )

    assert ExitReceipt.to_map(failed)["error"]["code"] == "blocked"

    assert {:error, %Error{code: :invalid_time_order}} =
             ExitReceipt.new(
               base
               |> Map.put(:status, :failed)
               |> Map.put(:completed_at, "2026-09-02T09:59:59Z")
               |> Map.put(:error, %{code: "blocked", message: "example"})
             )
  end

  test "degradation and manifest enforce cross-field uniqueness" do
    assert {:ok, none} =
             Degradation.new(%{
               degradation_id: "none-example",
               subject_id: "worker-example",
               level: :none,
               capabilities: [],
               reason_codes: [],
               since: "2026-09-02T10:00:00Z",
               recoverable: true
             })

    assert {:ok, ^none} = Degradation.new(none)
    assert Degradation.to_map(none)["level"] == "none"

    assert {:ok, capability} = Capability.new(capability_map())
    assert {:ok, compatibility} = Compatibility.new(compatibility_map())

    manifest = %{
      manifest_id: "manifest-example",
      artifact: %{
        name: "example",
        version: "1.0.0",
        digest: "sha256:" <> String.duplicate("a", 64)
      },
      compatibility: compatibility,
      supported_modes: [:hybrid],
      capabilities: [capability]
    }

    assert {:ok, value} = Manifest.new(manifest)
    assert {:ok, ^value} = Manifest.new(value)
    assert :ok = Manifest.compatible_with?(value, "1.0.0", [])

    assert {:error, %Error{code: :duplicate_value}} =
             Manifest.new(%{manifest | capabilities: [capability, capability]})

    assert {:error, %Error{code: :unsupported_capability_mode}} =
             Manifest.new(%{manifest | supported_modes: [:saas]})

    duplicate_requirements =
      compatibility_map()
      |> Map.put(:required_capabilities, [
        %{id: "same", version_requirement: "~> 1.0"},
        %{id: "same", version_requirement: "~> 1.0"}
      ])

    assert {:error, %Error{code: :duplicate_value}} = Compatibility.new(duplicate_requirements)

    assert {:error, [%{type: :schema, actual: "invalid"}]} =
             Compatibility.evaluate(compatibility, "invalid", [])
  end

  test "evidence references remain inert digest-bound values" do
    data = %{
      evidence_id: "evidence-example",
      uri: "urn:example:evidence:1",
      digest: "sha256:" <> String.duplicate("b", 64),
      media_type: "application/json",
      captured_at: "2026-09-02T10:00:00Z"
    }

    assert {:ok, evidence} = EvidenceReference.new(data)
    assert {:ok, ^evidence} = EvidenceReference.new(evidence)
    assert EvidenceReference.to_map(evidence)["uri"] == "urn:example:evidence:1"
  end

  defp action_result_base do
    %{
      result_id: "result-example",
      intent_id: "intent-example",
      status: :accepted,
      context: context_map()
    }
  end

  defp delivery_base do
    %{
      delivery_id: "delivery-example",
      item_kind: "action_intent",
      item_id: "intent-example",
      source: "edge-example",
      destination: "consumer-example",
      status: :pending,
      attempt: 1,
      emitted_at: "2026-09-02T10:00:00Z"
    }
  end

  defp exit_base do
    %{
      receipt_id: "exit-example",
      subject_id: "worker-example",
      operation: :remove,
      status: :requested,
      requested_at: "2026-09-02T10:00:00Z"
    }
  end

  defp capability_map do
    %{
      id: "local-buffering",
      version: "1.0.0",
      operations: ["enqueue"],
      modes: [:hybrid],
      network: :local,
      degradation: :queue
    }
  end

  defp compatibility_map do
    %{schema_requirement: "~> 1.0", required_capabilities: []}
  end

  defp context_map do
    %{
      execution_id: "exec-example",
      node_id: "edge-example",
      mode: %{deployment: :hybrid, connectivity: :connected},
      observed_at: "2026-09-02T10:00:00Z"
    }
  end
end
