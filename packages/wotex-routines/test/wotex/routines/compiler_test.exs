defmodule Wotex.Routines.CompilerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Compiler, Error, Limits, Profile, Program}

  @boolean %{"type" => "boolean", "unit" => nil, "enum" => []}
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
  @source %{
    "format" => "wotex.routines.source@1",
    "profile" => "bounded-composition@1",
    "id" => "root",
    "revision" => "1",
    "parameters" => %{"enabled" => @boolean},
    "bindings" => ["actuator"],
    "trigger" => %{"kind" => "manual"},
    "condition" => %{"op" => "literal", "value" => true},
    "steps" => %{
      "kind" => "effect",
      "id" => "apply",
      "binding" => "actuator",
      "input" => %{"parameter" => "enabled"},
      "completion" => "reported_match"
    },
    "overlap" => "reject",
    "run_ms" => 60_000
  }

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} = Limits.new(corpus["limits"])
    {:ok, profile} = Profile.new(@profile)
    basis = Enum.at(corpus["bases"], 2)

    binding = %{
      "basis" => Map.take(basis, ~w(id version semantic_digest)),
      "thing_id" => "urn:workcell:output",
      "resource_roles" => %{"target" => "resource:1"}
    }

    context = %{
      "registry" => corpus["registry"],
      "bases" => corpus["bases"],
      "bindings" => %{"actuator" => binding},
      "definitions" => [],
      "arguments" => %{"enabled" => false},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    %{corpus: corpus, limits: limits, profile: profile, context: context}
  end

  test "closed compiler context rejects foreign, duplicate, missing and over-capacity members", c do
    child = %{
      @source
      | "id" => "child"
    }

    contexts = [
      %{c.context | "bases" => nil},
      %{c.context | "bases" => [hd(c.context["bases"]) | c.context["bases"]]},
      %{c.context | "bases" => [Map.put(hd(c.context["bases"]), "extra", true)]},
      %{c.context | "definitions" => nil},
      %{c.context | "definitions" => [child, child]},
      %{c.context | "definitions" => [Map.put(child, "extra", true)]},
      %{c.context | "definitions" => Enum.map(1..64, &%{child | "id" => "child:#{&1}"})},
      put_in(c.context, ["arguments", "enabled"], "not-a-boolean"),
      put_in(c.context, ["bindings", "actuator", "thing_id"], "relative"),
      put_in(c.context, ["bindings", "actuator", "resource_roles"], %{})
    ]

    for context <- contexts do
      assert {:error, %Error{}} = Compiler.compile(@source, context, c.profile, c.limits)
    end

    context = %{c.context | "bases" => []}

    assert {:error, %Error{code: :unknown_binding_basis}} =
             Compiler.compile(@source, context, c.profile, c.limits)
  end

  test "predicate, argument, parallel and waiting limits refuse unsupported source before compilation",
       c do
    noop = %{"id" => "leaf", "kind" => "noop"}

    sources = [
      %{@source | "parameters" => []},
      %{@source | "trigger" => %{"kind" => "unimplemented"}},
      %{@source | "condition" => %{"op" => "unimplemented"}},
      %{
        @source
        | "condition" => %{"op" => "all", "args" => List.duplicate(@source["condition"], 65)}
      },
      %{
        @source
        | "steps" => %{
            "id" => "parallel",
            "kind" => "parallel",
            "branches" => Enum.map(1..5, &%{noop | "id" => "leaf:#{&1}"})
          }
      },
      %{
        @source
        | "steps" => %{
            "id" => "call",
            "kind" => "invoke",
            "routine_id" => "child",
            "revision" => "1",
            "arguments" => []
          }
      },
      put_in(@source, ["steps", "input"], %{"unsupported" => true}),
      %{@source | "steps" => %{"id" => "delay", "kind" => "delay", "duration_ms" => 60_001}},
      %{
        @source
        | "steps" => %{
            "id" => "wait",
            "kind" => "wait",
            "condition" => %{"op" => "unsupported"},
            "timeout_ms" => 100
          }
      }
    ]

    for source <- sources do
      assert {:error, %Error{}} = Compiler.compile(source, c.context, c.profile, c.limits)
    end

    {:ok, smaller} = Profile.new(%{c.profile.data | "waits" => 1})

    for kind <- ~w(wait delay) do
      first =
        if kind == "wait",
          do: %{
            "id" => "first",
            "kind" => kind,
            "condition" => @source["condition"],
            "timeout_ms" => 10
          },
          else: %{"id" => "first", "kind" => kind, "duration_ms" => 10}

      source = %{
        @source
        | "steps" => %{
            "id" => "sequence",
            "kind" => "sequence",
            "steps" => [first, %{first | "id" => "second"}]
          }
      }

      assert {:error, %Error{code: :wait_bound}} =
               Compiler.compile(source, c.context, smaller, c.limits)
    end
  end

  test "enum and integer argument contracts never coerce malformed or out-of-domain values", c do
    for contract <- [
          %{"type" => "enum", "unit" => nil, "enum" => ["enabled", "disabled"]},
          %{"type" => "integer", "unit" => hd(c.corpus["bases"])["value"]["unit"], "enum" => []}
        ] do
      source = %{
        @source
        | "parameters" => %{"enabled" => contract},
          "steps" => %{"id" => "none", "kind" => "noop"}
      }

      for value <- [true, nil, %{}, "not-enumerated"] do
        assert {:error, %Error{}} =
                 Compiler.compile(
                   source,
                   put_in(c.context, ["arguments", "enabled"], value),
                   c.profile,
                   c.limits
                 )
      end
    end

    for contract <- [
          %{"type" => "boolean", "unit" => %{}, "enum" => []},
          %{"type" => "integer", "unit" => %{}, "enum" => []}
        ] do
      source = %{@source | "parameters" => %{"enabled" => contract}}
      assert {:error, %Error{}} = Compiler.compile(source, c.context, c.profile, c.limits)
    end
  end

  test "full compilation resolves literals, complete basis and deterministic identities", context do
    assert {:ok, program} =
             Compiler.compile(@source, context.context, context.profile, context.limits)

    assert program.data["ir"]["steps"]["input"] == false
    assert program.data["ir"]["steps"]["path"] == []
    assert program.data["ir"]["steps"]["evidence_contract"]["id"] == "qualified-report"
    assert Compiler.current(program, context.context, context.profile, context.limits) == :ok

    assert {:ok, ^program} =
             Compiler.compile(@source, context.context, context.profile, context.limits)

    assert Compiler.to_map(program, context.profile, context.limits) == {:ok, program.data}

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-02-program.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, program.data) == :ok
  end

  test "recomputed digests cannot make altered IR current", context do
    {:ok, program} = Compiler.compile(@source, context.context, context.profile, context.limits)
    data = put_in(program.data, ["ir", "steps", "input"], true)

    commitment = %{
      "source_digest" => data["source_digest"],
      "ir" => data["ir"],
      "profile" => data["profile"],
      "compiler_profile" => data["compiler_profile"]
    }

    {:ok, encoded} = Wotex.JSON.encode(commitment)
    digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
    forged = %Program{data: Map.put(data, "ir_digest", digest)}

    assert {:error, %Error{code: :stale_or_forged_program}} =
             Compiler.current(forged, context.context, context.profile, context.limits)

    assert {:error, %Error{}} =
             Compiler.to_map(struct!(Program, data: %{}), context.profile, context.limits)
  end

  test "complete bound child conditions and independent call paths survive expansion", context do
    child = child()
    invocation = invoke("first")

    source = %{
      @source
      | "steps" => %{
          "kind" => "parallel",
          "id" => "fork",
          "branches" => [invocation, invoke("second")]
        }
    }

    settings = %{context.context | "definitions" => [child]}
    assert {:ok, program} = Compiler.compile(source, settings, context.profile, context.limits)
    [first, second] = program.data["ir"]["steps"]["branches"]
    assert first["condition"] == [["literal", false]]
    assert first["body"]["input"] == false
    assert first["body"]["path"] == [0, 0]
    assert second["body"]["path"] == [1, 0]
    assert first["run_ms"] == child["run_ms"]

    assert {:error, %Error{code: :expansion_bound}} =
             Compiler.compile(source, settings, %{@profile | "effects" => 1}, context.limits)
  end

  test "missing revisions and recursion anywhere in the supplied closure reject", context do
    source = %{@source | "steps" => invoke("call")}

    assert {:error, %Error{code: :missing_child_revision}} =
             Compiler.compile(source, context.context, context.profile, context.limits)

    recursive = %{
      child()
      | "steps" => %{
          "kind" => "invoke",
          "id" => "again",
          "routine_id" => "root",
          "revision" => "1",
          "arguments" => %{"enabled" => %{"parameter" => "on"}}
        }
    }

    assert {:error, %Error{code: :recursive_invocation}} =
             Compiler.compile(
               source,
               %{context.context | "definitions" => [recursive]},
               context.profile,
               context.limits
             )

    unused = %{
      child()
      | "steps" => %{
          "kind" => "invoke",
          "id" => "self",
          "routine_id" => "child",
          "revision" => "1",
          "arguments" => %{"on" => %{"parameter" => "on"}}
        }
    }

    assert {:error, %Error{code: :recursive_invocation}} =
             Compiler.compile(
               @source,
               %{context.context | "definitions" => [unused]},
               context.profile,
               context.limits
             )
  end

  test "parameters convert exact units rather than reinterpreting integers", context do
    scalar = hd(context.corpus["bases"])
    kelvin = hd(context.corpus["conversions"])["to"]
    parameter = %{"type" => "integer", "unit" => kelvin, "enum" => []}

    source = %{
      @source
      | "bindings" => ["actuator", "sensor"],
        "parameters" => Map.put(@source["parameters"], "temperature", parameter),
        "condition" => %{
          "op" => "eq",
          "binding" => "sensor",
          "value" => %{"parameter" => "temperature"}
        }
    }

    sensor = %{
      "basis" => Map.take(scalar, ~w(id version semantic_digest)),
      "thing_id" => "urn:workcell:sensor",
      "resource_roles" => %{}
    }

    settings = %{
      context.context
      | "bindings" => Map.put(context.context["bindings"], "sensor", sensor),
        "arguments" => %{"enabled" => false, "temperature" => 298_150}
    }

    assert {:ok, program} = Compiler.compile(source, settings, context.profile, context.limits)
    assert program.data["ir"]["condition"] == [["eq", "sensor", 2500]]

    assert {:error, %Error{code: :inexact_conversion}} =
             Compiler.compile(
               source,
               put_in(settings, ["arguments", "temperature"], 298_151),
               context.profile,
               context.limits
             )
  end

  test "missing bindings, arguments and weaker completion thresholds refuse", context do
    for settings <- [
          %{context.context | "bindings" => %{}},
          %{context.context | "arguments" => %{}},
          Map.put(context.context, "transport_callback", "execute")
        ] do
      assert {:error, %Error{}} =
               Compiler.compile(@source, settings, context.profile, context.limits)
    end

    source = put_in(@source, ["steps", "completion"], "protocol_response")

    assert {:error, %Error{code: :incompatible_effect}} =
             Compiler.compile(source, context.context, context.profile, context.limits)
  end

  test "unused invocation argument mistakes reject the whole supplied closure", context do
    target = %{child() | "id" => "target"}

    unused = %{
      child()
      | "steps" => %{
          "kind" => "invoke",
          "id" => "bad",
          "routine_id" => "target",
          "revision" => "1",
          "arguments" => %{}
        }
    }

    settings = %{context.context | "definitions" => [unused, target]}

    assert {:error, %Error{code: :missing_field}} =
             Compiler.compile(@source, settings, context.profile, context.limits)
  end

  defp child do
    %{
      @source
      | "id" => "child",
        "parameters" => %{"on" => @boolean},
        "condition" => %{"op" => "literal", "value" => false},
        "steps" => %{
          "kind" => "effect",
          "id" => "apply",
          "binding" => "actuator",
          "input" => %{"parameter" => "on"},
          "completion" => "reported_match"
        },
        "run_ms" => 30_000
    }
  end

  defp invoke(id) do
    %{
      "kind" => "invoke",
      "id" => id,
      "routine_id" => "child",
      "revision" => "1",
      "arguments" => %{"on" => %{"parameter" => "enabled"}}
    }
  end
end
