defmodule Wotex.Runtime.ImplementationBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.Implementation.{
    Admission,
    Descriptor,
    Error,
    Inputs,
    InstanceKey,
    JSON,
    Plan,
    Policy,
    Registration,
    Trust,
    Verification
  }

  alias Wotex.Runtime.TestSupport.ImplementationFactory, as: F

  test "all scalar JSON syntax, escapes and collection limits are bounded" do
    for {source, value} <- [
          {"null", nil},
          {"true", true},
          {"false", false},
          {"-9007199254740991", -9_007_199_254_740_991},
          {"9007199254740991", 9_007_199_254_740_991},
          {"{}", %{}},
          {"[]", []},
          {"{\"a\":1,\"b\":2}", %{"a" => 1, "b" => 2}},
          {"\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0001\\ud83d\\ude00\"", "\"\\/\b\f\n\r\t\u0001😀"}
        ] do
      assert {:ok, ^value} = JSON.decode(source)
      assert {:ok, encoded} = JSON.encode(value)
      assert {:ok, ^value} = JSON.decode(encoded)
    end

    for invalid <- [
          nil,
          "",
          "\"",
          "\"\\x\"",
          "\"\\uXXXX\"",
          "\"\\udc00\"",
          "\"\\ud800\\u0041\"",
          "\"a\n\"",
          "{\"a\" 0}",
          "{0:0}",
          "{\"a\":0,}",
          "[0 true]",
          "01",
          "+1",
          "1e0",
          "-",
          "1.0",
          "9007199254740992",
          "12345678901234567890123",
          "{\"a\":0]",
          "[",
          "[0"
        ] do
      assert {:error, _} = JSON.decode(invalid)
    end

    assert {:error, :limit_exceeded} = JSON.decode(~s({"a":0,"b":1}), %{entries: 1})
    assert {:error, :limit_exceeded} = JSON.decode("[[],[]]", %{depth: 1})
    assert {:error, :limit_exceeded} = JSON.encode(%{"a" => 0, "b" => 1}, %{entries: 1})
    assert {:error, :limit_exceeded} = JSON.encode([1, 2], %{entries: 1})
    assert {:error, :limit_exceeded} = JSON.encode([[1]], %{depth: 1})
    assert {:error, :limit_exceeded} = JSON.encode([1], %{nodes: 1})
    assert {:error, :limit_exceeded} = JSON.encode([], %{bytes: 1})
    assert {:error, :limit_exceeded} = JSON.encode(%{"a" => 0}, %{bytes: 5})

    for value <- [1.0, :foreign, %{a: 1}, %{"x" => <<255>>}, %InstanceKey{}] do
      assert {:error, _} = JSON.encode(value)
    end
  end

  test "kind-specific descriptor, registration and permission contracts are closed" do
    cell = %{
      "direction" => "consumed",
      "scheme" => "http",
      "operation" => "readproperty",
      "media_type" => "application/json",
      "security_scheme" => "nosec"
    }

    permission = %{"kind" => "device", "resource" => "device.1", "operations" => ["read", "write"]}

    host =
      F.native_map()
      |> Map.merge(%{
        "kind" => "native_host",
        "support" => [cell],
        "permissions" => [permission],
        "state" => %{
          "scope" => "consumer_instance",
          "continuity" => "explicit_loss",
          "update_mode" => "stop_reopen",
          "format" => nil
        }
      })

    beam =
      F.descriptor_map()
      |> Map.merge(%{"kind" => "beam_adapter", "support" => [cell], "permissions" => [permission]})

    data = F.descriptor_map() |> Map.put("kind", "data_mapping")

    for map <- [host, beam, data] do
      d = F.descriptor(map)
      rmap = F.registration_map(d)

      rmap =
        if map["kind"] == "data_mapping",
          do: Map.put(rmap, "deployment", %{"kind" => "data", "identity" => "mapping.1"}),
          else: rmap

      assert {:ok, r} = Registration.new(rmap)
      assert r.value["codec_contract"] == nil
    end

    d = F.descriptor(host)
    i = F.inputs(d)
    assert {:ok, a} = Admission.new(d, i)
    assert a.value["permissions"] == [permission]
    {:ok, p} = Policy.new(Map.put(i.policy.value, "grants", []))
    assert {:error, %Error{code: :permission_denied}} = Admission.new(d, %{i | policy: p})
    {:ok, r} = Registration.new(Map.put(i.registrations[d.value["id"]].value, "permissions", []))

    assert {:error, %Error{code: :permission_denied}} =
             Admission.new(d, %{i | registrations: %{d.value["id"] => r}})

    {:ok, r} =
      Registration.new(
        Map.put(i.registrations[d.value["id"]].value, "support", [
          Map.put(cell, "direction", "exposed")
        ])
      )

    assert {:error, %Error{code: :unsupported_cell}} =
             Admission.new(d, %{i | registrations: %{d.value["id"] => r}})

    for change <- [
          %{"permissions" => [Map.put(permission, "operations", ["read", "read"])]},
          %{"support" => [Map.put(cell, "operation", "unknown")]},
          %{"state" => Map.put(host["state"], "scope", "stateless")},
          %{"entrypoint" => String.duplicate("a/", 16) <> "codec"},
          %{"extensions" => %{"bad" => true}},
          %{"extensions" => %{"x:" => true}},
          %{"extensions" => %{"x:a" => -1}}
        ] do
      assert {:error, %Error{}} = Descriptor.decode(Jason.encode!(Map.merge(host, change)))
    end

    store = Map.put(permission, "kind", "store")

    assert {:error, %Error{}} =
             Descriptor.decode(Jason.encode!(Map.put(host, "permissions", [store])))

    assert {:ok, _} =
             Descriptor.decode(
               Jason.encode!(
                 host
                 |> Map.put("permissions", [store])
                 |> put_in(["state", "format"], "store@1" |> String.replace("@", "."))
               )
             )
  end

  test "compatibility and execution revalidation reject substituted decisions before work" do
    d = F.descriptor(Map.put(F.descriptor_map(), "requires", ["feature.1"]))
    i = F.inputs(d)
    original = i.registrations[d.value["id"]]

    for {change, code} <- [
          {%{"requires" => []}, :unsupported_requirement},
          {%{"configuration_schema" => %{"id" => "other", "sha256" => F.hash()}},
           :identity_mismatch},
          {%{"descriptor_sha256" => F.hash()}, :identity_mismatch}
        ] do
      {:ok, r} = Registration.new(Map.merge(original.value, change))

      assert {:error, %Error{code: ^code}} =
               Admission.new(d, %{i | registrations: %{d.value["id"] => r}})
    end

    {:ok, t} = Trust.new(Map.put(i.trust.value, "scope", "other"))
    assert {:error, %Error{code: :identity_mismatch}} = Admission.new(d, %{i | trust: t})
    {:ok, p} = Policy.new(Map.put(i.policy.value, "target", "other"))
    assert {:error, %Error{code: :identity_mismatch}} = Admission.new(d, %{i | policy: p})
    {:ok, a} = Admission.new(d, i)
    assert {:error, %Error{}} = Admission.validate(%{a | registration: nil})
    assert {:error, %Error{}} = Admission.validate(nil)
    assert {:error, %Error{}} = Inputs.validate(nil)
    assert {:error, %Error{}} = Plan.validate(nil)
    assert {:error, %Error{}} = Plan.validate(%{F.plan() | sha256: F.hash()})
    assert {:error, %Error{}} = Plan.new(a, %{}, F.key(), nil)

    assert {:error, %Error{}} =
             Inputs.new(%{Map.from_struct(i) | trust: %{i.trust | sha256: F.hash()}})

    assert {:error, %Error{}} =
             Registration.new(Map.put(original.value, "support", [nil | :invalid]))

    assert {:error, %Error{code: :limit_exceeded}} =
             Policy.new(Map.put(i.policy.value, "scope", String.duplicate("x", 4097)))
  end

  test "native admission refuses future verification, wrong deployment, zero limits and untrusted execution" do
    d = F.descriptor(F.native_map())
    i = F.inputs(d)
    {:ok, v} = Verification.new(Map.put(i.verification.value, "verified_at_ms", 101))
    assert {:error, %Error{code: :artifact_unverified}} = Admission.new(d, %{i | verification: v})

    {:ok, r} =
      Registration.new(
        Map.put(i.registrations[d.value["id"]].value, "deployment", %{
          "kind" => "native_payload",
          "identity" => F.hash("f")
        })
      )

    assert {:error, %Error{code: :identity_mismatch}} =
             Admission.new(d, %{i | registrations: %{d.value["id"] => r}})

    for {change, code} <- [
          {%{"limits" => Map.put(i.policy.value["limits"], "memory_bytes", 0)},
           :enforcement_unavailable},
          {%{"enforcement" => Map.put(i.policy.value["enforcement"], "trust", "untrusted")},
           :enforcement_unavailable},
          {%{"enforcement" => Map.put(i.policy.value["enforcement"], "guarantees", ["memory"])},
           :deployment_mutable}
        ] do
      {:ok, p} = Policy.new(Map.merge(i.policy.value, change))
      assert {:error, %Error{code: ^code}} = Admission.new(d, %{i | policy: p})
    end

    exception = %{
      "id" => "exception",
      "scope" => "consumer",
      "payload_identity" => d.value["artifact"]["payload_identity"],
      "expires_at_ms" => 101,
      "decision_sha256" => F.hash()
    }

    assert {:ok, v} =
             Verification.new(Map.put(i.verification.value, "security_exception", exception))

    assert {:ok, _} = Admission.new(d, %{i | verification: v})

    assert {:error, %Error{}} =
             Verification.new(
               Map.put(
                 i.verification.value,
                 "security_exception",
                 Map.put(exception, "payload_identity", F.hash())
               )
             )

    for key <- ~w(legal_sha256 sbom_sha256 closure_sha256) do
      assert {:error, %Error{}} = Verification.new(Map.put(i.verification.value, key, nil))
    end
  end

  test "fixed error classes and details reject every foreign field and identity" do
    assert {:error, %Error{}} = Admission.validate(%{__struct__: Admission})
    assert {:error, %Error{}} = Plan.validate(%{__struct__: Plan})
    refute Error.valid?(%{__struct__: Error})

    for {code, class} <- [
          deadline_exceeded: :timeout,
          codec_unavailable: :unavailable,
          startup_failed: :unavailable,
          owner_lost: :unavailable,
          session_lost: :unavailable,
          overloaded: :rate_limited,
          protocol_fault: :protocol,
          correlation_failed: :protocol,
          effect_unknown: :permanent
        ] do
      e =
        Error.new(code, :request, %{
          field: :instance_key,
          descriptor_sha256: F.hash(),
          instance_key: F.key()
        })

      assert e.class == class
      assert Error.valid?(e)
    end

    for details <- [
          %{field: "secret"},
          %{descriptor_sha256: 1},
          %{descriptor_sha256: "short"},
          %{instance_key: %{}},
          %{unknown: "secret"},
          nil
        ] do
      assert %Error{code: :invalid_admission_inputs, phase: :construction, field: nil} =
               Error.new(:overloaded, :request, details)
    end

    refute Error.valid?(nil)
    refute InstanceKey.valid?(nil)
    assert is_list(Error.codes())
  end
end
