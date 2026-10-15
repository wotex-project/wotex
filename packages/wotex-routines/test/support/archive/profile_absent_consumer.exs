defmodule ProfileAbsentConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Basis, Error, Input, InputMapping}

  test "ordinary routine values work while the explicitly optional profile producer refuses" do
    v = Jason.decode!(File.read!("input.json"))
    refute Code.ensure_loaded?(Wotex.Profiles.Proposal)
    assert {:ok, _} = Basis.new(v["basis"], v["registry"], v["limits"])

    assert {:error, %Error{code: :missing_producer}} =
             InputMapping.new(v["mapping"], v["registry"], v["limits"])

    context = %{
      "registry" => v["registry"],
      "limits" => v["limits"],
      "reader_limits" => v["reader_limits"]
    }

    assert {:error, %Error{code: :missing_producer}} =
             Input.project(v["proposal"], v["mapping"], v["metadata"], context)

    assert {:error, %Error{code: :missing_producer}} =
             Input.binding_basis(v["mapping"], v["registry"], v["limits"])

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "ordinary-routine",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => [],
      "trigger" => %{"kind" => "manual"},
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{"id" => "end", "kind" => "noop"},
      "overlap" => "reject",
      "run_ms" => 1000
    }

    compiler_context = %{
      "registry" => [],
      "bases" => [],
      "bindings" => %{},
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    profile = %{
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

    assert {:ok, program} =
             Wotex.Routines.Compiler.compile(source, compiler_context, profile, v["limits"])

    snapshot = %{
      "id" => "snapshot:ordinary",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{},
      "binding_bases" => %{},
      "facts" => %{}
    }

    time = %{
      "epoch" => "clock:1",
      "elapsed_ms" => 0,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    event = %{
      "kind" => "manual",
      "original" => "ordinary:1",
      "program_digest" => program.data["ir_digest"]
    }

    prior = %{"original" => nil, "busy" => nil, "edge" => nil}

    assert {:ok, %{"outcome" => "completed", "proposals" => []}} =
             Wotex.Routines.Kernel.advance(
               program,
               event,
               snapshot,
               time,
               prior,
               profile,
               v["limits"]
             )

    refute Code.ensure_loaded?(Wotex.Profiles.Proposal)
  end
end
