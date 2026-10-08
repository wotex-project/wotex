defmodule Wotex.Runtime.TestSupport.ImplementationFactory do
  @moduledoc false

  alias Wotex.Runtime.Implementation.{
    Admission,
    Descriptor,
    Inputs,
    InstanceKey,
    Plan,
    Policy,
    Registration,
    Trust,
    Verification
  }

  @spec hash(term()) :: String.t()
  def hash(character \\ "a"), do: String.duplicate(character, 64)

  @spec descriptor_map() :: map()
  def descriptor_map do
    %{
      "schema" => "wotex.implementation@1",
      "id" => "example.codec",
      "version" => "1.0.0",
      "kind" => "codec",
      "api" => %{"id" => "wotex.codec", "version" => "1.0.0"},
      "binding" => %{"id" => "beam-codec", "version" => "1.0.0"},
      "artifact" => nil,
      "entrypoint" => nil,
      "support" => [],
      "requires" => [],
      "configuration_schema" => %{"id" => "example.codec.config", "sha256" => hash()},
      "permissions" => [],
      "state" => %{
        "scope" => "stateless",
        "continuity" => "none",
        "update_mode" => "message_boundary",
        "format" => nil
      },
      "limits" => %{
        "startup_ms" => 0,
        "request_ms" => 1000,
        "shutdown_ms" => 1000,
        "inflight" => 1,
        "queued" => 0,
        "frame_bytes" => 0,
        "queue_bytes" => 0,
        "stderr_bytes" => 0,
        "memory_bytes" => 0
      },
      "extensions" => %{}
    }
  end

  @spec descriptor(map()) :: Descriptor.t()
  def descriptor(map \\ descriptor_map()) do
    {:ok, descriptor} = Descriptor.decode(Jason.encode!(map))
    descriptor
  end

  @spec deployment(term()) :: map()
  def deployment(d) do
    if d.value["artifact"],
      do: %{"kind" => "native_payload", "identity" => d.value["artifact"]["payload_identity"]},
      else: %{"kind" => "beam_release", "identity" => hash("b")}
  end

  @spec enforcement(term()) :: map()
  def enforcement(d) do
    %{
      "id" => "consumer.trusted",
      "trust" => "trusted",
      "guarantees" =>
        if(d.value["artifact"],
          do: ~w(memory deadline descendants privileges immutable_deployment),
          else: ["deadline"]
        )
    }
  end

  @spec registration_map(term()) :: map()
  def registration_map(d) do
    %{
      "schema" => "wotex.implementation-registration@1",
      "id" => d.value["id"],
      "kind" => d.value["kind"],
      "descriptor_sha256" => d.sha256,
      "deployment" => deployment(d),
      "apis" => [d.value["api"]],
      "bindings" => [d.value["binding"]],
      "support" => d.value["support"],
      "requires" => d.value["requires"],
      "permissions" => d.value["permissions"],
      "configuration_schema" => d.value["configuration_schema"],
      "state" => d.value["state"],
      "enforcement" => enforcement(d),
      "limits" => d.value["limits"],
      "codec_contract" =>
        if(d.value["kind"] == "codec",
          do: %{"id" => "example.uint8", "version" => "1.0.0", "sha256" => hash("c")},
          else: nil
        )
    }
  end

  @spec trust_map(term()) :: map()
  def trust_map(d) do
    %{
      "schema" => "wotex.implementation-trust@1",
      "mode" => "local_pin",
      "approval_id" => "consumer.approval",
      "scope" => "consumer",
      "descriptor_sha256" => d.sha256,
      "deployment" => deployment(d),
      "revision" => "trust.1",
      "valid_until_ms" => nil,
      "update" => nil
    }
  end

  @spec policy_map(term()) :: map()
  def policy_map(d) do
    %{
      "schema" => "wotex.implementation-policy@1",
      "scope" => "consumer",
      "target" => "darwin-aarch64",
      "descriptor_sha256" => d.sha256,
      "deployment" => deployment(d),
      "revision" => "policy.1",
      "valid_until_ms" => nil,
      "grants" => d.value["permissions"],
      "limits" => d.value["limits"],
      "enforcement" => enforcement(d),
      "security_status" => "allowed",
      "security_revision" => "security.1"
    }
  end

  @spec verification_map(term()) :: map()
  def verification_map(d) do
    %{
      "schema" => "wotex.implementation-verification@1",
      "descriptor_sha256" => d.sha256,
      "artifact" => d.value["artifact"],
      "native_descriptor_schema" => "wotex.native-artifact-descriptor@2",
      "payload_manifest_schema" => "wotex.native-payload-manifest@1",
      "artifact_format" => "wotex.native-artifact@1",
      "closure_sha256" => hash(),
      "deployment_evidence_sha256" => hash(),
      "legal_sha256" => hash(),
      "sbom_sha256" => hash(),
      "advisory_receipt_sha256" => hash(),
      "security_exception" => nil,
      "verified_at_ms" => 0,
      "verifier_id" => "consumer.verifier",
      "verifier_revision" => "verifier.1"
    }
  end

  @spec inputs(term()) :: Inputs.t()
  def inputs(d \\ descriptor()) do
    {:ok, registration} = Registration.new(registration_map(d))
    {:ok, trust} = Trust.new(trust_map(d))
    {:ok, policy} = Policy.new(policy_map(d))

    verification =
      if d.value["artifact"] do
        {:ok, receipt} = Verification.new(verification_map(d))
        receipt
      end

    {:ok, inputs} =
      Inputs.new(%{
        registrations: %{d.value["id"] => registration},
        verification: verification,
        trust: trust,
        policy: policy,
        target: "darwin-aarch64",
        apis: [d.value["api"]],
        bindings: [d.value["binding"]],
        now_ms: 100,
        scope: "consumer"
      })

    inputs
  end

  @spec key(term()) :: InstanceKey.t()
  def key(generation \\ 1) do
    {:ok, key} =
      InstanceKey.new(%{consumer_scope: "consumer", instance_id: "codec.1", generation: generation})

    key
  end

  @spec plan(term()) :: Plan.t()
  def plan(config \\ %{}) do
    d = descriptor()
    {:ok, admission} = Admission.new(d, inputs(d))
    {:ok, plan} = Plan.new(admission, config, key(), fn _, _ -> :ok end)
    plan
  end

  @spec native_map() :: map()
  def native_map do
    descriptor_map()
    |> Map.put("binding", %{"id" => "process-codec", "version" => "1.0.0"})
    |> Map.put("artifact", %{
      "package" => "wotex-runtime",
      "profile" => "process-codec",
      "target" => "darwin-aarch64",
      "build_identity" => hash("d"),
      "payload_identity" => hash("e")
    })
    |> Map.put("entrypoint", "bin/codec")
    |> Map.update!(
      "limits",
      &Map.merge(&1, %{
        "startup_ms" => 5000,
        "frame_bytes" => 131_072,
        "queue_bytes" => 262_144,
        "stderr_bytes" => 4096,
        "memory_bytes" => 67_108_864
      })
    )
  end
end
