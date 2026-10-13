defmodule Wotex.Profiles.InterpreterTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Compiler, Definition, Error, Interpreter}
  alias Wotex.Profiles.Test.Fixtures, as: F

  defp closure,
    do: %{
      "definitions" => [F.definition()],
      "bindings" => [F.json("installed-binding")],
      "contracts" => F.json("installed-contracts")
    }

  defp projection do
    {:ok, value} =
      Compiler.compile(F.json("compiler-profile"), closure(), F.json("capture"), F.limits())

    value
  end

  defp report(projection) do
    %{
      "channel_id" => "sample",
      "profile_sha256" => projection.data["profile_sha256"],
      "binding" => projection.data["binding"],
      "capture_epoch" => projection.data["capture_epoch"],
      "source_ref" => "synthetic-source",
      "source_epoch" => String.duplicate("e", 32),
      "sequence" => nil,
      "source_time" => nil,
      "receipt_time" => %{"epoch" => String.duplicate("f", 32), "monotonic_us" => "1"},
      "continuity" => "baseline",
      "quality" => "usable",
      "quality_reason" => nil,
      "value" => %{"type" => "sint", "value" => "25"}
    }
  end

  defp specialized(definition, binding, conversion) do
    {:ok, ref} = Definition.reference(definition, F.limits())

    profile =
      F.json("compiler-profile")
      |> put_in(["channels", Access.at(0), "semantic"], ref)
      |> put_in(["channels", Access.at(0), "conversion"], conversion)

    {:ok, projection} =
      Compiler.compile(
        profile,
        %{
          "definitions" => [definition],
          "bindings" => [binding],
          "contracts" => F.json("installed-contracts")
        },
        F.json("capture"),
        F.limits()
      )

    projection
  end

  test "unconverted proposals preserve provenance without fabricated source time" do
    projection = projection()
    report = report(projection)

    for continuity <- ~w(unknown baseline continuous gap retained replayed) do
      current = Map.put(report, "continuity", continuity)
      assert {:ok, proposal} = Interpreter.project(projection, current, F.limits())
      assert proposal["normalized_value"] == report["value"]
      assert proposal["source_time"] == nil
      assert proposal["sequence"] == nil
      assert proposal["continuity"] == continuity
      assert proposal["receipt_time"] == report["receipt_time"]
      assert proposal["interpretation"] == "unconverted"
      assert proposal["quality"] == "usable"
    end
  end

  test "invalid quality bypasses domains and a usable raw sentinel becomes missing" do
    projection = projection()
    report = report(projection)

    for quality <- ~w(invalid unknown stale) do
      current =
        Map.merge(report, %{
          "quality" => quality,
          "quality_reason" => "device_invalid",
          "value" => %{"type" => "null"}
        })

      assert {:ok, proposal} = Interpreter.project(projection, current, F.limits())
      assert proposal["normalized_value"] == %{"type" => "null"}
      assert proposal["quality"] == quality
      assert proposal["quality_reason"] == "device_invalid"
      assert proposal["interpretation"] == "unconverted"
    end

    assert {:ok, proposal} =
             Interpreter.project(
               projection,
               Map.put(report, "value", %{"type" => "sint", "value" => "-1"}),
               F.limits()
             )

    assert proposal["normalized_value"] == %{"type" => "null"}
    assert proposal["quality"] == "invalid"
    assert proposal["quality_reason"] == "profile_sentinel"
  end

  test "raw ADC domain is checked before conversion and target domain after conversion" do
    definition =
      F.definition()
      |> Map.put("value_schema", %{"type" => "number", "minimum" => -40, "maximum" => 100})

    conversion = %{
      "kind" => "affine",
      "scale_n" => "1",
      "scale_d" => "100",
      "offset_n" => "-40",
      "offset_d" => "1"
    }

    projection = specialized(definition, F.json("installed-binding"), conversion)
    report = report(projection)

    assert {:ok, proposal} =
             Interpreter.project(
               projection,
               Map.put(report, "value", %{"type" => "sint", "value" => "5000"}),
               F.limits()
             )

    assert proposal["normalized_value"] == %{"type" => "sint", "value" => "10"}
    assert proposal["interpretation"] == "profile_declared"

    for value <- ["15000", "32768"] do
      assert {:error, %Error{code: :out_of_domain}} =
               Interpreter.project(
                 projection,
                 Map.put(report, "value", %{"type" => "sint", "value" => value}),
                 F.limits()
               )
    end

    repeating = Map.merge(conversion, %{"scale_d" => "3", "offset_n" => "0"})
    projection = specialized(definition, F.json("installed-binding"), repeating)

    assert {:error, %Error{code: :inexact_conversion}} =
             Interpreter.project(
               projection,
               Map.put(report(projection), "value", %{"type" => "sint", "value" => "1"}),
               F.limits()
             )
  end

  test "finite table uses canonical typed equality with no unmatched default or signedness coercion" do
    entry = %{
      "source" => %{"type" => "sint", "value" => "1"},
      "target" => %{"type" => "sint", "value" => "42"}
    }

    projection =
      specialized(F.definition(), F.json("installed-binding"), %{
        "kind" => "table",
        "entries" => [entry]
      })

    report = report(projection)

    assert {:ok, proposal} =
             Interpreter.project(projection, Map.put(report, "value", entry["source"]), F.limits())

    assert proposal["normalized_value"] == entry["target"]

    for value <- [%{"type" => "sint", "value" => "2"}, %{"type" => "uint", "value" => "1"}] do
      assert {:error, %Error{code: :unsupported_semantics}} =
               Interpreter.project(projection, Map.put(report, "value", value), F.limits())
    end
  end

  test "stale basis and native forgery refuse before value interpretation" do
    projection = projection()
    report = report(projection)

    for changed <- [
          Map.put(report, "profile_sha256", String.duplicate("a", 64)),
          Map.put(report, "capture_epoch", String.duplicate("a", 32)),
          put_in(report, ["binding", "sha256"], String.duplicate("a", 64))
        ] do
      assert {:error, %Error{code: :stale_basis}} =
               Interpreter.project(projection, Map.put(changed, "value", 1), F.limits())
    end

    assert {:error, %Error{code: :stale_basis}} =
             Interpreter.project(
               %{
                 projection
                 | data: Map.put(projection.data, "closure_sha256", String.duplicate("a", 64))
               },
               report,
               F.limits()
             )

    assert {:error, %Error{code: :invalid_input}} =
             Interpreter.project(projection.data, report, F.limits())

    assert {:error, %Error{code: :unsupported_semantics}} =
             Interpreter.project(projection, Map.put(report, "channel_id", "unknown"), F.limits())
  end

  test "source time is explicit UTC and trusted uncertainty cannot be omitted" do
    projection = projection()
    report = report(projection)

    for utc <- ["2026-10-13T00:00:00Z", "2026-10-13T00:00:00.123456+00:00"] do
      time = %{"utc" => utc, "trust" => "trusted", "uncertainty_us" => "0"}

      assert {:ok, proposal} =
               Interpreter.project(projection, Map.put(report, "source_time", time), F.limits())

      assert proposal["source_time"] == time
    end

    for time <- [
          %{},
          %{"utc" => "2026-10-13T00:00:00Z", "trust" => "trusted", "uncertainty_us" => nil},
          %{"utc" => "2026-10-13T00:00:00+01:00", "trust" => "unknown", "uncertainty_us" => nil},
          %{"utc" => "2026-02-30T00:00:00Z", "trust" => "unknown", "uncertainty_us" => nil},
          %{"utc" => "2026-10-13T00:00:00.1234567Z", "trust" => "unknown", "uncertainty_us" => nil},
          %{"utc" => nil, "trust" => "unknown", "uncertainty_us" => nil}
        ] do
      assert {:error, %Error{code: :invalid_input}} =
               Interpreter.project(projection, Map.put(report, "source_time", time), F.limits())
    end
  end

  test "closed report fields and counters reject malformed input without foreign payloads" do
    projection = projection()
    report = report(projection)

    for {key, value} <- [
          {"sequence", "-1"},
          {"sequence", "18446744073709551616"},
          {"source_epoch", "bad"},
          {"source_ref", ""},
          {"receipt_time", %{}},
          {"receipt_time", %{"epoch" => String.duplicate("f", 32), "monotonic_us" => "01"}},
          {"continuity", "guessed"},
          {"quality", "assumed"},
          {"quality_reason", "secret-canary"},
          {"quality_reason", "stale"},
          {"value", 1},
          {"foreign-secret-canary", "credential-canary"}
        ] do
      assert {:error, %Error{} = error} =
               Interpreter.project(projection, Map.put(report, key, value), F.limits())

      refute inspect(error) =~ "canary"
    end

    assert {:error, %Error{}} =
             Interpreter.project(projection, Map.delete(report, "value"), F.limits())
  end
end
