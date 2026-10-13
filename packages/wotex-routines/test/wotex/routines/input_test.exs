defmodule Wotex.Routines.InputTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Error, Fact, Input, InputMapping}
  alias Wotex.Routines.InputFixtures, as: F

  test "independent identities, public reader and scalar Fact join agree exactly" do
    v = F.vector()

    assert {:ok, projection} =
             Wotex.Profiles.Compiler.compile(
               v["profile"],
               v["closure"],
               v["capture"],
               v["reader_limits"]
             )

    report =
      Map.take(
        v["proposal"],
        ~w(channel_id profile_sha256 source_ref source_epoch sequence source_time receipt_time continuity quality quality_reason)
      )
      |> Map.merge(%{
        "binding" => v["capture"]["binding"],
        "capture_epoch" => v["capture"]["capture_epoch"],
        "value" => %{"type" => "sint", "value" => "251"}
      })

    assert {:ok, proposal} =
             Wotex.Profiles.Interpreter.project(projection, report, v["reader_limits"])

    assert proposal == v["proposal"]

    assert {:ok, digest} =
             InputMapping.digest(Map.delete(v["mapping"], "sha256"), v["registry"], v["limits"])

    assert digest == v["mapping"]["sha256"]
    assert {:ok, result} = Input.project(proposal, v["mapping"], v["metadata"], F.context(v))
    assert result["source_proposal_sha256"] == v["source_proposal_sha256"]

    assert result["fact"].data ==
             Map.merge(v["metadata"], %{
               "value" => 2510,
               "unit" => v["basis"]["value"]["unit"],
               "quality" => "usable"
             })

    assert Map.keys(result) |> Enum.sort() ==
             ~w(correspondence_ref fact mapping_ref source_proposal_sha256)

    assert {:ok, mapping} = InputMapping.new(v["mapping"], v["registry"], v["limits"])
    assert {:ok, same} = Input.project(proposal, mapping, v["metadata"], F.context(v))
    assert same == result
    assert {:ok, _} = Fact.to_map(result["fact"], v["limits"])
    assert {:ok, ref} = InputMapping.reference(mapping, v["registry"], v["limits"])
    assert ref == result["mapping_ref"]

    schema =
      Path.expand("../../../priv/schemas/wro-05-input.schema.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.valid?(schema, v["mapping"])
    assert ExJsonSchema.Validator.valid?(schema, Map.put(result, "fact", result["fact"].data))
    refute ExJsonSchema.Validator.valid?(schema, Map.put(v["mapping"], "extra", 0))
  end

  test "exact decimal conversion uses independent rational cases" do
    v = F.vector()

    for {node, expected} <- [
          {%{"type" => "decimal", "coefficient" => "251", "exponent" => -1}, 2510},
          {%{"type" => "sint", "value" => "-40"}, -4000},
          {%{"type" => "uint", "value" => "0"}, 0},
          {%{"type" => "sint", "value" => "100"}, 10_000}
        ] do
      assert {:ok, result} =
               Input.project(
                 Map.put(v["proposal"], "normalized_value", node),
                 v["mapping"],
                 v["metadata"],
                 F.context(v)
               )

      assert result["fact"].data["value"] == expected
    end

    assert {:error, %Error{code: :inexact_conversion}} =
             Input.project(
               put_in(v["proposal"], ["normalized_value"], %{
                 "type" => "decimal",
                 "coefficient" => "1001",
                 "exponent" => -3
               }),
               v["mapping"],
               v["metadata"],
               F.context(v)
             )

    for node <- [
          %{"type" => "list", "items" => []},
          %{"type" => "text", "value" => "25"},
          %{"type" => "sint", "value" => "1001"},
          %{"type" => "decimal", "coefficient" => "1", "exponent" => 19},
          %{"type" => "decimal", "coefficient" => "9223372036854775807", "exponent" => 1}
        ] do
      assert {:error, %Error{code: code}} =
               Input.project(
                 Map.put(v["proposal"], "normalized_value", node),
                 v["mapping"],
                 v["metadata"],
                 F.context(v)
               )

      assert code in [:unsupported_representation, :input_limit]
    end
  end

  test "a repeating rational coordinate refuses and timestamp precision preserves the instant" do
    v = F.vector()

    assert {:ok, _} =
             Input.project(
               v["proposal"],
               v["mapping"],
               Map.put(v["metadata"], "source_time", "2026-10-14T12:00:00.000000Z"),
               F.context(v)
             )

    unsigned =
      v["mapping"]
      |> Map.delete("sha256")
      |> put_in(["external_unit", "scale_d"], "3")

    v = F.install(v, unsigned)

    proposal =
      Map.merge(v["proposal"], %{
        "unit" => v["mapping"]["external_unit"],
        "normalized_value" => %{"type" => "sint", "value" => "1"}
      })

    assert {:error, %Error{code: :inexact_conversion}} =
             Input.project(proposal, v["mapping"], v["metadata"], F.context(v))
  end

  test "current mappings and exact basis fields cannot be substituted" do
    v = F.vector()

    for key <- ~w(profile_sha256 closure_sha256 capture_digest source_epoch) do
      value =
        if key == "source_epoch", do: String.duplicate("0", 32), else: String.duplicate("0", 64)

      assert {:error, %Error{code: :stale_basis}} =
               Input.project(
                 Map.put(v["proposal"], key, value),
                 v["mapping"],
                 v["metadata"],
                 F.context(v)
               )
    end

    for key <- ~w(semantic compiler_ref) do
      proposal = put_in(v["proposal"], [key, "sha256"], String.duplicate("0", 64))

      assert {:error, %Error{code: :stale_basis}} =
               Input.project(proposal, v["mapping"], v["metadata"], F.context(v))
    end

    for {key, value} <- [
          {"channel_id", "other"},
          {"source_ref", "other"},
          {"unit", nil},
          {"affordance", %{"kind" => "event", "name" => "scalar"}}
        ] do
      assert {:error, %Error{code: :stale_basis}} =
               Input.project(
                 Map.put(v["proposal"], key, value),
                 v["mapping"],
                 v["metadata"],
                 F.context(v)
               )
    end

    assert {:error, %Error{code: :unsupported_mapping}} =
             Input.project(
               v["proposal"],
               v["mapping"],
               v["metadata"],
               Map.put(
                 F.context(v),
                 "registry",
                 Enum.reject(v["registry"], &(&1["id"] == v["mapping"]["id"]))
               )
             )
  end

  test "continuity retains replay classification and cannot renew freshness" do
    v = F.vector()

    for {source, continuity, replay} <- [
          {"continuous", "continuous", "fresh"},
          {"baseline", "baseline", "fresh"},
          {"gap", "lost", "fresh"},
          {"retained", "lost", "retained"},
          {"replayed", "lost", "replayed"}
        ] do
      metadata = Map.merge(v["metadata"], %{"continuity" => continuity, "replay" => replay})
      proposal = Map.put(v["proposal"], "continuity", source)
      assert {:ok, result} = Input.project(proposal, v["mapping"], metadata, F.context(v))
      assert result["fact"].data["expires_ms"] == metadata["expires_ms"]
      assert result["fact"].data["replay"] == replay

      if replay != "fresh" do
        assert {:error, %Error{code: :stale_basis}} =
                 Input.project(
                   proposal,
                   v["mapping"],
                   Map.put(metadata, "replay", "fresh"),
                   F.context(v)
                 )
      end
    end

    assert {:error, %Error{code: :unsupported_representation}} =
             Input.project(
               Map.put(v["proposal"], "continuity", "unknown"),
               v["mapping"],
               v["metadata"],
               F.context(v)
             )

    for sequence <- [nil, "18446744073709551615"] do
      assert {:error, %Error{code: :unsupported_representation}} =
               Input.project(
                 Map.put(v["proposal"], "sequence", sequence),
                 v["mapping"],
                 v["metadata"],
                 F.context(v)
               )
    end
  end

  test "explicit clock correspondence permits negative origins but no guessed rounding" do
    v = F.vector()

    assert {:error, %Error{code: :inexact_conversion}} =
             Input.project(
               put_in(v["proposal"], ["receipt_time", "monotonic_us"], "-99001"),
               v["mapping"],
               v["metadata"],
               F.context(v)
             )

    for {key, value} <- [
          {"receipt_epoch", "other"},
          {"receipt_ms", 102},
          {"source_uncertainty_ms", 1},
          {"source_time_basis", "sha256:" <> String.duplicate("0", 64)},
          {"source_time", "2026-10-14T12:00:02Z"},
          {"source_time_trust", "untrusted"},
          {"source_class", "protocol_response"},
          {"source_id", "other"},
          {"source_epoch", "other"},
          {"sequence", 8},
          {"profile_digest", "sha256:" <> String.duplicate("0", 64)},
          {"affordance_name", "other"},
          {"affordance_type", "event"}
        ] do
      assert {:error, %Error{code: :stale_basis}} =
               Input.project(
                 v["proposal"],
                 v["mapping"],
                 Map.put(v["metadata"], key, value),
                 F.context(v)
               )
    end

    assert {:error, %Error{code: :stale_basis}} =
             Input.project(
               put_in(v["proposal"], ["receipt_time", "epoch"], String.duplicate("0", 32)),
               v["mapping"],
               v["metadata"],
               F.context(v)
             )
  end

  test "nonusable qualities become null without numeric conversion" do
    v = F.vector()

    for quality <- ~w(unknown invalid stale) do
      proposal =
        Map.merge(v["proposal"], %{
          "quality" => quality,
          "quality_reason" => "stale",
          "normalized_value" => %{"type" => "null"},
          "interpretation" => "unconverted"
        })

      assert {:ok, result} = Input.project(proposal, v["mapping"], v["metadata"], F.context(v))
      assert result["fact"].data["quality"] == quality
      assert result["fact"].data["value"] == nil
    end
  end

  test "caller-owned source time may be absent without fabricating a clock basis" do
    v = F.vector()

    unsigned =
      v["mapping"]
      |> Map.delete("sha256")
      |> put_in(["observation", "source_time_basis"], nil)

    v = F.install(v, unsigned)

    metadata =
      Map.merge(v["metadata"], %{
        "source_time" => nil,
        "source_time_trust" => "unknown",
        "source_time_basis" => nil,
        "source_uncertainty_ms" => nil
      })

    proposal = Map.put(v["proposal"], "source_time", nil)
    assert {:ok, result} = Input.project(proposal, v["mapping"], metadata, F.context(v))
    assert result["fact"].data["source_time"] == nil

    assert {:error, %Error{code: :stale_basis}} =
             Input.project(proposal, v["mapping"], v["metadata"], F.context(v))

    time = %{"utc" => "2026-10-14T12:00:00Z", "trust" => "untrusted", "uncertainty_us" => nil}

    metadata =
      Map.merge(metadata, %{"source_time" => time["utc"], "source_time_trust" => "untrusted"})

    assert {:ok, _} =
             Input.project(
               Map.put(proposal, "source_time", time),
               v["mapping"],
               metadata,
               F.context(v)
             )
  end

  test "malformed and over-budget inputs refuse without foreign payloads" do
    v = F.vector()

    for proposal <- [
          %URI{},
          Map.put(v["proposal"], "private-canary", "secret-canary"),
          %{},
          put_in(v["proposal"], ["unit", "scale_d"], "0")
        ] do
      assert {:error, %Error{} = error} =
               Input.project(proposal, v["mapping"], v["metadata"], F.context(v))

      refute inspect(error) =~ "canary"
    end

    for metadata <- [
          Map.put(v["metadata"], "private-canary", <<255>>),
          %URI{},
          Map.put(v["metadata"], "private-canary", "secret-canary"),
          Map.delete(v["metadata"], "id")
        ] do
      assert {:error, %Error{} = error} =
               Input.project(v["proposal"], v["mapping"], metadata, F.context(v))

      refute inspect(error) =~ "canary"
    end

    for context <- [
          nil,
          %URI{},
          Map.put(F.context(v), "foreign-canary", "secret-canary"),
          Map.put(F.context(v), "limits", %{}),
          Map.put(F.context(v), "reader_limits", %{})
        ] do
      assert {:error, %Error{} = error} =
               Input.project(v["proposal"], v["mapping"], v["metadata"], context)

      refute inspect(error) =~ "canary"
    end

    assert {:error, %Error{code: :input_limit}} =
             Input.project(
               v["proposal"],
               v["mapping"],
               v["metadata"],
               put_in(F.context(v), ["limits", "max_bytes"], 128)
             )
  end
end
