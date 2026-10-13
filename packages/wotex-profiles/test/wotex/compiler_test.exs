defmodule Wotex.Profiles.CompilerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Binding, Checked, Compiler, Definition, Error, Profile, Projection}
  alias Wotex.Profiles.Test.Fixtures, as: F

  defp closure,
    do: %{
      "definitions" => [F.definition()],
      "bindings" => [F.json("installed-binding")],
      "contracts" => F.json("installed-contracts")
    }

  defp profile, do: F.json("compiler-profile")

  test "independent identities and literal capture produce checked inert plans" do
    expected = F.json("compiled-identities")
    assert Compiler.identity() == expected["compiler_ref"]
    assert {:ok, checked} = Compiler.check(profile(), closure(), F.limits())
    assert Map.take(checked.data, ~w(profile_sha256 closure_sha256 compiler_ref)) == expected
    assert {:ok, data} = Checked.to_map(checked, F.limits())
    assert data == checked.data
    [plan] = data["channel_plans"]
    assert plan["disposition"] == "supported"
    assert plan["operations"] == ["readproperty"]
    assert plan["reason"] == nil
    refute Map.has_key?(plan["definition"], "annotations")
    assert {:ok, projection} = Compiler.compile(profile(), closure(), F.json("capture"), F.limits())
    assert {:ok, serialized} = Projection.to_map(projection, F.limits())
    assert serialized["capture_digest"] == F.json("capture")["digest"]
    assert {:error, %Error{code: :invalid_input}} = Projection.to_map(serialized, F.limits())
  end

  test "unrelated valid entries do not change the selected closure identity" do
    assert {:ok, first} = Compiler.check(profile(), closure(), F.limits())
    expanded = put_in(closure(), ["definitions"], [F.json("research-definition"), F.definition()])
    assert {:ok, second} = Compiler.check(profile(), expanded, F.limits())
    assert first.data == second.data
    assert {:ok, definition} = Definition.new(F.definition(), F.limits())
    assert {:ok, binding} = Binding.new(F.json("installed-binding"), F.limits())
    assert {:ok, profile} = Profile.new(profile(), F.limits())

    native = %{
      "definitions" => [definition],
      "bindings" => [binding],
      "contracts" => F.json("installed-contracts")
    }

    assert {:ok, native_checked} = Compiler.check(profile, native, F.limits())
    assert native_checked.data == first.data
  end

  test "reachable references expose the exact independently frozen closure while excluding unused data" do
    assert {:ok, references} = Compiler.references(profile(), closure(), F.limits())

    assert Enum.map(references, & &1["id"]) == [
             "urn:example:binding:register",
             "urn:example:decoder:register-output",
             "urn:example:profile:industrial",
             "urn:example:semantic:industrial"
           ]

    {:ok, bytes} = Wotex.JSON.encode(references)

    digest =
      Base.encode16(:crypto.hash(:sha256, "wotex.profile.closure@1\n" <> bytes), case: :lower)

    assert digest == F.json("compiled-identities")["closure_sha256"]
    expanded = put_in(closure(), ["definitions"], [F.json("research-definition"), F.definition()])
    assert {:ok, ^references} = Compiler.references(profile(), expanded, F.limits())

    assert {:error, %Error{code: :missing_reference}} =
             Compiler.references(profile(), Map.put(closure(), "definitions", []), F.limits())

    assert {:error, %Error{code: :input_limit}} =
             Compiler.references(profile(), closure(), Map.put(F.limits(), "max_dependencies", 2))
  end

  test "missing or conflicting exact closure refuses without alias repair" do
    for changed <- [
          Map.put(closure(), "definitions", []),
          Map.put(closure(), "bindings", []),
          Map.put(closure(), "contracts", [])
        ] do
      assert {:error, %Error{code: :missing_reference}} =
               Compiler.check(profile(), changed, F.limits())
    end

    assert {:error, %Error{code: :reference_conflict}} =
             Compiler.check(
               put_in(profile(), ["binding", "sha256"], String.duplicate("c", 64)),
               closure(),
               F.limits()
             )

    assert {:error, %Error{code: :reference_conflict}} =
             Compiler.check(
               profile(),
               put_in(closure(), ["definitions"], [F.definition(), F.definition()]),
               F.limits()
             )

    assert {:error, %Error{code: :reference_conflict}} =
             Compiler.check(
               profile(),
               Map.put(closure(), "contracts", [
                 Map.take(F.json("installed-binding"), ~w(id version sha256))
               ]),
               F.limits()
             )

    assert {:error, %Error{code: :unsupported_binding}} =
             Compiler.check(
               put_in(profile(), ["fingerprint", Access.at(0), "field"], "unregistered"),
               closure(),
               F.limits()
             )
  end

  test "declared cycles refuse before edge hash conflicts and optional exclusion" do
    a =
      Map.put(F.definition(), "requires", [
        %{
          "id" => "urn:example:semantic:cycle",
          "version" => "1.0.0",
          "sha256" => String.duplicate("a", 64)
        }
      ])

    b =
      F.definition()
      |> Map.put("id", "urn:example:semantic:cycle")
      |> Map.put("requires", [Map.fetch!(hd(profile()["channels"]), "semantic")])

    assert {:ok, ref} = Definition.reference(a, F.limits())
    p = put_in(profile(), ["channels", Access.at(0), "semantic"], ref)
    c = put_in(closure(), ["definitions"], [a, b])
    assert {:error, %Error{code: :cyclic_reference}} = Compiler.check(p, c, F.limits())

    assert {:error, %Error{code: :cyclic_reference}} =
             Compiler.check(put_in(p, ["channels", Access.at(0), "required"], false), c, F.limits())
  end

  test "optional missing or unsupported channels are explicit exclusions" do
    optional = put_in(profile(), ["channels", Access.at(0), "required"], false)

    for {p, c, reason} <- [
          {optional, Map.put(closure(), "definitions", []), "missing_reference"},
          {put_in(optional, ["channels", Access.at(0), "selector"], %{"foreign" => "secret"}),
           closure(), "unsupported_selector"},
          {put_in(optional, ["channels", Access.at(0), "invalid_values"], [
             %{"type" => "bytes", "base64" => "AA=="}
           ]), closure(), "codec_required"}
        ] do
      assert {:ok, checked} = Compiler.check(p, c, F.limits())
      [plan] = checked.data["channel_plans"]
      assert plan["disposition"] == "excluded"
      assert plan["operations"] == []
      assert plan["reason"] == reason

      assert {:error, %Error{}} =
               Compiler.check(
                 put_in(p, ["channels", Access.at(0), "required"], true),
                 c,
                 F.limits()
               )
    end

    required = Map.put(optional, "requires", [hd(profile()["channels"])["semantic"]])

    assert {:error, %Error{code: :missing_reference}} =
             Compiler.check(required, Map.put(closure(), "definitions", []), F.limits())
  end

  test "capture mismatch and forged native plans cannot be reused" do
    assert {:ok, checked} = Compiler.check(profile(), closure(), F.limits())
    assert {:ok, projection} = Compiler.compile(profile(), closure(), F.json("capture"), F.limits())

    assert {:error, %Error{code: :stale_basis}} =
             Checked.to_map(
               %{
                 checked
                 | data: Map.put(checked.data, "profile_sha256", String.duplicate("f", 64))
               },
               F.limits()
             )

    assert {:error, %Error{code: :stale_basis}} =
             Projection.to_map(
               %{
                 projection
                 | data: Map.put(projection.data, "capture_epoch", String.duplicate("f", 32))
               },
               F.limits()
             )

    for value <- [checked, projection] do
      module = value.__struct__
      assert {:error, %Error{}} = module.to_map(Map.put(value, :extra, "secret"), F.limits())

      assert {:error, %Error{code: :stale_basis}} =
               module.to_map(value, Map.put(F.limits(), "max_channels", 1))

      assert {:error, %Error{}} = module.to_map(%{value | inputs: %{}}, F.limits())
    end

    capture = Map.put(F.json("capture"), "fields", %{})

    assert {:ok, digest} =
             Wotex.Profiles.Capture.digest(
               Map.delete(capture, "digest"),
               F.json("installed-binding"),
               F.limits()
             )

    assert {:error, %Error{code: :fingerprint_mismatch}} =
             Compiler.compile(profile(), closure(), Map.put(capture, "digest", digest), F.limits())
  end

  test "whole-input and selected dependency limits are enforced" do
    for {key, amount} <- [{"max_nodes", 1}, {"max_depth", 1}, {"max_dependencies", 3}] do
      assert {:error, %Error{code: :input_limit}} =
               Compiler.check(profile(), closure(), Map.put(F.limits(), key, amount))
    end

    for bad <- [
          %{},
          Map.put(closure(), "foreign", true),
          Map.put(closure(), "definitions", [F.definition() | :bad])
        ] do
      assert {:error, %Error{}} = Compiler.check(profile(), bad, F.limits())
    end

    assert {:error, %Error{code: :input_limit}} =
             Compiler.check(
               profile(),
               Map.put(closure(), "bindings", List.duplicate(F.json("installed-binding"), 65)),
               F.limits()
             )
  end

  test "transitive definitions and installed contracts are memoized in exact closure identity" do
    raw = hd(F.json("installed-contracts"))
    child = F.json("research-definition")
    assert {:ok, child_ref} = Definition.reference(child, F.limits())

    parent =
      F.definition()
      |> Map.put("requires", [child_ref])
      |> Map.put("behaviour", raw)

    assert {:ok, parent_ref} = Definition.reference(parent, F.limits())

    p =
      F.json("compiler-profile")
      |> put_in(["channels", Access.at(0), "semantic"], parent_ref)
      |> Map.put("requires", [raw])

    c = Map.put(closure(), "definitions", [child, parent])
    assert {:ok, checked} = Compiler.check(p, c, F.limits())
    assert {:ok, _} = Checked.to_map(checked, F.limits())

    assert {:error, %Error{code: :missing_reference}} =
             Compiler.check(p, Map.put(c, "definitions", [parent]), F.limits())

    # A known descriptor stays in the closed basis when its selector is unsupported.
    p = put_in(p, ["channels", Access.at(0), "required"], false)
    p = put_in(p, ["channels", Access.at(0), "selector"], %{"register" => -1})
    assert {:ok, excluded} = Compiler.check(p, c, F.limits())
    changed = Map.put(parent, "behaviour", nil)
    assert {:ok, changed_ref} = Definition.reference(changed, F.limits())
    changed_p = put_in(p, ["channels", Access.at(0), "semantic"], changed_ref)

    assert {:ok, changed_checked} =
             Compiler.check(changed_p, Map.put(c, "definitions", [child, changed]), F.limits())

    refute excluded.data["closure_sha256"] == changed_checked.data["closure_sha256"]
  end

  test "descriptor type, operations and installed contract role mismatches refuse executable use" do
    base = F.json("compiler-profile")

    assert {:error, %Error{}} =
             Compiler.check(
               put_in(base, ["channels", Access.at(0), "operations"], ["writeproperty"]),
               closure(),
               F.limits()
             )

    definition = Map.put(F.definition(), "value_schema", %{"type" => "boolean"})
    assert {:ok, ref} = Definition.reference(definition, F.limits())
    p = put_in(base, ["channels", Access.at(0), "semantic"], ref)

    assert {:error, %Error{code: :unsupported_semantics}} =
             Compiler.check(p, Map.put(closure(), "definitions", [definition]), F.limits())

    assert {:error, %Error{code: :unsupported_semantics}} =
             Compiler.check(
               put_in(base, ["binding"], hd(F.json("installed-contracts"))),
               closure(),
               F.limits()
             )

    assert {:error, %Error{}} =
             Compiler.check(base, Map.put(closure(), "bindings", [%{}]), F.limits())

    assert {:error, %Error{code: :reference_conflict}} =
             Compiler.check(
               put_in(
                 base,
                 ["channels", Access.at(0), "semantic", "sha256"],
                 String.duplicate("f", 64)
               ),
               closure(),
               F.limits()
             )

    optional = put_in(base, ["channels", Access.at(0), "required"], false)
    assert {:ok, optional_checked} = Compiler.check(optional, closure(), F.limits())

    assert {:error, %Error{code: :invalid_input}} =
             Checked.to_map(
               %{optional_checked | data: Map.put(optional_checked.data, "foreign", 1)},
               F.limits()
             )
  end

  test "repeated large descriptors cannot expand output beyond its selected envelope" do
    definition =
      put_in(F.definition(), ["value_schema", "description"], String.duplicate("x", 8000))

    assert {:ok, ref} = Definition.reference(definition, F.limits())
    [channel] = profile()["channels"]
    channel = Map.put(channel, "semantic", ref)
    channels = [Map.put(channel, "id", "a"), Map.put(channel, "id", "b")]
    p = Map.put(profile(), "channels", channels)
    c = Map.put(closure(), "definitions", [definition])

    assert {:error, %Error{code: :input_limit}} =
             Compiler.check(p, c, Map.put(F.limits(), "max_bytes", 15_000))

    assert {:ok, _} = Compiler.check(p, c, F.limits())
  end
end
