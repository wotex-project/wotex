defmodule Wotex.Lab.Test.ContinuumFixtures do
  @moduledoc false

  # One valid value per registered continuum kind, built through public constructors.

  alias WotexContinuum.{
    ActionIntent,
    ActionResult,
    Capability,
    Compatibility,
    Degradation,
    Delivery,
    EvidenceReference,
    ExecutionScope,
    ExitReceipt,
    Lifecycle,
    Manifest,
    Mode,
    ObservationProposal
  }

  @at "2026-09-08T10:00:00Z"
  @digest "sha256:" <> String.duplicate("a", 64)

  @spec mode() :: Mode.t()
  def mode do
    {:ok, mode} = Mode.from_map(%{deployment: :hybrid, connectivity: :connected})
    mode
  end

  @spec scope(String.t()) :: ExecutionScope.t()
  def scope(node_id \\ "edge-a") do
    {:ok, scope} =
      ExecutionScope.from_map(%{
        execution_id: "exec-1",
        node_id: node_id,
        mode: mode(),
        observed_at: @at
      })

    scope
  end

  @spec capability(String.t(), String.t()) :: Capability.t()
  def capability(id \\ "observation-forwarding", version \\ "2.1.0") do
    {:ok, capability} =
      Capability.from_map(%{
        id: id,
        version: version,
        operations: ["forward"],
        modes: [:hybrid, :saas],
        network: :external,
        degradation: :queue
      })

    capability
  end

  @spec compatibility(String.t()) :: Compatibility.t()
  def compatibility(requirement \\ ">= 2.0.0 and < 3.0.0") do
    {:ok, compatibility} =
      Compatibility.from_map(%{
        schema_requirement: "~> 2.0",
        required_capabilities: [%{id: "observation-forwarding", version_requirement: requirement}]
      })

    compatibility
  end

  @spec manifest(keyword()) :: Manifest.t()
  def manifest(opts \\ []) do
    {:ok, manifest} =
      Manifest.from_map(%{
        manifest_id: Keyword.get(opts, :id, "manifest-edge-a"),
        artifact: %{name: "edge-worker", version: "1.2.3", digest: @digest},
        compatibility: Keyword.get(opts, :compatibility, compatibility()),
        supported_modes: [:hybrid, :saas, :air_gapped],
        capabilities: [capability("local-buffering", "1.0.0")]
      })

    manifest
  end

  @spec all_kinds() :: [struct()]
  def all_kinds do
    {:ok, evidence} =
      EvidenceReference.from_map(%{
        evidence_id: "evidence-1",
        uri: "https://example.test/evidence/1",
        digest: @digest,
        media_type: "application/json",
        captured_at: @at
      })

    {:ok, proposal} =
      ObservationProposal.from_map(%{
        proposal_id: "proposal-1",
        thing_id: "urn:wotex:lab:room:1",
        affordance_type: :property,
        affordance_name: "temperature",
        value: 21.5,
        observed_at: @at,
        sequence: 1,
        context: scope()
      })

    {:ok, intent} =
      ActionIntent.from_map(%{
        intent_id: "intent-1",
        thing_id: "urn:wotex:lab:room:1",
        action_name: "setTarget",
        input: 22.0,
        requested_at: @at,
        idempotency_key: "set-22",
        context: scope()
      })

    {:ok, result} =
      ActionResult.from_map(%{
        result_id: "result-1",
        intent_id: "intent-1",
        status: :succeeded,
        output: %{"accepted" => true},
        completed_at: @at,
        context: scope("cloud")
      })

    {:ok, delivery} =
      Delivery.from_map(%{
        delivery_id: "delivery-x",
        item_kind: "action_intent",
        item_id: "intent-1",
        source: "edge-a",
        destination: "cloud",
        status: :acknowledged,
        attempt: 1,
        emitted_at: @at,
        acknowledged_at: @at
      })

    {:ok, lifecycle} =
      Lifecycle.from_map(%{subject_id: "edge-a", state: :active, generation: 2, changed_at: @at})

    {:ok, degradation} =
      Degradation.from_map(%{
        degradation_id: "degradation-1",
        subject_id: "edge-a",
        level: :reduced,
        capabilities: ["observation-forwarding"],
        reason_codes: ["uplink_slow"],
        since: @at,
        recoverable: true
      })

    {:ok, receipt} =
      ExitReceipt.from_map(%{
        receipt_id: "receipt-1",
        subject_id: "edge-a",
        operation: :export,
        status: :completed,
        requested_at: @at,
        completed_at: @at,
        artifacts: [evidence]
      })

    [
      manifest(),
      compatibility(),
      scope(),
      capability(),
      proposal,
      intent,
      result,
      evidence,
      delivery,
      mode(),
      lifecycle,
      degradation,
      receipt
    ]
  end
end
