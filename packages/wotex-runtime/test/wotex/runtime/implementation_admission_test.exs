defmodule Wotex.Runtime.ImplementationAdmissionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.Implementation.{
    Admission,
    Descriptor,
    Error,
    Grammar,
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

  test "passive admission and configuration preserve exact public layouts and identities" do
    d = F.descriptor()
    inputs = F.inputs(d)
    assert {:ok, a} = Admission.new(d, inputs)
    assert a.value["permissions"] == []
    assert a.value["verification_sha256"] == nil
    assert :ok = Admission.revalidate(a, %{inputs | now_ms: 101})

    assert {:ok, p} =
             Plan.new(a, %{"scale" => 2}, F.key(), fn config, schema ->
               assert config == %{"scale" => 2}
               assert schema == d.value["configuration_schema"]
               :ok
             end)

    assert p.instance_key.generation == 1

    assert Map.keys(Map.from_struct(p)) |> Enum.sort() ==
             Enum.sort([:admission, :configuration, :configuration_sha256, :instance_key, :sha256])

    assert d.value == Descriptor.to_map(d)
    assert :ok = Plan.validate(p)
  end

  test "JCS object ordering uses UTF-16, preserves arrays and extensions" do
    map =
      F.descriptor_map()
      |> Map.put("extensions", %{"example:identity" => %{"😀" => 1, "\uE000" => 2}})

    d = F.descriptor(map)
    encoded = Jason.encode!(map)

    reordered =
      "{" <>
        (map
         |> Enum.reverse()
         |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> Jason.encode!(v) end)) <> "}"

    assert {:ok, same} = Descriptor.decode(reordered)
    assert same.sha256 == d.sha256
    # Independently specified canonical serialization for this UTF-16 ordering.
    assert {:ok, canonical} = Wotex.Runtime.Implementation.JSON.encode(map)
    assert String.contains?(canonical, "{\"😀\":1,\"\uE000\":2}")
    assert {:ok, ^d} = Descriptor.decode(encoded)
    changed = F.descriptor(put_in(map, ["extensions", "example:identity", "😀"], 2))
    refute changed.sha256 == d.sha256
  end

  test "descriptor parser refuses duplicate keys, unsafe numbers, Unicode and trailing data" do
    json = Jason.encode!(F.descriptor_map())

    for invalid <- [
          json <> "null",
          "\uFEFF" <> json,
          String.replace(json, "\"extensions\":{}", "\"extensions\":{\"x:a\":1,\"x:a\":2}"),
          String.replace(json, "\"request_ms\":1000", "\"request_ms\":1e3"),
          String.replace(json, "\"request_ms\":1000", "\"request_ms\":1000.0"),
          String.replace(json, "\"request_ms\":1000", "\"request_ms\":-1"),
          String.replace(json, "\"extensions\":{}", "\"extensions\":{\"x:a\":\"\\ud800\"}"),
          String.replace(json, "\"extensions\":{}", "\"extensions\":{\"x:a\":[1,]}"),
          <<255>>
        ] do
      assert {:error, %Error{code: :invalid_descriptor, phase: :parse}} = Descriptor.decode(invalid)
    end
  end

  test "generic parse ceilings include exact byte, depth, node, member and decoded string bounds" do
    assert {:ok, "aa"} = JSON.decode("\"\\u0061\\u0061\"", %{string: 2})
    assert {:error, :limit_exceeded} = JSON.decode("\"aaa\"", %{string: 2})
    assert {:ok, [nil]} = JSON.decode("[null]", %{bytes: 6, depth: 1, nodes: 2, entries: 1})

    for limits <- [%{bytes: 5}, %{depth: 0}, %{nodes: 1}, %{entries: 0}] do
      assert {:error, :limit_exceeded} = JSON.decode("[null]", limits)
    end

    assert {:error, %Error{code: :limit_exceeded}} =
             Descriptor.decode(String.duplicate(" ", 65_537))

    assert {:error, :limit_exceeded} =
             JSON.decode(String.duplicate("[", 13) <> "0" <> String.duplicate("]", 13))

    assert {:error, :limit_exceeded} = JSON.encode(%{"x" => String.duplicate("a", 4097)})
    assert {:error, :invalid_descriptor} = JSON.encode([1 | :secret])
    assert {:ok, "\"\\u001a\""} = JSON.encode(<<26>>)
    assert {:error, :invalid_descriptor} = JSON.decode("\"\\u+001\"")
  end

  test "all descriptor fields are required and closed" do
    map = F.descriptor_map()

    for key <- Map.keys(map) do
      assert {:error, %Error{}} = Descriptor.decode(Jason.encode!(Map.delete(map, key)))
    end

    assert {:error, %Error{}} = Descriptor.decode(Jason.encode!(Map.put(map, "extra", "secret")))

    assert {:error, %Error{code: :unsupported_schema}} =
             Descriptor.decode(Jason.encode!(Map.put(map, "schema", "wotex.implementation@2")))

    for path <- ["/codec", "../codec", "bin/./codec", "bin//codec", "bin\\codec", "bin/codec\u0000"] do
      assert {:error, %Error{code: :invalid_descriptor}} =
               Descriptor.decode(Jason.encode!(Map.put(F.native_map(), "entrypoint", path)))
    end
  end

  test "SemVer grammar and compatibility follow independent version axes" do
    map = F.descriptor_map()

    for version <- ["01.0.0", "1.01.0", "1.0.0-01", "1.0.0-", "1.0.0+", "1.0", "1.0.0\n"] do
      assert {:error, %Error{}} = Descriptor.decode(Jason.encode!(Map.put(map, "version", version)))
    end

    for version <- ["1.0.0", "0.2.0", "1.0.0-alpha.1+build.01"] do
      assert {:ok, _} = Descriptor.decode(Jason.encode!(Map.put(map, "version", version)))
    end

    assert Grammar.compatible?("1.2.3", "1.2.9")
    assert Grammar.compatible?("0.2.3+one", "0.2.3+two")
    refute Grammar.compatible?("0.2.3", "0.2.4")
    refute Grammar.compatible?("1.2.3-a", "1.2.3-b")
    refute Grammar.compatible?("1.2.3", "1.3.3")
  end

  test "receipt constructors reject missing, extra, wrong and forged values" do
    d = F.descriptor(F.native_map())

    for {module, map} <- [
          {Registration, F.registration_map(d)},
          {Verification, F.verification_map(d)},
          {Trust, F.trust_map(d)},
          {Policy, F.policy_map(d)}
        ] do
      assert {:ok, receipt} = module.new(map)

      for key <- Map.keys(map) do
        assert {:error, %Error{}} = module.new(Map.delete(map, key))
      end

      assert {:error, %Error{}} = module.new(Map.put(map, "extra", "secret"))
      assert {:error, %Error{}} = module.new(nil)

      assert {:error, %Error{}} =
               Wotex.Runtime.Implementation.Record.validate(
                 %{receipt | sha256: F.hash("f")},
                 module
               )
    end

    i = F.inputs(d)

    for key <- Map.keys(Map.from_struct(i)) do
      assert {:error, %Error{}} = Inputs.new(Map.delete(Map.from_struct(i), key))
    end

    assert {:error, %Error{}} =
             Inputs.new(%{
               Map.from_struct(i)
               | registrations: %{"wrong" => hd(Map.values(i.registrations))}
             })

    assert {:error, %Error{}} = Descriptor.to_map(%{d | value: Map.put(d.value, "id", "other")})
  end

  test "registration refusal precedes trust and policy; no missing grants are silently omitted" do
    d = F.descriptor()
    i = F.inputs(d)

    assert {:error, %Error{code: :registration_missing, phase: :compatibility}} =
             Admission.new(d, %{i | registrations: %{}})

    assert {:error, %Error{code: :incompatible_api}} =
             Admission.new(d, %{i | apis: [%{"id" => "wotex.codec", "version" => "2.0.0"}]})

    assert {:error, %Error{code: :incompatible_binding}} =
             Admission.new(d, %{i | bindings: [%{"id" => "unknown", "version" => "1.0.0"}]})

    {:ok, p} = Policy.new(Map.put(i.policy.value, "security_status", "denied"))
    assert {:error, %Error{code: :security_denied}} = Admission.new(d, %{i | policy: p})
    {:ok, p} = Policy.new(put_in(i.policy.value, ["enforcement", "guarantees"], ["memory"]))
    assert {:error, %Error{code: :enforcement_unavailable}} = Admission.new(d, %{i | policy: p})
  end

  test "exact native receipt, closure, immutable deployment and security expiry are required" do
    d = F.descriptor(F.native_map())
    i = F.inputs(d)
    assert {:ok, a} = Admission.new(d, i)
    assert a.value["verification_sha256"] == i.verification.sha256
    assert {:error, %Error{code: :artifact_unverified}} = Admission.new(d, %{i | verification: nil})

    assert {:error, %Error{code: :target_mismatch}} =
             Admission.new(d, %{i | target: "linux-x86-64"})

    {:ok, v} =
      Verification.new(put_in(i.verification.value, ["artifact", "payload_identity"], F.hash("f")))

    assert {:error, %Error{code: :identity_mismatch}} = Admission.new(d, %{i | verification: v})

    {:ok, r} =
      Registration.new(
        put_in(i.registrations[d.value["id"]].value, ["enforcement", "guarantees"], ["memory"])
      )

    assert {:error, %Error{code: :deployment_mutable}} =
             Admission.new(d, %{i | registrations: %{d.value["id"] => r}})

    exception = %{
      "id" => "exception.1",
      "payload_identity" => d.value["artifact"]["payload_identity"],
      "scope" => "consumer",
      "expires_at_ms" => 100,
      "decision_sha256" => F.hash()
    }

    {:ok, v} = Verification.new(Map.put(i.verification.value, "security_exception", exception))
    assert {:error, %Error{code: :security_denied}} = Admission.new(d, %{i | verification: v})
  end

  test "freshness binds policy, registration, trust and earliest horizon, equality is expired" do
    d = F.descriptor()
    i = F.inputs(d)
    {:ok, t} = Trust.new(Map.put(i.trust.value, "valid_until_ms", 200))
    {:ok, p} = Policy.new(Map.put(i.policy.value, "valid_until_ms", 150))
    i = %{i | trust: t, policy: p}
    {:ok, a} = Admission.new(d, i)
    assert a.value["valid_until_ms"] == 150
    assert :ok = Admission.revalidate(a, %{i | now_ms: 149})
    assert {:error, %Error{code: :stale_admission}} = Admission.revalidate(a, %{i | now_ms: 150})
    assert {:error, %Error{code: :trust_expired}} = Admission.revalidate(a, %{i | now_ms: 200})
    {:ok, p} = Policy.new(Map.put(i.policy.value, "revision", "policy.2"))
    assert {:error, %Error{code: :stale_admission}} = Admission.revalidate(a, %{i | policy: p})
    assert {:error, %Error{code: :stale_admission}} = Admission.revalidate(a, %{i | now_ms: 99})
    assert {:error, %Error{}} = Admission.revalidate(%{a | sha256: F.hash()}, i)
  end

  test "verified update requires threshold, role coverage, high water and bounded horizon" do
    d = F.descriptor()

    update = %{
      "verifier_profile" => "consumer.update",
      "verifier_revision" => "update.1",
      "root_revision" => "root.1",
      "signature_receipt_sha256" => F.hash(),
      "metadata_versions" => %{"root" => 2},
      "high_water_versions" => %{"root" => 1},
      "threshold_required" => 2,
      "verified_signers" => ["key.1", "key.2"],
      "expires_at_ms" => 200,
      "revocation_revision" => "revocation.1",
      "rollback_checked" => true
    }

    map =
      F.trust_map(d)
      |> Map.merge(%{"mode" => "verified_update", "valid_until_ms" => 200, "update" => update})

    assert {:ok, t} = Trust.new(map)
    i = %{F.inputs(d) | trust: t}
    assert {:ok, _} = Admission.new(d, i)
    assert {:error, %Error{code: :trust_expired}} = Admission.new(d, %{i | now_ms: 200})

    for bad <- [
          %{"verified_signers" => ["key.1"]},
          %{"rollback_checked" => false},
          %{"metadata_versions" => %{"root" => 0}},
          %{"high_water_versions" => %{"root" => 3}},
          %{"metadata_versions" => %{"other" => 2}}
        ] do
      assert {:error, %Error{}} = Trust.new(Map.put(map, "update", Map.merge(update, bad)))
    end

    assert {:error, %Error{}} = Trust.new(Map.put(map, "valid_until_ms", nil))
    assert {:error, %Error{}} = Trust.new(Map.put(map, "valid_until_ms", 201))
  end

  test "configuration callbacks run once after bounds and sanitize raised, exited and thrown text" do
    d = F.descriptor()
    {:ok, a} = Admission.new(d, F.inputs(d))
    key = F.key()

    for callback <- [
          fn _, _ -> raise "secret-canary" end,
          fn _, _ -> exit("secret-canary") end,
          fn _, _ -> throw("secret-canary") end,
          fn _, _ -> {:error, "secret-canary"} end
        ] do
      assert {:error, %Error{code: :invalid_configuration} = error} =
               Plan.new(a, %{}, key, callback)

      refute inspect(error) =~ "secret-canary"
    end

    assert {:error, %Error{}} =
             Plan.new(a, %{"x" => 1.0}, key, fn _, _ -> flunk("must not run") end)

    assert {:error, %Error{}} =
             Plan.new(a, %{}, %{key | generation: 0}, fn _, _ -> flunk("must not run") end)

    assert {:error, %Error{code: :invalid_instance}} =
             InstanceKey.new(%{consumer_scope: "consumer", instance_id: "id", generation: 0})

    assert %Error{code: :invalid_admission_inputs, field: nil} =
             Error.new(:foreign, :parse, %{field: "secret-canary"})

    assert %Error{class: :permanent} = Error.new(:effect_unknown, :request, %{})
  end
end
