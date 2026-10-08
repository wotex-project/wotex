defmodule Wotex.Modbus.RegisterProcessFixture do
  @moduledoc false

  alias Wotex.Modbus.{RegisterCodec, RegisterCodecFixture}

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

  # Synthetic receipts exercise the owner contract, never native verification.
  @spec plan(map(), keyword()) :: Plan.t()
  def plan(configuration, opts \\ []) do
    value =
      RegisterCodecFixture.descriptor().value
      |> Map.merge(%{
        "binding" => %{"id" => "process-codec", "version" => "1.0.0"},
        "artifact" => %{
          "package" => "wotex_modbus",
          "profile" => "register-decimal",
          "target" => "test-process",
          "build_identity" => String.duplicate("b", 64),
          "payload_identity" => String.duplicate("c", 64)
        },
        "entrypoint" => "bin/register-decimal",
        "limits" => %{
          "startup_ms" => 5000,
          "request_ms" => 1000,
          "shutdown_ms" => 1000,
          "inflight" => 1,
          "queued" => 0,
          "frame_bytes" => 131_072,
          "queue_bytes" => 262_144,
          "stderr_bytes" => 4096,
          "memory_bytes" => 67_108_864
        }
      })

    value = put_in(value["limits"], Map.merge(value["limits"], Keyword.get(opts, :limits, %{})))
    {:ok, descriptor} = Descriptor.decode(Jason.encode!(value))
    {:ok, admission} = Admission.new(descriptor, inputs(descriptor, opts))

    {:ok, key} =
      InstanceKey.new(%{
        consumer_scope: "consumer",
        instance_id: Keyword.get(opts, :id, "register-decoder"),
        generation: Keyword.get(opts, :generation, 1)
      })

    {:ok, plan} = Plan.new(admission, configuration, key, &RegisterCodec.validate_configuration/2)
    plan
  end

  @spec inputs(Descriptor.t(), keyword()) :: Inputs.t()
  def inputs(descriptor, opts \\ []) do
    base = RegisterCodecFixture.inputs(descriptor)

    deployment = %{
      "kind" => "native_payload",
      "identity" => descriptor.value["artifact"]["payload_identity"]
    }

    enforcement = %{
      "id" => "consumer.test.native",
      "trust" => "trusted",
      "guarantees" => ~w(deadline descendants immutable_deployment memory privileges)
    }

    registration =
      base.registrations[descriptor.value["id"]].value
      |> Map.merge(%{"deployment" => deployment, "enforcement" => enforcement})

    {:ok, registration} = Registration.new(registration)
    {:ok, trust} = Trust.new(Map.put(base.trust.value, "deployment", deployment))

    policy =
      Map.merge(base.policy.value, %{
        "target" => "test-process",
        "deployment" => deployment,
        "enforcement" => enforcement
      })

    policy =
      put_in(
        policy["enforcement"]["guarantees"],
        Keyword.get(opts, :guarantees, enforcement["guarantees"])
      )

    {:ok, policy} = Policy.new(policy)

    {:ok, verification} =
      Verification.new(%{
        "schema" => "wotex.implementation-verification@1",
        "descriptor_sha256" => descriptor.sha256,
        "artifact" => descriptor.value["artifact"],
        "native_descriptor_schema" => "wotex.native-artifact-descriptor@2",
        "payload_manifest_schema" => "wotex.native-payload-manifest@1",
        "artifact_format" => "wotex.native-artifact@1",
        "closure_sha256" => String.duplicate("d", 64),
        "deployment_evidence_sha256" => String.duplicate("d", 64),
        "legal_sha256" => String.duplicate("d", 64),
        "sbom_sha256" => String.duplicate("d", 64),
        "advisory_receipt_sha256" => String.duplicate("d", 64),
        "security_exception" => nil,
        "verified_at_ms" => 100,
        "verifier_id" => "consumer.test",
        "verifier_revision" => "test.1"
      })

    {:ok, inputs} =
      Inputs.new(%{
        registrations: %{descriptor.value["id"] => registration},
        verification: verification,
        trust: trust,
        policy: policy,
        target: "test-process",
        apis: base.apis,
        bindings: base.bindings,
        now_ms: 100,
        scope: "consumer"
      })

    inputs
  end
end
