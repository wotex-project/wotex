defmodule ProfileArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Compiler, Definition, Interpreter}
  alias Wotex.Routines.{Basis, Error, Input, InputMapping}

  @execution_profile %{
    "source_bytes" => 65_536,
    "source_depth" => 32,
    "expanded_nodes" => 64,
    "predicate_nodes" => 64,
    "invocation_depth" => 4,
    "parallel_width" => 4,
    "effects" => 16,
    "waits" => 16,
    "active_definitions" => 64,
    "active_runs" => 64,
    "pending_work" => 64,
    "run_ms" => 86_400_000
  }

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

  defp interpreted(v, raw \\ "251") do
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
        "value" => %{"type" => "sint", "value" => raw}
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

  test "full external execution preserves null UTC, signed precision and independent profile identity" do
    {v, expected} = execution_fixture()
    {fact, mapping, context} = execution_input(v, "-1001", 9998, 1, "continuous", "251")
    assert fact["value"] == expected
    assert fact["received_at"] == nil
    assert fact["receipt_ms"] == 9998
    assert fact["expires_ms"] == 10_998
    assert fact["profile_digest"] == "sha256:" <> mapping["profile_sha256"]
    refute fact["profile_digest"] == mapping["basis"]["semantic_digest"]
    f = execution_program(fact, mapping, context, expected)
    assert {:ok, true} = evaluate(f, context)
    assert {:ok, %{"outcome" => "completed", "proposals" => []}} = advance(f, context, nil)

    # This must be unknown even though every other identity and freshness field matches.
    forged =
      put_in(f.snapshot, ["facts", "sensor", "profile_digest"], mapping["basis"]["semantic_digest"])

    assert {:ok, "unknown"} = evaluate(%{f | snapshot: forged}, context)

    assert {:ok, %{"outcome" => "blocked", "proposals" => []}} =
             advance(%{f | snapshot: forged}, context, nil)

    expired = %{f | time: Map.put(f.time, "elapsed_ms", 10_998)}
    assert {:ok, "unknown"} = evaluate(expired, context)

    legacy =
      f.snapshot["binding_bases"]["sensor"]
      |> Map.take(~w(profile_digest source_id source_epoch source_time_basis))

    stale = put_in(f.snapshot, ["binding_bases", "sensor"], legacy)

    assert {:error, %{code: :stale_binding_basis}} =
             Wotex.Routines.Snapshot.new(stale, f.program, @execution_profile, context["limits"])

    absent = Enum.reject(context["registry"], &(&1["id"] == mapping["id"]))
    assert {:error, _} = Input.binding_basis(mapping, absent, context["limits"])
  end

  test "external edge history agrees with independent baseline, transition, duplicate and gap outcomes" do
    {v, expected} = execution_fixture()

    rows = [
      {1, "-1001", 9998, "100", "continuous", "baseline"},
      {2, "999", 10_000, "300", "continuous", "eligible"},
      {2, "999", 10_000, "300", "continuous", "duplicate"},
      {3, "1999", 10_001, "300", "gap", "unqualified"},
      {4, "2999", 10_002, "300", "continuous", "baseline"}
    ]

    Enum.reduce(rows, nil, fn {sequence, us, ms, raw, continuity, outcome}, prior ->
      {fact, mapping, context} = execution_input(v, us, ms, sequence, continuity, raw)
      f = execution_program(fact, mapping, context, expected, true)

      assert {:ok, edge_result} =
               Wotex.Routines.Edge.advance(
                 f.program,
                 f.event,
                 f.snapshot,
                 f.time,
                 prior,
                 @execution_profile,
                 context["limits"]
               )

      assert edge_result["reason"] == outcome
      assert {:ok, transition} = advance(f, context, prior)
      assert transition["edge"] == edge_result["edge"]
      assert transition["outcome"] == if(outcome == "eligible", do: "completed", else: "no-edge")
      assert transition["proposals"] == []
      assert transition["edge"]["binding_basis"] == f.snapshot["binding_bases"]["sensor"]

      assert {:ok, edge} =
               Wotex.Routines.Edge.new(
                 transition["edge"],
                 f.program,
                 @execution_profile,
                 context["limits"]
               )

      assert {:ok, _} =
               Wotex.Routines.Edge.to_map(edge, f.program, @execution_profile, context["limits"])

      if sequence == 1, do: assert(transition["edge"]["last_original"] == nil)
      if sequence == 4, do: assert(transition["edge"]["last_original"] == "original:2")
      transition["edge"]
    end)
  end

  defp execution_fixture do
    {v, expected} = fixture()
    corpus = Jason.decode!(File.read!("input-execution.json"))
    # Frozen independent negative fraction: -1001 us at 0 us/10000 ms -> 9998 ms.
    [clock | _] = corpus["clock_cases"]
    assert clock["source_receipt_us"] == "-1001"
    assert clock["expected_receipt_ms"] == 9998

    receipt_clock = %{
      "format" => "wotex.routines.receipt-clock@1",
      "projection" => "floor_millisecond",
      "source_epoch" => v["mapping"]["receipt_clock"]["source_epoch"],
      "source_origin_us" => clock["source_origin_us"],
      "target_epoch" => v["mapping"]["receipt_clock"]["target_epoch"],
      "target_origin_ms" => clock["target_origin_ms"]
    }

    {put_in(v, ["mapping", "receipt_clock"], receipt_clock), expected}
  end

  defp execution_input(v, us, ms, sequence, continuity, raw) do
    proposal =
      v["proposal"]
      |> Map.merge(%{"sequence" => Integer.to_string(sequence), "continuity" => continuity})
      |> put_in(["receipt_time", "monotonic_us"], us)

    metadata =
      Map.merge(v["metadata"], %{
        "id" => "external-fact:#{sequence}",
        "sequence" => sequence,
        "received_at" => nil,
        "receipt_ms" => ms,
        "expires_ms" => ms + 1000,
        "continuity" => if(continuity == "gap", do: "lost", else: continuity)
      })

    {proposal, mapping, metadata, context} =
      interpreted(Map.merge(v, %{"proposal" => proposal, "metadata" => metadata}), raw)

    assert {:ok, result} = Input.project(proposal, mapping, metadata, context)
    {:ok, limits} = Wotex.Routines.Limits.new(context["limits"])
    {result["fact"].data, mapping, Map.put(context, "limits", limits)}
  end

  defp execution_program(fact, mapping, context, expected, edge \\ false) do
    {enter, exit} = Map.fetch!(%{2510 => {2500, 1500}, 251_000 => {250_000, 150_000}}, expected)

    trigger =
      if edge do
        %{
          "kind" => "edge",
          "binding" => "sensor",
          "direction" => "rising",
          "debounce_ms" => 0,
          "cooldown_ms" => 0,
          "hysteresis" => %{"enter" => enter, "exit" => exit}
        }
      else
        %{"kind" => "manual"}
      end

    condition =
      if edge,
        do: %{"op" => "literal", "value" => true},
        else: %{"op" => "gt", "binding" => "sensor", "value" => enter}

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "external-execution",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["sensor"],
      "trigger" => trigger,
      "condition" => condition,
      "steps" => %{"id" => "end", "kind" => "noop"},
      "overlap" => "reject",
      "run_ms" => 1000
    }

    compiler_context = %{
      "registry" => context["registry"],
      "bases" => [mapping["basis"]],
      "bindings" => %{
        "sensor" => %{
          "basis" => mapping["legacy_basis_ref"],
          "thing_id" => fact["thing_id"],
          "resource_roles" => %{}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    assert {:ok, program} =
             Wotex.Routines.Compiler.compile(
               source,
               compiler_context,
               @execution_profile,
               context["limits"]
             )

    assert {:ok, binding} = Input.binding_basis(mapping, context["registry"], context["limits"])

    snapshot = %{
      "id" => "snapshot:external",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{fact["thing_id"] => 1},
      "binding_bases" => %{"sensor" => binding},
      "facts" => %{"sensor" => fact}
    }

    {:ok, date, _} = DateTime.from_iso8601(fact["source_time"])
    utc = DateTime.to_unix(date, :millisecond) + 10

    time = %{
      "epoch" => fact["receipt_epoch"],
      "elapsed_ms" => fact["receipt_ms"],
      "clock_generation" => "clock:1",
      "utc_low_ms" => utc,
      "utc_high_ms" => utc
    }

    event = %{
      "kind" => "manual",
      "original" => "original:#{fact["sequence"]}",
      "program_digest" => program.data["ir_digest"]
    }

    event =
      if edge,
        do: Map.merge(event, %{"kind" => "fact", "binding" => "sensor", "fact_id" => fact["id"]}),
        else: event

    %{program: program, snapshot: snapshot, time: time, event: event}
  end

  defp evaluate(f, context),
    do:
      Wotex.Routines.Evaluation.evaluate(
        f.program,
        f.snapshot,
        f.time,
        @execution_profile,
        context["limits"]
      )

  defp advance(f, context, edge),
    do:
      Wotex.Routines.Kernel.advance(
        f.program,
        f.event,
        f.snapshot,
        f.time,
        %{"original" => nil, "busy" => nil, "edge" => edge},
        @execution_profile,
        context["limits"]
      )
end
