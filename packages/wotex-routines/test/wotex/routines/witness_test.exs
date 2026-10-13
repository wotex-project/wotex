defmodule Wotex.Routines.WitnessTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Compiler, Error, Kernel, Limits, Profile, Witness, WitnessProperties}

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} = Limits.new(corpus["limits"])

    {:ok, profile} =
      Profile.new(%{
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
      })

    basis = Enum.at(corpus["bases"], 2)

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "bounded-process",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["output"],
      "trigger" => %{"kind" => "manual"},
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{
        "id" => "apply",
        "kind" => "effect",
        "binding" => "output",
        "input" => false,
        "completion" => "reported_match"
      },
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => corpus["registry"],
      "bases" => corpus["bases"],
      "bindings" => %{
        "output" => %{
          "basis" => Map.take(basis, ~w(id version semantic_digest)),
          "thing_id" => "urn:cell:output",
          "resource_roles" => %{"target" => "cell:1"}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(source, context, profile, limits)

    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{"urn:cell:output" => 1, "cell:1" => 1},
      "binding_bases" => %{
        "output" => %{
          "profile_digest" => basis["semantic_digest"],
          "source_id" => "output:1",
          "source_epoch" => "connection:1",
          "source_time_basis" => nil
        }
      },
      "facts" => %{"output" => nil}
    }

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 20,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    %{
      limits: limits,
      profile: profile,
      basis: basis,
      program: program,
      snapshot: snapshot,
      time: time,
      source: source,
      context: context
    }
  end

  test "a complete staged/cancelled trace does not reproduce a false software violation", c do
    frames = [
      frame(c, "manual"),
      frame(c, "admission"),
      frame(c, "handoff"),
      frame(c, "result", "protocol_response"),
      frame(c, "cancel"),
      frame(c, "result", "reported_match"),
      frame(c, "manual")
    ]

    for property <- ~w(proposal_once held_spend_retained stopped_continuation completion_evidence) do
      input = witness(c, property, frames)
      assert {:ok, result} = Witness.replay(c.program, input, c.profile, c.limits)
      assert result["reproduced"] == false
      assert result["violation_step"] == nil
      assert length(result["transitions"]) == 7
      last = List.last(result["transitions"])
      assert last["outcome"] == "cancelled"
      assert hd(last["run"]["steps"])["status"] == "completed"
      assert length(last["run"]["spent"]) == 1
      assert result == elem(Witness.replay(c.program, input, c.profile, c.limits), 1)
      schema = schema()
      assert ExJsonSchema.Validator.validate(schema, input) == :ok
      assert ExJsonSchema.Validator.validate(schema, result) == :ok
    end
  end

  test "initial history preserves previous proposal identity and handoff evidence", c do
    {:ok, first} = advance(c, frame(c, "manual"), nil)

    input =
      witness(c, "proposal_once", [
        frame(c, "manual"),
        frame(c, "admission"),
        frame(c, "handoff"),
        frame(c, "result", "reported_match")
      ])

    input = put_in(input, ["initial", "runs"], [first["run"]])
    assert {:ok, result} = Witness.replay(c.program, input, c.profile, c.limits)
    assert result["reproduced"] == false
    assert hd(result["transitions"])["proposals"] == []
    assert List.last(result["transitions"])["outcome"] == "completed"
  end

  test "each exact program subject invalidates a stale witness", c do
    input = witness(c, "proposal_once", [frame(c, "manual")])

    for subject <- ~w(program_digest source_digest compiler_basis) do
      changed = Map.put(input, subject, "sha256:" <> String.duplicate("8", 64))

      assert {:error, %Error{code: :stale_witness}} =
               Witness.replay(c.program, changed, c.profile, c.limits)
    end

    assert {:ok, first} = Witness.replay(c.program, input, c.profile, c.limits)
    changed = put_in(input, ["frames", Access.at(0), "snapshot", "id"], "snapshot:2")
    assert {:ok, second} = Witness.replay(c.program, changed, c.profile, c.limits)
    assert first["trace_digest"] != second["trace_digest"]
  end

  test "input/work ceilings, field closure and invalid retained history refuse", c do
    input = witness(c, "proposal_once", [frame(c, "manual")])
    {:ok, first} = advance(c, frame(c, "manual"), nil)
    {:ok, other} = advance(c, put_in(frame(c, "manual"), ["event", "original"], "original:2"), nil)

    for changed <- [
          Map.put(input, "expected_output", %{}),
          %{input | "frames" => []},
          %{input | "max_steps" => 0},
          %{input | "max_steps" => 257},
          %{input | "max_originals" => 1025},
          %{input | "property" => "physical_effect"},
          put_in(input, ["frames", Access.at(0), "extra"], true),
          put_in(input, ["initial", "runs"], [first["run"], first["run"]]),
          put_in(input, ["initial", "runs"], [first["run"], other["run"]]),
          put_in(input, ["initial", "runs"], [%{first["run"] | "source_digest" => "forged"}]),
          put_in(input, ["initial", "edge"], %{}),
          %{input | "initial" => nil}
        ] do
      assert {:error, %Error{}} = Witness.replay(c.program, changed, c.profile, c.limits)
    end

    over = %{input | "frames" => [frame(c, "manual"), frame(c, "manual")], "max_steps" => 1}

    assert {:error, %Error{code: :witness_step_bound}} =
             Witness.replay(c.program, over, c.profile, c.limits)
  end

  test "a later kernel refusal invalidates the complete claimed witness", c do
    input = witness(c, "proposal_once", [frame(c, "manual"), frame(c, "handoff")])

    assert {:error, %Error{code: :out_of_order_receipt}} =
             Witness.replay(c.program, input, c.profile, c.limits)
  end

  test "retained terminal originals count against the explicit replay ledger ceiling", c do
    source = %{c.source | "steps" => %{"id" => "noop", "kind" => "noop"}}
    {:ok, program} = Compiler.compile(source, c.context, c.profile, c.limits)

    c = %{
      c
      | program: program,
        snapshot: %{c.snapshot | "active_programs" => [program.data["ir_digest"]]}
    }

    frames = [frame(c, "manual"), put_in(frame(c, "manual"), ["event", "original"], "original:2")]
    input = %{witness(c, "proposal_once", frames) | "max_originals" => 1}

    assert {:error, %Error{code: :witness_original_bound}} =
             Witness.replay(c.program, input, c.profile, c.limits)
  end

  test "independent record checks detect mutations without treating forged records as public evidence",
       c do
    {:ok, first} = advance(c, frame(c, "manual"), nil)
    {:ok, held} = advance(c, frame(c, "admission"), first["run"])
    {:ok, handed} = advance(c, frame(c, "handoff"), held["run"])
    seen = WitnessProperties.started([held["run"]])
    assert WitnessProperties.violated?("proposal_once", nil, first, c.program.data, seen)
    refunded = put_in(held, ["run", "spent"], [])

    assert WitnessProperties.violated?(
             "held_spend_retained",
             held["run"],
             refunded,
             c.program.data,
             seen
           )

    stopped = %{held["run"] | "status" => "cancelled"}
    assert WitnessProperties.violated?("stopped_continuation", stopped, first, c.program.data, seen)
    completed = put_in(handed, ["run", "steps", Access.at(0), "status"], "completed")
    assert WitnessProperties.violated?("completion_evidence", nil, completed, c.program.data, seen)

    queued =
      put_in(completed, ["run", "steps", Access.at(0), "receipts", "protocol_response"], %{
        "outcome" => "accepted"
      })

    assert WitnessProperties.violated?("completion_evidence", nil, queued, c.program.data, seen)
    input = witness(c, "completion_evidence", [frame(c, "manual")])
    input = put_in(input, ["initial", "runs"], [queued["run"]])
    assert {:error, %Error{}} = Witness.replay(c.program, input, c.profile, c.limits)
  end

  test "amplified transition output obeys the same explicit byte ceiling", c do
    {:ok, limits} = Limits.new(%{c.limits.data | "max_bytes" => 32_768})
    {:ok, program} = Compiler.compile(c.source, c.context, c.profile, limits)

    c = %{
      c
      | program: program,
        snapshot: %{c.snapshot | "active_programs" => [program.data["ir_digest"]]}
    }

    input = witness(c, "proposal_once", List.duplicate(frame(c, "manual"), 32))
    assert {:ok, _} = Wotex.JSON.encode(input, max_bytes: 32_768)

    assert {:error, %Error{code: :limit_or_json_error}} =
             Witness.replay(c.program, input, c.profile, limits)
  end

  defp frame(c, kind, stage \\ nil) do
    event = %{
      "kind" => kind,
      "original" => "original:1",
      "program_digest" => c.program.data["ir_digest"]
    }

    event =
      case kind do
        "admission" ->
          Map.merge(event, %{"path" => [], "ref" => "held:1", "outcome" => "held"})

        "handoff" ->
          Map.merge(event, %{"path" => [], "ref" => "handoff:1"})

        "result" ->
          Map.merge(event, %{
            "path" => [],
            "ref" => "result:" <> stage,
            "stage" => stage,
            "outcome" => "accepted",
            "report_contract" =>
              if(stage in ~w(correlated_report reported_match),
                do: c.basis["evidence"]["report_contract"],
                else: nil
              )
          })

        _ ->
          event
      end

    %{"event" => event, "snapshot" => c.snapshot, "time" => c.time}
  end

  defp witness(c, property, frames),
    do: %{
      "format" => "wotex.routines.witness@1",
      "property" => property,
      "program_digest" => c.program.data["ir_digest"],
      "source_digest" => c.program.data["source_digest"],
      "compiler_basis" => c.program.data["context"]["compiler_basis"],
      "max_steps" => 64,
      "max_originals" => 64,
      "initial" => %{"runs" => [], "edge" => nil},
      "frames" => frames
    }

  defp advance(c, frame, run),
    do:
      Kernel.advance(
        c.program,
        frame["event"],
        frame["snapshot"],
        frame["time"],
        %{"original" => run, "busy" => nil, "edge" => nil},
        c.profile,
        c.limits
      )

  defp schema do
    :wotex_routines
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("schemas/wro-04-witness.schema.json")
    |> File.read!()
    |> JSON.decode!()
    |> ExJsonSchema.Schema.resolve()
  end
end
