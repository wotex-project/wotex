defmodule ProfileArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Compiler, Definition, Interpreter}
  alias Wotex.Routines.{Basis, Error, Input, InputMapping}

  defp fixture do
    v = Jason.decode!(File.read!("input.json"))

    case System.fetch_env!("WOTEX_ROUTINES_INPUT_FAMILY") do
      "industrial" -> {v, 2510}
      "research" -> research(v)
    end
  end

  defp research(v) do
    unit = %{
      "quantity_kind" => "urn:example:research:unseen-ratio",
      "dimension" => [0, 0, 0, 0, 0, 0, 0],
      "scale_n" => "1",
      "scale_d" => "1",
      "offset_n" => "0",
      "offset_d" => "1"
    }

    definition = Map.merge(v["definition"], %{"id" => "urn:example:research:ratio", "unit" => unit})
    {:ok, ref} = Definition.reference(definition, v["reader_limits"])

    profile =
      v["profile"]
      |> Map.put("id", "urn:example:research:profile")
      |> put_in(["channels", Access.at(0), "semantic"], ref)
      |> put_in(["channels", Access.at(0), "conversion", "scale_d"], "1000")

    closure = Map.put(v["closure"], "definitions", [definition])

    basis =
      v["basis"]
      |> put_in(["value", "unit"], %{
        "dimension" => "fraction",
        "name" => "millionths",
        "scale_n" => 1,
        "scale_d" => 1_000_000,
        "offset_n" => 0,
        "offset_d" => 1,
        "min" => 0,
        "max" => 1_000_000
      })
      |> put_in(["output"], nil)

    {:ok, digest} = Basis.semantic_digest(basis, v["limits"])
    basis = Map.put(basis, "semantic_digest", digest)
    basis_ref = Map.take(basis, ~w(id version semantic_digest))

    registry =
      Enum.map(v["registry"], fn record ->
        record =
          if record["id"] == basis["id"],
            do: Map.put(record, "semantic_digest", digest),
            else: record

        Map.update!(record, "requires", &Enum.map(&1, fn ref -> replace_ref(ref, basis_ref) end))
      end)

    mapping =
      v["mapping"]
      |> Map.merge(%{
        "external_unit" => unit,
        "basis" => basis,
        "legacy_basis_ref" => basis_ref,
        "semantic_ref" => ref
      })

    {Map.merge(v, %{
       "profile" => profile,
       "closure" => closure,
       "registry" => registry,
       "mapping" => mapping
     }), 251_000}
  end

  defp replace_ref(ref, basis_ref), do: if(ref["id"] == basis_ref["id"], do: basis_ref, else: ref)

  defp interpreted(v) do
    {:ok, projection} =
      Compiler.compile(v["profile"], v["closure"], v["capture"], v["reader_limits"])

    report =
      Map.take(
        v["proposal"],
        ~w(channel_id source_ref source_epoch sequence source_time receipt_time continuity quality quality_reason)
      )
      |> Map.merge(%{
        "profile_sha256" => projection.data["profile_sha256"],
        "binding" => v["capture"]["binding"],
        "capture_epoch" => v["capture"]["capture_epoch"],
        "value" => %{"type" => "sint", "value" => "251"}
      })

    {:ok, proposal} = Interpreter.project(projection, report, v["reader_limits"])

    unsigned =
      v["mapping"]
      |> Map.delete("sha256")
      |> Map.merge(Map.take(proposal, ~w(profile_sha256 closure_sha256)))

    {:ok, digest} = InputMapping.digest(unsigned, v["registry"], v["limits"])
    mapping = Map.put(unsigned, "sha256", digest)

    registry =
      Enum.map(v["registry"], fn record ->
        if record["id"] == mapping["id"],
          do: Map.put(record, "semantic_digest", "sha256:" <> digest),
          else: record
      end)

    metadata = Map.put(v["metadata"], "profile_digest", "sha256:" <> proposal["profile_sha256"])

    context = %{
      "registry" => registry,
      "limits" => v["limits"],
      "reader_limits" => v["reader_limits"]
    }

    {proposal, mapping, metadata, context}
  end

  test "independent supplied quantity joins using public APIs from extracted archives" do
    {v, expected} = fixture()
    {proposal, mapping, metadata, context} = interpreted(v)
    assert {:ok, result} = Input.project(proposal, mapping, metadata, context)
    assert result["fact"].data["value"] == expected
    assert result["fact"].data["source_uncertainty_ms"] == 2
    assert result["fact"].data["receipt_ms"] == 101
    assert result["correspondence_ref"] == mapping["correspondence_ref"]
  end

  test "unsupported shape and changed meaning cannot become a routine value" do
    {v, _} = fixture()
    {proposal, mapping, metadata, context} = interpreted(v)

    assert {:error, %Error{code: :unsupported_representation}} =
             Input.project(
               Map.put(proposal, "normalized_value", %{"type" => "list", "items" => []}),
               mapping,
               metadata,
               context
             )

    changed = put_in(proposal, ["unit", "quantity_kind"], "urn:example:other-quantity")
    assert {:error, %Error{code: :stale_basis}} = Input.project(changed, mapping, metadata, context)

    pressure =
      mapping
      |> Map.delete("sha256")
      |> put_in(["external_unit", "dimension"], [-1, 1, -2, 0, 0, 0, 0])

    assert {:error, %Error{code: :incompatible_dimension}} =
             InputMapping.digest(pressure, context["registry"], context["limits"])
  end

  test "replacement and replay never reuse old qualification or refresh an observation" do
    {v, _} = fixture()
    {proposal, mapping, metadata, context} = interpreted(v)

    assert {:error, %Error{code: :stale_basis}} =
             Input.project(
               Map.put(proposal, "capture_digest", String.duplicate("0", 64)),
               mapping,
               metadata,
               context
             )

    proposal = Map.put(proposal, "continuity", "retained")

    assert {:error, %Error{code: :stale_basis}} =
             Input.project(proposal, mapping, metadata, context)

    metadata = Map.merge(metadata, %{"continuity" => "lost", "replay" => "retained"})
    assert {:ok, result} = Input.project(proposal, mapping, metadata, context)
    assert result["fact"].data["expires_ms"] == metadata["expires_ms"]

    missing =
      Map.update!(context, "registry", &Enum.reject(&1, fn ref -> ref["id"] == mapping["id"] end))

    assert {:error, %Error{code: :unsupported_mapping}} =
             Input.project(proposal, mapping, metadata, missing)
  end
end
