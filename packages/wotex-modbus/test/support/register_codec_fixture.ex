defmodule Wotex.Modbus.RegisterCodecFixture do
  @moduledoc false

  alias Wotex.Modbus.RegisterCodec

  alias Wotex.Runtime.Implementation.{
    Admission,
    Descriptor,
    Inputs,
    InstanceKey,
    Plan,
    Policy,
    Registration,
    Trust
  }

  @spec plan(map(), pos_integer()) :: Plan.t()
  def plan(configuration, generation \\ 1) do
    descriptor = descriptor()
    {:ok, admission} = Admission.new(descriptor, inputs(descriptor))

    {:ok, key} =
      InstanceKey.new(%{
        consumer_scope: "consumer",
        instance_id: "register-decoder",
        generation: generation
      })

    {:ok, plan} = Plan.new(admission, configuration, key, &RegisterCodec.validate_configuration/2)
    plan
  end

  @spec descriptor() :: Descriptor.t()
  def descriptor do
    value = %{
      "schema" => "wotex.implementation@1",
      "id" => "wotex.modbus.register-decimal",
      "version" => "1.0.0",
      "kind" => "codec",
      "api" => %{"id" => "wotex.codec", "version" => "1.0.0"},
      "binding" => %{"id" => "beam-codec", "version" => "1.0.0"},
      "artifact" => nil,
      "entrypoint" => nil,
      "support" => [],
      "requires" => [],
      "configuration_schema" => RegisterCodec.configuration_schema(),
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

    {:ok, descriptor} = Descriptor.decode(Jason.encode!(value))
    descriptor
  end

  @spec inputs(Descriptor.t()) :: Inputs.t()
  def inputs(descriptor \\ descriptor()) do
    d = descriptor.value
    deployment = %{"kind" => "beam_release", "identity" => String.duplicate("b", 64)}
    enforcement = %{"id" => "consumer.trusted", "trust" => "trusted", "guarantees" => ["deadline"]}

    registration = %{
      "schema" => "wotex.implementation-registration@1",
      "id" => d["id"],
      "kind" => "codec",
      "descriptor_sha256" => descriptor.sha256,
      "deployment" => deployment,
      "apis" => [d["api"]],
      "bindings" => [d["binding"]],
      "support" => [],
      "requires" => [],
      "permissions" => [],
      "configuration_schema" => d["configuration_schema"],
      "state" => d["state"],
      "enforcement" => enforcement,
      "limits" => d["limits"],
      "codec_contract" => RegisterCodec.contract()
    }

    {:ok, registration} = Registration.new(registration)

    {:ok, trust} =
      Trust.new(%{
        "schema" => "wotex.implementation-trust@1",
        "mode" => "local_pin",
        "approval_id" => "consumer.approval",
        "scope" => "consumer",
        "descriptor_sha256" => descriptor.sha256,
        "deployment" => deployment,
        "revision" => "trust.1",
        "valid_until_ms" => nil,
        "update" => nil
      })

    {:ok, policy} =
      Policy.new(%{
        "schema" => "wotex.implementation-policy@1",
        "scope" => "consumer",
        "target" => "test-beam",
        "descriptor_sha256" => descriptor.sha256,
        "deployment" => deployment,
        "revision" => "policy.1",
        "valid_until_ms" => nil,
        "grants" => [],
        "limits" => d["limits"],
        "enforcement" => enforcement,
        "security_status" => "allowed",
        "security_revision" => "security.1"
      })

    {:ok, inputs} =
      Inputs.new(%{
        registrations: %{d["id"] => registration},
        verification: nil,
        trust: trust,
        policy: policy,
        target: "test-beam",
        apis: [d["api"]],
        bindings: [d["binding"]],
        now_ms: 100,
        scope: "consumer"
      })

    inputs
  end
end
