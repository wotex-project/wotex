defmodule Wotex.Profiles.ArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Profiles.{Definition, Definitions, Profile, Unit}

  test "original bytes and unseen quantity survive the public archive boundary" do
    limits = Jason.decode!(File.read!("limits.json"))
    expected = Jason.decode!(File.read!("identities.json"))
    family = System.fetch_env!("PROFILE_FAMILY")

    for {kind, module} <- [{"profile", Profile}, {"definition", Definition}] do
      bytes = File.read!(kind <> ".json")
      assert {:ok, value} = module.parse(bytes, limits)
      assert value.raw_sha256 == expected[family <> "-" <> kind]["raw_sha256"]
      assert value.semantic_sha256 == expected[family <> "-" <> kind]["semantic_sha256"]
      assert {:ok, reference} = module.reference(value, limits)
      assert reference["sha256"] == value.semantic_sha256
      assert {:ok, data} = module.to_map(value, limits)
      assert data == Jason.decode!(bytes)
      assert {:ok, reconstructed} = module.new(value, limits)
      assert reconstructed.raw_sha256 == nil
    end

    assert {:ok, definition} = Definition.parse(File.read!("definition.json"), limits)
    assert {:ok, [_]} = Definitions.new([definition], limits)
    assert {:ok, unit} = Unit.new(definition.data["unit"], limits)

    assert unit.data["quantity_kind"] in [
             "urn:example:quantity:particle-number-density",
             "urn:example:quantity:sample-coherence"
           ]

    assert {:ok, profile} = Profile.parse(File.read!("profile.json"), limits)
    assert {:ok, ref} = Definition.reference(definition, limits)
    assert hd(profile.data["channels"])["semantic"] == ref
  end

  test "the library has no application callback or consumer-specific mechanics" do
    for app <- [:wotex_profiles, :wotex_runtime, :wotex] do
      assert Application.spec(app, :mod) in [nil, []]
    end

    limits = Jason.decode!(File.read!("limits.json"))
    data = Jason.decode!(File.read!("definition.json"))

    assert {:error, %Wotex.Profiles.Error{code: :unsupported_schema}} =
             Definition.new(put_in(data, ["value_schema", "pattern"], "execute"), limits)
  end
end
