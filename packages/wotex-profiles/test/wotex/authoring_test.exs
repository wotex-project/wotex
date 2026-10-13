defmodule Wotex.Profiles.AuthoringTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Artifacts, Contract, Draft, Error, Finalized, Validation, ValidationReport}
  alias Wotex.Profiles.Test.Fixtures, as: F

  defp contract(overrides \\ %{}) do
    {:ok, value} =
      Contract.export(
        [F.json("installed-binding")],
        F.json("installed-contracts"),
        Map.merge(F.json("authoring-limits"), overrides),
        Artifacts.current()
      )

    value
  end

  defp finalized do
    {:ok, %Finalized{} = value} = Draft.finalize(F.bytes("authoring-draft"), contract())
    value
  end

  defp disposition(%ValidationReport{} = report, contract) do
    assert {:ok, data} = ValidationReport.to_map(report, contract)
    data
  end

  test "manual local draft finalization and validation share identities and mechanics" do
    c = contract()
    assert {:ok, %Finalized{} = final} = Draft.finalize(F.bytes("authoring-draft"), c)

    assert final.draft_sha256 ==
             Base.encode16(:crypto.hash(:sha256, F.bytes("authoring-draft")), case: :lower)

    assert final.contract_sha256 == c.sha256
    expected = F.json("authoring-identities")
    assert c.sha256 == expected["contract_sha256"]
    assert c.data["producer"] == expected["producer"]
    assert final.bundle_sha256 == expected["bundle_sha256"]
    assert final.draft_sha256 == expected["draft_sha256"]
    assert {:ok, report} = Validation.check(final.bundle_bytes, c, nil)
    assert disposition(report, c)["disposition"] == "compatible"
    assert disposition(report, c)["capture_status"] == "not_supplied"
    assert {:ok, report} = Validation.check(final.bundle_bytes, c, F.json("capture"))
    assert disposition(report, c)["capture_status"] == "matched"
    assert {:ok, bytes} = ValidationReport.encode(report, c)
    assert Jason.decode!(bytes) == report.data
  end

  test "unsupported selectors are structurally valid candidates but never compatible" do
    c = contract()
    final = finalized()
    data = Jason.decode!(final.bundle_bytes)

    data =
      put_in(data, ["profile", "channels", Access.at(0), "selector"], %{
        "foreign-register" => "secret-canary"
      })

    assert {:ok, report} = Validation.check(F.encode(data), c, F.json("capture"))
    result = disposition(report, c)
    assert result["disposition"] == "invalid"
    assert result["capture_status"] == "not_checked"
    [diagnostic] = result["diagnostics"]
    assert diagnostic["phase"] == "binding"
    assert diagnostic["code"] == "unsupported_selector"
    refute inspect(result) =~ "canary"
    capture = Map.put(F.json("capture"), "capture_epoch", String.duplicate("a", 32))
    assert {:ok, report} = Validation.check(final.bundle_bytes, c, capture)
    assert disposition(report, c)["capture_status"] == "mismatch"
  end

  test "unreachable, missing, cyclic and forged draft references refuse without repair" do
    c = contract()
    draft = F.json("authoring-draft")

    for changed <- [
          Map.put(draft, "definitions", []),
          Map.put(draft, "definitions", [F.json("research-definition") | draft["definitions"]]),
          put_in(draft, ["profile", "channels", Access.at(0), "semantic"], %{
            "id" => F.definition()["id"],
            "version" => "1.0.0",
            "sha256" => String.duplicate("a", 64)
          })
        ] do
      assert {:ok, %ValidationReport{} = report} = Draft.finalize(F.encode(changed), c)
      assert disposition(report, c)["disposition"] == "invalid"
    end

    local = %{"local" => %{"id" => F.definition()["id"], "version" => "1.0.0"}}
    cyclic = put_in(draft, ["definitions", Access.at(0), "requires"], [local])
    assert {:ok, report} = Draft.finalize(F.encode(cyclic), c)
    assert hd(disposition(report, c)["diagnostics"])["code"] == "cyclic_reference"
    duplicate = Map.put(draft, "definitions", draft["definitions"] ++ draft["definitions"])
    assert {:ok, report} = Draft.finalize(F.encode(duplicate), c)
    assert hd(disposition(report, c)["diagnostics"])["code"] == "reference_conflict"
  end

  test "shape, syntax, API and resource failures retain honest outcome distinctions" do
    c = contract()

    for bytes <- [
          "{",
          "{\"format\":1,\"format\":2}",
          F.encode(Map.put(F.json("authoring-draft"), "foreign-secret", true))
        ] do
      assert {:ok, %ValidationReport{} = report} = Draft.finalize(bytes, c)
      assert disposition(report, c)["disposition"] == "invalid"
      refute inspect(report) =~ "foreign-secret"
    end

    assert {:error, %Error{code: :invalid_input}} = Draft.finalize(1, c)
    assert {:error, %Error{code: :invalid_contract}} = Draft.finalize("{}", %{})

    assert {:error, %Error{code: :input_limit}} =
             Draft.finalize(F.bytes("authoring-draft"), contract(%{"max_bundle_bytes" => 1}))

    assert {:error, %Error{code: :input_limit}} =
             Draft.finalize(F.bytes("authoring-draft"), contract(%{"max_check_steps" => 1}))

    assert {:error, %Error{code: :report_limit}} =
             Draft.finalize("{}", contract(%{"max_report_bytes" => 1}))
  end

  test "diagnostics use safe sorted pointers and retain an invalid prefix within limits" do
    c = contract(%{"max_diagnostics" => 1})
    assert {:ok, report} = Validation.check("{}", c, nil)
    data = disposition(report, c)
    assert data["disposition"] == "invalid"
    assert length(data["diagnostics"]) == 1
    assert data["truncated"] == true
    assert {:error, %Error{}} = ValidationReport.to_map(Map.put(report, :extra, "secret"), c)

    assert {:error, %Error{}} =
             ValidationReport.to_map(
               %{report | data: Map.put(data, "contract_sha256", String.duplicate("a", 64))},
               c
             )

    assert {:error, %Error{}} =
             ValidationReport.to_map(
               %{report | data: Map.put(data, "disposition", "compatible")},
               c
             )
  end

  test "transitive local DAG resolution is independent of input order and preserves exact external contracts" do
    c = contract()
    draft = F.json("authoring-draft")
    child = F.json("research-definition")
    local = %{"local" => Map.take(child, ~w(id version))}

    parent =
      F.definition()
      |> Map.put("requires", [local])
      |> Map.put("behaviour", hd(F.json("installed-contracts")))

    draft = Map.put(draft, "definitions", [parent, child])
    assert {:ok, %Finalized{} = one} = Draft.finalize(F.encode(draft), c)

    assert {:ok, %Finalized{} = two} =
             Draft.finalize(F.encode(Map.put(draft, "definitions", [child, parent])), c)

    assert one.bundle_bytes == two.bundle_bytes
    assert {:ok, report} = Validation.check(one.bundle_bytes, c, nil)
    assert disposition(report, c)["disposition"] == "compatible"
    bundle = Jason.decode!(one.bundle_bytes)
    reversed = Map.put(bundle, "definitions", Enum.reverse(bundle["definitions"]))
    assert {:ok, report} = Validation.check(F.encode(reversed), c, nil)
    assert disposition(report, c)["disposition"] == "invalid"
    repeated = Map.put(draft, "profile", Map.put(draft["profile"], "requires", [local]))
    assert {:ok, %Finalized{}} = Draft.finalize(F.encode(repeated), c)
    raw = hd(F.json("installed-contracts"))

    assert {:ok, %Finalized{}} =
             Draft.finalize(F.encode(put_in(draft, ["profile", "requires"], [raw])), c)

    for external <- [
          Map.put(raw, "id", "urn:example:missing"),
          Map.put(raw, "sha256", String.duplicate("a", 64))
        ] do
      assert {:ok, report} =
               Draft.finalize(F.encode(put_in(draft, ["profile", "requires"], [external])), c)

      assert disposition(report, c)["disposition"] == "invalid"
    end
  end

  test "normalization cannot turn unsupported schema mechanics into a compatible report" do
    c = contract()
    draft = F.json("authoring-draft")

    schema = %{
      "type" => "object",
      "properties" => %{"a" => %{"type" => "integer"}, "b" => %{"type" => "integer"}},
      "required" => ["b", "a"],
      "additionalProperties" => false
    }

    descriptor =
      F.definition()
      |> Map.put("value_schema", schema)
      |> Map.put("unit", nil)

    assert {:ok, %Finalized{} = final} =
             Draft.finalize(F.encode(Map.put(draft, "definitions", [descriptor])), c)

    assert {:ok, report} = Validation.check(final.bundle_bytes, c, nil)
    assert disposition(report, c)["disposition"] == "invalid"
    limited = contract(%{"reader" => Map.put(F.limits(), "max_definitions", 1)})

    assert {:error, %Error{code: :input_limit}} =
             Draft.finalize(
               F.encode(Map.put(draft, "definitions", [descriptor, F.json("research-definition")])),
               limited
             )

    assert {:error, %Error{code: :input_limit}} =
             Validation.check(final.bundle_bytes, contract(%{"max_check_steps" => 1}), nil)

    assert {:error, %Error{code: :report_limit}} =
             Validation.check("{}", contract(%{"max_report_bytes" => 1}), nil)
  end

  test "draft literal tables normalize canonical source order without merging duplicate entries" do
    c = contract()
    draft = F.json("authoring-draft")

    entry = fn source, target ->
      %{
        "source" => %{"type" => "sint", "value" => source},
        "target" => %{"type" => "sint", "value" => target}
      }
    end

    conversion = %{"kind" => "table", "entries" => [entry.("2", "20"), entry.("1", "10")]}
    draft = put_in(draft, ["profile", "channels", Access.at(0), "conversion"], conversion)
    assert {:ok, %Finalized{} = result} = Draft.finalize(F.encode(draft), c)
    bundle = Jason.decode!(result.bundle_bytes)

    assert hd(bundle["profile"]["channels"])["conversion"]["entries"] == [
             entry.("1", "10"),
             entry.("2", "20")
           ]

    assert {:ok, report} = Validation.check(result.bundle_bytes, c, nil)
    assert disposition(report, c)["disposition"] == "compatible"

    duplicate =
      put_in(draft, ["profile", "channels", Access.at(0), "conversion", "entries"], [
        entry.("1", "10"),
        entry.("1", "20")
      ])

    assert {:ok, %ValidationReport{} = report} = Draft.finalize(F.encode(duplicate), c)
    assert disposition(report, c)["disposition"] == "invalid"
  end
end
