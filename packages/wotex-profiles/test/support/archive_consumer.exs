defmodule Wotex.Profiles.ArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Profiles.{
    Binding,
    Capture,
    Compiler,
    Definition,
    Definitions,
    Interpreter,
    Profile,
    Projection,
    Unit
  }

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

  test "generic exact coordinates and quantity refusal survive both archived consumers" do
    limits = Jason.decode!(File.read!("limits.json"))
    unit = Jason.decode!(File.read!("definition.json"))["unit"]
    source = Map.merge(unit, %{"scale_n" => "1", "scale_d" => "100"})
    value = %{"type" => "sint", "value" => "25"}

    assert {:ok, %{"type" => "decimal", "coefficient" => "25", "exponent" => -2}} =
             Unit.convert(value, source, unit, limits)

    assert {:error, %Wotex.Profiles.Error{code: :unsupported_semantics}} =
             Unit.convert(
               value,
               Map.put(source, "quantity_kind", "urn:example:quantity:unrelated"),
               unit,
               limits
             )

    assert {:error, %Wotex.Profiles.Error{code: :inexact_conversion}} =
             Unit.convert(
               %{"type" => "sint", "value" => "1"},
               Map.put(unit, "scale_d", "3"),
               unit,
               limits
             )
  end

  test "multi-channel compile and report interpretation use only public archived contracts" do
    limits = Jason.decode!(File.read!("limits.json"))
    definition = Jason.decode!(File.read!("definition.json"))
    profile = Jason.decode!(File.read!("profile.json"))
    binding = Jason.decode!(File.read!("installed-binding.json"))
    contracts = Jason.decode!(File.read!("installed-contracts.json"))
    assert {:ok, bref} = Binding.reference(binding, limits)
    [channel] = profile["channels"]

    channel =
      if definition["value_schema"]["type"] == "number" do
        Map.put(channel, "conversion", %{
          "kind" => "affine",
          "scale_n" => "1",
          "scale_d" => "100",
          "offset_n" => "0",
          "offset_d" => "1"
        })
      else
        channel
      end

    auxiliary = Map.merge(channel, %{"id" => "auxiliary", "selector" => %{"register" => 5}})
    profile = Map.merge(profile, %{"binding" => bref, "channels" => [auxiliary, channel]})
    model = hd(hd(profile["fingerprint"])["values"])

    capture = %{
      "binding" => bref,
      "capture_epoch" => String.duplicate("c", 32),
      "fields" => %{"model" => model}
    }

    assert {:ok, digest} = Capture.digest(capture, binding, limits)
    capture = Map.put(capture, "digest", digest)
    closure = %{"definitions" => [definition], "bindings" => [binding], "contracts" => contracts}
    assert {:ok, projection} = Compiler.compile(profile, closure, capture, limits)
    assert {:ok, plan} = Projection.to_map(projection, limits)
    assert Enum.map(plan["channel_plans"], & &1["channel_id"]) == ["auxiliary", "sample"]

    value = %{"type" => "sint", "value" => "25"}

    expected =
      if definition["value_schema"]["type"] == "integer",
        do: value,
        else: %{"type" => "decimal", "coefficient" => "25", "exponent" => -2}

    report = %{
      "channel_id" => "auxiliary",
      "profile_sha256" => plan["profile_sha256"],
      "binding" => bref,
      "capture_epoch" => capture["capture_epoch"],
      "source_ref" => "synthetic-source",
      "source_epoch" => String.duplicate("e", 32),
      "sequence" => nil,
      "source_time" => nil,
      "receipt_time" => %{"epoch" => String.duplicate("f", 32), "monotonic_us" => "1"},
      "continuity" => "retained",
      "quality" => "usable",
      "quality_reason" => nil,
      "value" => value
    }

    assert {:ok, proposal} = Interpreter.project(projection, report, limits)
    assert proposal["normalized_value"] == expected
    assert proposal["continuity"] == "retained"
    assert proposal["source_time"] == nil
    assert {:ok, proposal_value} = Wotex.Profiles.Proposal.new(proposal, limits)
    assert {:ok, ^proposal} = Wotex.Profiles.Proposal.to_map(proposal_value, limits)
    assert Wotex.Profiles.Proposal.identity()["id"] == "urn:wotex:profiles:proposal"

    assert {:error, %Wotex.Profiles.Error{code: :stale_basis}} =
             Interpreter.project(
               projection,
               Map.put(report, "capture_epoch", String.duplicate("a", 32)),
               limits
             )
  end

  test "manual authoring, pure reports and actual CLI exit codes agree across archived consumers" do
    alias Wotex.Profiles.{Artifacts, Contract, Draft, Finalized, Validation, ValidationReport}
    limits = Jason.decode!(File.read!("authoring-limits.json"))
    binding = Jason.decode!(File.read!("installed-binding.json"))
    contracts = Jason.decode!(File.read!("installed-contracts.json"))
    definition = Jason.decode!(File.read!("definition.json"))
    profile = Jason.decode!(File.read!("profile.json"))
    assert {:ok, ref} = Binding.reference(binding, limits["reader"])
    profile = Map.put(profile, "binding", ref)

    profile =
      put_in(profile, ["channels", Access.at(0), "semantic"], %{
        "local" => Map.take(definition, ~w(id version))
      })

    draft = %{
      "format" => "wotex.profile.draft@1",
      "profile" => profile,
      "definitions" => [definition]
    }

    assert {:ok, contract} = Contract.export([binding], contracts, limits, Artifacts.current())
    assert {:ok, contract_bytes} = Contract.encode(contract)
    assert {:ok, ^contract} = Contract.parse(contract_bytes)
    assert {:ok, %Finalized{} = final} = Draft.finalize(Jason.encode!(draft), contract)
    assert {:ok, report} = Validation.check(final.bundle_bytes, contract, nil)
    assert {:ok, report_bytes} = ValidationReport.encode(report, contract)
    assert report.data["disposition"] == "compatible"
    File.write!("contract.json", contract_bytes)
    File.write!("candidate.json", final.bundle_bytes)
    File.write!("draft.json", Jason.encode!(draft))

    {output, 0} =
      System.cmd(
        "mix",
        ["wotex.profiles.validate", "--contract", "contract.json", "--candidate", "candidate.json"],
        env: [{"HEX_API_KEY", nil}, {"GITHUB_TOKEN", nil}, {"GH_TOKEN", nil}],
        stderr_to_stdout: true
      )

    assert String.trim(output) == report_bytes

    {output, 0} =
      System.cmd(
        "mix",
        [
          "wotex.profiles.finalize",
          "--contract",
          "contract.json",
          "--candidate",
          "draft.json",
          "--output",
          "derived.json"
        ],
        env: [{"HEX_API_KEY", nil}, {"GITHUB_TOKEN", nil}, {"GH_TOKEN", nil}],
        stderr_to_stdout: true
      )

    assert Jason.decode!(output)["bundle_sha256"] == final.bundle_sha256
    assert File.read!("derived.json") == final.bundle_bytes
    File.write!("candidate.json", "{}")

    {output, 1} =
      System.cmd(
        "mix",
        ["wotex.profiles.validate", "--contract", "contract.json", "--candidate", "candidate.json"],
        env: [{"HEX_API_KEY", nil}, {"GITHUB_TOKEN", nil}, {"GH_TOKEN", nil}],
        stderr_to_stdout: true
      )

    assert Jason.decode!(output)["disposition"] == "invalid"

    {output, 2} =
      System.cmd(
        "mix",
        [
          "wotex.profiles.validate",
          "--contract",
          "missing-private-path",
          "--candidate",
          "candidate.json"
        ],
        env: [{"HEX_API_KEY", nil}, {"GITHUB_TOKEN", nil}, {"GH_TOKEN", nil}],
        stderr_to_stdout: true
      )

    refute output =~ "missing-private-path"
    assert Jason.decode!(output)["error"]["code"] == "invalid_input"
  end
end
