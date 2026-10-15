defmodule Wotex.Routines.InputExecutionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{
    Compiler,
    Continuum,
    Edge,
    Evaluation,
    Fact,
    Input,
    InputMapping,
    Kernel,
    Model,
    Snapshot
  }

  alias Wotex.Routines.InputFixtures, as: F

  @profile %{
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

  setup_all do
    path =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()

    corpus =
      path
      |> Path.join("vectors/wro-05-input-execution.json")
      |> File.read!()
      |> JSON.decode!()

    %{base: F.vector(), corpus: corpus, join: corpus["join"]}
  end

  test "actual public reader-to-kernel path preserves independent identities and null receipt UTC",
       c do
    {:ok, projection} =
      Wotex.Profiles.Compiler.compile(
        c.base["profile"],
        c.base["closure"],
        c.base["capture"],
        c.base["reader_limits"]
      )

    report =
      Map.take(
        c.join["proposal"],
        ~w(channel_id profile_sha256 source_ref source_epoch sequence source_time receipt_time continuity quality quality_reason)
      )
      |> Map.merge(%{
        "binding" => c.base["capture"]["binding"],
        "capture_epoch" => c.base["capture"]["capture_epoch"],
        "value" => %{"type" => "sint", "value" => "251"}
      })

    assert {:ok, proposal} =
             Wotex.Profiles.Interpreter.project(projection, report, c.base["reader_limits"])

    assert proposal == c.join["proposal"]
    assert {:ok, result} = project(c, proposal)
    assert result["fact"].data == c.join["expected_fact"]
    assert result["source_proposal_sha256"] == c.join["source_proposal_sha256"]

    assert {:ok, binding} =
             Input.binding_basis(c.join["mapping"], c.join["registry"], c.base["limits"])

    assert binding == c.join["expected_binding_basis"]
    refute binding["profile_digest"] == c.base["basis"]["semantic_digest"]
    f = fixture(c, result["fact"].data, binding)
    assert :ok = Compiler.current(f.program, f.context, @profile, c.base["limits"])
    assert {:ok, _} = Snapshot.new(f.snapshot, f.program, @profile, c.base["limits"])
    assert {:ok, true} = evaluate(c, f)

    event = %{
      "kind" => "manual",
      "original" => "execution:1",
      "program_digest" => f.program.data["ir_digest"]
    }

    prior = %{"original" => nil, "busy" => nil, "edge" => nil}

    assert {:ok, %{"outcome" => "completed", "proposals" => []}} =
             Kernel.advance(f.program, event, f.snapshot, f.time, prior, @profile, c.base["limits"])
  end

  test "null receipt UTC survives exchange and never supplies a missing source timestamp", c do
    assert {:ok, result} = project(c, c.join["proposal"])

    scope = %{
      "execution_id" => "execution:1",
      "node_id" => "node:1",
      "observed_at" => c.base["metadata"]["received_at"],
      "mode" => %{
        "deployment" => "air_gapped",
        "connectivity" => "disconnected",
        "extensions" => %{}
      },
      "extensions" => %{}
    }

    assert {:ok, observation} =
             Continuum.to_observation(result["fact"], scope, [], c.base["limits"])

    assert {:ok, wire} = WotexContinuum.to_map(observation)
    assert {:ok, restored} = Continuum.from_observation(wire, c.base["limits"])
    assert restored == result["fact"]

    raw = %{
      result["fact"].data
      | "source_time" => nil,
        "source_time_trust" => "unknown",
        "source_time_basis" => nil,
        "source_uncertainty_ms" => nil
    }

    assert {:ok, unknown_utc} = Fact.new(raw, c.base["limits"])

    assert {:error, %{code: :missing_source_time}} =
             Continuum.to_observation(unknown_utc, scope, [], c.base["limits"])

    assert {:error, _} = Fact.new(Map.delete(raw, "received_at"), c.base["limits"])
  end

  test "independent signed floor vectors include negative fractions, 65-bit difference and overflow",
       c do
    for vector <- c.corpus["clock_cases"] do
      mapping =
        c.join["mapping"]
        |> Map.delete("sha256")
        |> put_in(["receipt_clock", "source_origin_us"], vector["source_origin_us"])
        |> put_in(["receipt_clock", "target_origin_ms"], vector["target_origin_ms"])

      selected = F.install(c.base, mapping)
      changed = %{c | join: Map.merge(c.join, Map.take(selected, ~w(mapping registry)))}

      proposal =
        put_in(c.join["proposal"], ["receipt_time", "monotonic_us"], vector["source_receipt_us"])

      metadata =
        c.join["metadata"]
        |> Map.put("receipt_ms", vector["expected_receipt_ms"] || 0)
        |> Map.put("expires_ms", vector["maximum_expiry_ms"] || 0)

      if vector["expected_error"] do
        assert {:error, %{code: :input_limit}} = project(changed, proposal, metadata)
      else
        assert {:ok, result} = project(changed, proposal, metadata)
        assert result["fact"].data["receipt_ms"] == vector["expected_receipt_ms"]
        assert result["fact"].data["expires_ms"] == vector["maximum_expiry_ms"]
      end
    end
  end

  test "floor projection cannot widen expiry, change receipt coordinates or alter the exact legacy mode",
       c do
    for changed <- [
          Map.update!(c.join["metadata"], "expires_ms", &(&1 + 1)),
          Map.update!(c.join["metadata"], "receipt_ms", &(&1 + 1)),
          Map.put(c.join["metadata"], "receipt_epoch", "foreign-clock")
        ] do
      assert {:error, %{code: :stale_basis}} = project(c, c.join["proposal"], changed)
    end

    assert {:error, %{code: :inexact_conversion}} =
             Input.project(
               c.join["proposal"],
               c.base["mapping"],
               c.base["metadata"],
               F.context(c.base)
             )

    earlier = Map.put(c.join["metadata"], "expires_ms", 500)
    assert {:ok, result} = project(c, c.join["proposal"], earlier)
    assert result["fact"].data["expires_ms"] == 500
  end

  test "floor clock has a closed discriminator and canonical signed coordinates", c do
    unsigned = Map.delete(c.join["mapping"], "sha256")

    for clock <- [
          Map.put(unsigned["receipt_clock"], "format", "wotex.routines.receipt-clock@2"),
          Map.put(unsigned["receipt_clock"], "projection", "nearest_millisecond"),
          Map.delete(unsigned["receipt_clock"], "projection"),
          Map.put(unsigned["receipt_clock"], "extra", true),
          Map.put(unsigned["receipt_clock"], "source_origin_us", "-0"),
          Map.put(unsigned["receipt_clock"], "source_origin_us", "+1"),
          Map.put(unsigned["receipt_clock"], "source_origin_us", "01"),
          Map.put(unsigned["receipt_clock"], "source_origin_us", "9223372036854775808"),
          Map.put(unsigned["receipt_clock"], "target_epoch", "bad" <> <<0>> <> "epoch"),
          Map.put(unsigned["receipt_clock"], "target_origin_ms", -1)
        ] do
      assert {:error, _} =
               InputMapping.digest(
                 Map.put(unsigned, "receipt_clock", clock),
                 c.join["registry"],
                 c.base["limits"]
               )
    end
  end

  test "an external profile cannot become a legacy Basis identity or renew expiry at its boundary",
       c do
    assert {:ok, result} = project(c, c.join["proposal"])
    f = fixture(c, result["fact"].data, c.join["expected_binding_basis"])

    legacy =
      c.join["expected_binding_basis"]
      |> Map.take(~w(profile_digest source_id source_epoch source_time_basis))
      |> Map.put("profile_digest", c.base["basis"]["semantic_digest"])

    legacy = %{f | snapshot: put_in(f.snapshot, ["binding_bases", "sensor"], legacy)}
    assert {:ok, "unknown"} = evaluate(c, legacy)
    expired = %{f | time: Map.put(f.time, "elapsed_ms", result["fact"].data["expires_ms"])}
    assert {:ok, "unknown"} = evaluate(c, expired)
  end

  test "outer binding forgery and missing mapping installation refuse without falling back", c do
    assert {:ok, result} = project(c, c.join["proposal"])
    f = fixture(c, result["fact"].data, c.join["expected_binding_basis"])

    for binding <- [
          Map.put(c.join["expected_binding_basis"], "extra", true),
          Map.put(
            c.join["expected_binding_basis"],
            "profile_digest",
            c.base["basis"]["semantic_digest"]
          ),
          Map.put(c.join["expected_binding_basis"], "source_id", "different-source"),
          put_in(
            c.join["expected_binding_basis"],
            ["input_mapping", "sha256"],
            String.duplicate("0", 64)
          )
        ] do
      changed = put_in(f.snapshot, ["binding_bases", "sensor"], binding)
      assert {:error, _} = Snapshot.new(changed, f.program, @profile, c.base["limits"])
    end

    registry = Enum.reject(c.join["registry"], &(&1["id"] == c.join["mapping"]["id"]))
    assert {:error, _} = Input.binding_basis(c.join["mapping"], registry, c.base["limits"])

    assert {:ok, mapping} =
             InputMapping.new(c.join["mapping"], c.join["registry"], c.base["limits"])

    forged = %{mapping | data: Map.put(mapping.data, "extra", true)}
    assert {:error, _} = Input.binding_basis(forged, c.join["registry"], c.base["limits"])
  end

  test "actual Boolean and enum reader values reach known predicates and completed inert runs", c do
    for {type, rows} <- [
          {"boolean", [{false, false}, {true, true}]},
          {"enum", [{"0", "closed"}, {"1", "open"}]}
        ] do
      changed = typed(c, type)

      for {raw, expected} <- rows do
        node = %{"type" => if(type == "boolean", do: "boolean", else: "text"), "value" => raw}
        proposal = interpreted(changed.base, c.join["proposal"], node)
        assert {:ok, result} = project(changed, proposal)
        assert result["fact"].data["value"] == expected
        assert result["fact"].data["unit"] == nil
        assert result["fact"].data["received_at"] == nil

        assert {:ok, binding} =
                 Input.binding_basis(
                   changed.join["mapping"],
                   changed.join["registry"],
                   c.base["limits"]
                 )

        condition = %{"op" => "eq", "binding" => "sensor", "value" => expected}
        f = fixture(changed, result["fact"].data, binding, condition: condition)
        assert {:ok, true} = evaluate(changed, f)
        assert {:ok, %{"outcome" => "completed", "proposals" => []}} = kernel(changed, f)

        mismatched =
          put_in(
            f.snapshot,
            ["binding_bases", "sensor", "profile_digest"],
            c.base["basis"]["semantic_digest"]
          )

        assert {:error, _} = Snapshot.new(mismatched, f.program, @profile, c.base["limits"])
      end
    end
  end

  test "mapped class and source clock remain exact even when Basis permits broader evidence", c do
    unsigned =
      c.join["mapping"]
      |> Map.delete("sha256")
      |> put_in(["basis", "evidence", "sources"], ["device_report", "protocol_response"])
      |> put_in(["basis", "evidence", "require_source_time"], false)

    changed = with_mapping(c, unsigned)
    assert {:ok, result} = project(changed, c.join["proposal"])

    assert {:ok, binding} =
             Input.binding_basis(
               changed.join["mapping"],
               changed.join["registry"],
               c.base["limits"]
             )

    f = fixture(changed, result["fact"].data, binding)
    assert {:ok, true} = evaluate(changed, f)

    for {field, value} <- [
          {"source_class", "protocol_response"},
          {"source_time_basis", "sha256:" <> String.duplicate("9", 64)},
          {"profile_digest", c.base["basis"]["semantic_digest"]},
          {"source_id", "other-source"},
          {"source_epoch", String.duplicate("9", 32)}
        ] do
      snapshot = put_in(f.snapshot, ["facts", "sensor", field], value)
      assert {:ok, _} = Snapshot.new(snapshot, f.program, @profile, c.base["limits"])
      assert {:ok, "unknown"} = evaluate(changed, %{f | snapshot: snapshot})
    end

    foreign = %{
      f
      | snapshot: put_in(f.snapshot, ["facts", "sensor", "receipt_epoch"], "foreign-clock"),
        time: Map.put(f.time, "epoch", "foreign-clock")
    }

    assert {:ok, "unknown"} = evaluate(changed, foreign)
  end

  test "the complete Basis body and each aggregate embedded mapping are revalidated", c do
    unsigned =
      put_in(
        Map.delete(c.join["mapping"], "sha256"),
        ["basis", "byte_digest"],
        "sha256:" <> String.duplicate("9", 64)
      )

    changed = with_mapping(c, unsigned)
    assert changed.join["mapping"]["legacy_basis_ref"] == c.join["mapping"]["legacy_basis_ref"]

    assert {:ok, binding} =
             Input.binding_basis(
               changed.join["mapping"],
               changed.join["registry"],
               c.base["limits"]
             )

    assert {:ok, result} = project(changed, c.join["proposal"])
    f = fixture(changed, result["fact"].data, binding)
    context = Map.put(f.context, "bases", [c.join["mapping"]["basis"]])

    assert {:ok, program} =
             Compiler.compile(f.program.data["source"], context, @profile, c.base["limits"])

    snapshot = Map.put(f.snapshot, "active_programs", [program.data["ir_digest"]])

    assert {:error, %{code: :stale_binding_basis}} =
             Snapshot.new(snapshot, program, @profile, c.base["limits"])

    {:ok, bytes} = Wotex.JSON.encode(c.join["mapping"])
    {:ok, registry_bytes} = Wotex.JSON.encode(c.join["registry"])

    narrow =
      Map.put(c.base["limits"], "max_bytes", max(byte_size(bytes), byte_size(registry_bytes)))

    assert {:ok, _} = InputMapping.new(c.join["mapping"], c.join["registry"], narrow)

    assert {:error, %{code: :input_limit}} =
             Input.binding_basis(c.join["mapping"], c.join["registry"], narrow)

    padded = put_in(f.snapshot, ["facts", "sensor", "id"], String.duplicate("bounded", 3000))
    {:ok, encoded} = Wotex.JSON.encode(padded)
    aggregate = Map.put(c.base["limits"], "max_bytes", byte_size(encoded) - 1)

    assert {:ok, narrow_program} =
             Compiler.compile(f.program.data["source"], f.context, @profile, aggregate)

    assert {:ok, _} = Compiler.to_map(narrow_program, @profile, aggregate)
    padded = Map.put(padded, "active_programs", [narrow_program.data["ir_digest"]])

    assert {:error, %{code: :limit_or_json_error}} =
             Snapshot.new(
               padded,
               narrow_program,
               @profile,
               aggregate
             )
  end

  test "independent external edge trace preserves the entire installed binding and agrees with kernel",
       c do
    Enum.reduce(c.corpus["edge_trace"], nil, fn row, prior ->
      f = edge_fixture(c, row["sequence"], row["value"], row["continuity"] || "continuous")
      assert {:ok, result} = edge(c, f, prior)
      assert result["reason"] == row["expected"]
      assert result["eligible"] == (row["expected"] == "eligible")
      assert result["edge"]["binding_basis"] == c.join["expected_binding_basis"]
      assert {:ok, transition} = kernel(c, f, prior)
      assert transition["edge"] == result["edge"]
      assert transition["outcome"] == if(result["eligible"], do: "completed", else: "no-edge")
      assert transition["proposals"] == []
      assert {:ok, retained} = Edge.new(result["edge"], f.program, @profile, c.base["limits"])
      assert {:ok, _} = Edge.to_map(retained, f.program, @profile, c.base["limits"])
      result["edge"]
    end)
  end

  test "expiry, restored input and clock/source replacement cannot reuse a positive external edge",
       c do
    first = edge_fixture(c, 1, 1000)
    assert {:ok, baseline} = edge(c, first, nil)
    next = edge_fixture(c, 2, 3000)
    assert {:ok, %{"eligible" => true}} = edge(c, next, baseline["edge"])
    clock = %{next | time: Map.put(next.time, "clock_generation", "clock:2")}
    assert {:ok, %{"eligible" => false, "reason" => "baseline"}} = edge(c, clock, baseline["edge"])

    expired = %{
      next
      | time: Map.put(next.time, "elapsed_ms", next.snapshot["facts"]["sensor"]["expires_ms"])
    }

    assert {:ok, %{"eligible" => false, "reason" => "unqualified"}} =
             edge(c, expired, baseline["edge"])

    for continuity <- ~w(baseline retained replayed) do
      restored = edge_fixture(c, 2, 3000, continuity)

      assert {:ok, %{"eligible" => false, "reason" => "unqualified"}} =
               edge(c, restored, baseline["edge"])
    end

    unsigned =
      put_in(
        Map.delete(c.join["mapping"], "sha256"),
        ["observation", "source_epoch"],
        String.duplicate("9", 32)
      )

    changed = with_mapping(c, unsigned)
    changed = put_in(changed, [:join, "proposal", "source_epoch"], String.duplicate("9", 32))
    changed = put_in(changed, [:join, "metadata", "source_epoch"], String.duplicate("9", 32))
    replaced = edge_fixture(changed, 2, 3000)
    assert {:error, %{code: :stale_edge}} = edge(changed, replaced, baseline["edge"])
    assert {:ok, %{"eligible" => false, "reason" => "baseline"}} = edge(changed, replaced, nil)

    forged = put_in(baseline["edge"], ["binding_basis", "input_mapping", "extra"], true)
    assert {:error, _} = Edge.new(forged, first.program, @profile, c.base["limits"])
    assert {:ok, native} = Edge.new(baseline["edge"], first.program, @profile, c.base["limits"])

    assert {:error, _} =
             Edge.new(Map.put(native, :extra, true), first.program, @profile, c.base["limits"])
  end

  test "existing analysis profiles explicitly refuse external input execution scope", c do
    assert {:ok, result} = project(c, c.join["proposal"])
    f = fixture(c, result["fact"].data, c.join["expected_binding_basis"])

    root =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()

    scope =
      root
      |> Path.join("vectors/wro-04-proposal-prefix.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("scope")

    assert {:error, %{code: :unsupported_model_scope}} =
             Model.compile(f.program, scope, @profile, c.base["limits"])
  end

  defp project(c, proposal, metadata \\ nil) do
    Input.project(proposal, c.join["mapping"], metadata || c.join["metadata"], %{
      "registry" => c.join["registry"],
      "limits" => c.base["limits"],
      "reader_limits" => c.base["reader_limits"]
    })
  end

  defp fixture(c, fact, binding, options \\ []) do
    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "external-input-check",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["sensor"],
      "trigger" => Keyword.get(options, :trigger, %{"kind" => "manual"}),
      "condition" =>
        Keyword.get(options, :condition, %{"op" => "gt", "binding" => "sensor", "value" => 2000}),
      "steps" => %{"id" => "end", "kind" => "noop"},
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => c.join["registry"],
      "bases" => [c.join["mapping"]["basis"]],
      "bindings" => %{
        "sensor" => %{
          "basis" => c.join["mapping"]["legacy_basis_ref"],
          "thing_id" => fact["thing_id"],
          "resource_roles" => %{}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(source, context, @profile, c.base["limits"])

    snapshot = %{
      "id" => "snapshot:external",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{fact["thing_id"] => 1},
      "binding_bases" => %{"sensor" => binding},
      "facts" => %{"sensor" => fact}
    }

    {:ok, utc, _} = DateTime.from_iso8601(fact["source_time"])
    utc = DateTime.to_unix(utc, :millisecond) + 10

    time = %{
      "epoch" => fact["receipt_epoch"],
      "elapsed_ms" => fact["receipt_ms"],
      "clock_generation" => "clock:1",
      "utc_low_ms" => utc,
      "utc_high_ms" => utc
    }

    %{program: program, context: context, snapshot: snapshot, time: time}
  end

  defp evaluate(c, f),
    do: Evaluation.evaluate(f.program, f.snapshot, f.time, @profile, c.base["limits"])

  defp with_mapping(c, unsigned) do
    selected = F.install(c.base, unsigned)
    %{c | join: Map.merge(c.join, Map.take(selected, ~w(mapping registry)))}
  end

  defp interpreted(base, proposal, value) do
    {:ok, projection} =
      Wotex.Profiles.Compiler.compile(
        base["profile"],
        base["closure"],
        base["capture"],
        base["reader_limits"]
      )

    report =
      Map.take(
        proposal,
        ~w(channel_id source_ref source_epoch sequence source_time receipt_time continuity quality quality_reason)
      )
      |> Map.merge(%{
        "profile_sha256" => projection.data["profile_sha256"],
        "binding" => base["capture"]["binding"],
        "capture_epoch" => base["capture"]["capture_epoch"],
        "value" => value
      })

    {:ok, result} = Wotex.Profiles.Interpreter.project(projection, report, base["reader_limits"])
    result
  end

  defp typed(c, type) do
    schema =
      if type == "boolean",
        do: %{"type" => "boolean"},
        else: %{"type" => "string", "enum" => ["0", "1"]}

    unsigned =
      hd(c.base["closure"]["bindings"])
      |> Map.delete("sha256")
      |> Map.put("raw_value_schema", schema)

    {:ok, digest} = Wotex.Profiles.Binding.digest(unsigned, c.base["reader_limits"])
    installed = Map.put(unsigned, "sha256", digest)
    ref = Map.take(installed, ~w(id version sha256))

    capture =
      c.base["capture"]
      |> Map.delete("digest")
      |> Map.put("binding", ref)

    {:ok, capture_digest} =
      Wotex.Profiles.Capture.digest(capture, installed, c.base["reader_limits"])

    capture = Map.put(capture, "digest", capture_digest)
    definition = Map.merge(c.base["definition"], %{"value_schema" => schema, "unit" => nil})
    {:ok, semantic} = Wotex.Profiles.Definition.reference(definition, c.base["reader_limits"])

    profile =
      c.base["profile"]
      |> Map.put("binding", ref)
      |> put_in(["channels", Access.at(0), "semantic"], semantic)
      |> put_in(["channels", Access.at(0), "conversion"], nil)
      |> put_in(["channels", Access.at(0), "invalid_values"], [])

    closure =
      Map.merge(c.base["closure"], %{"bindings" => [installed], "definitions" => [definition]})

    base = Map.merge(c.base, %{"profile" => profile, "capture" => capture, "closure" => closure})

    {:ok, projection} =
      Wotex.Profiles.Compiler.compile(profile, closure, capture, c.base["reader_limits"])

    value = %{
      "type" => type,
      "unit" => nil,
      "enum" => if(type == "enum", do: ["closed", "open"], else: [])
    }

    table =
      if type == "enum",
        do: [%{"source" => "0", "target" => "closed"}, %{"source" => "1", "target" => "open"}],
        else: nil

    unsigned_mapping =
      c.join["mapping"]
      |> Map.delete("sha256")
      |> Map.merge(Map.take(projection.data, ~w(profile_sha256 closure_sha256 capture_digest)))
      |> Map.merge(%{
        "semantic_ref" => semantic,
        "projection" => type,
        "external_unit" => nil,
        "enum_table" => table
      })
      |> put_in(["basis", "value"], value)
      |> put_in(["basis", "output"], nil)

    changed = with_mapping(%{c | base: base}, unsigned_mapping)

    put_in(
      changed,
      [:join, "metadata", "profile_digest"],
      "sha256:" <> projection.data["profile_sha256"]
    )
  end

  defp edge_fixture(c, sequence, value, continuity \\ "continuous") do
    receipt =
      Map.fetch!(
        %{1 => {"-98999", 101}, 2 => {"-88999", 111}, 3 => {"-78999", 121}, 4 => {"-68999", 131}},
        sequence
      )

    proposal =
      c.join["proposal"]
      |> Map.merge(%{"sequence" => Integer.to_string(sequence), "continuity" => continuity})
      |> put_in(["receipt_time", "monotonic_us"], elem(receipt, 0))

    proposal =
      interpreted(c.base, proposal, %{
        "type" => "sint",
        "value" => Map.fetch!(%{1000 => "100", 3000 => "300"}, value)
      })

    {replay, fact_continuity} =
      case continuity do
        "continuous" -> {"fresh", "continuous"}
        "baseline" -> {"fresh", "baseline"}
        "gap" -> {"fresh", "lost"}
        other -> {other, "lost"}
      end

    metadata =
      Map.merge(c.join["metadata"], %{
        "id" => "edge-fact:#{sequence}",
        "sequence" => sequence,
        "receipt_ms" => elem(receipt, 1),
        "expires_ms" => elem(receipt, 1) + 1000,
        "replay" => replay,
        "continuity" => fact_continuity
      })

    {:ok, result} = project(c, proposal, metadata)
    {:ok, binding} = Input.binding_basis(c.join["mapping"], c.join["registry"], c.base["limits"])

    trigger = %{
      "kind" => "edge",
      "binding" => "sensor",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 0,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    fixture(c, result["fact"].data, binding,
      trigger: trigger,
      condition: %{"op" => "literal", "value" => true}
    )
  end

  defp event(f) do
    base = %{
      "kind" => f.program.data["ir"]["trigger"]["kind"],
      "original" => "execution:#{f.snapshot["facts"]["sensor"]["sequence"]}",
      "program_digest" => f.program.data["ir_digest"]
    }

    if base["kind"] == "edge",
      do:
        Map.merge(base, %{
          "kind" => "fact",
          "binding" => "sensor",
          "fact_id" => f.snapshot["facts"]["sensor"]["id"]
        }),
      else: base
  end

  defp edge(c, f, prior) do
    {:ok, limits} = Wotex.Routines.Limits.new(c.base["limits"])
    Edge.advance(f.program, event(f), f.snapshot, f.time, prior, @profile, limits)
  end

  defp kernel(c, f, prior \\ nil),
    do:
      Kernel.advance(
        f.program,
        event(f),
        f.snapshot,
        f.time,
        %{"original" => nil, "busy" => nil, "edge" => prior},
        @profile,
        c.base["limits"]
      )
end
