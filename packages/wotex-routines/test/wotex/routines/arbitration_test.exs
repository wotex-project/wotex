defmodule Wotex.Routines.ArbitrationTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Arbitration, Collection, Compiler, Error, Limits, Profile}

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

    %{corpus: corpus, limits: limits, profile: profile}
  end

  test "conflict beyond the batch cutoff prevents both effects", c do
    input = input(c, [{"a", false, "one"}, {"b", true, "one"}])
    assert {:ok, collection} = Collection.evaluate(input, c.profile, c.limits)
    assert length(collection.data["proposals"]) == 2
    assert {:ok, result} = decide(c, collection, 1)
    assert result["selected"] == []
    assert Enum.map(result["decisions"], & &1["outcome"]) == ["conflict", "conflict"]

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-02-collection.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    for value <- [input, collection.data, result] do
      assert ExJsonSchema.Validator.validate(schema, value) == :ok
    end

    reversed = %{input | "entries" => Enum.reverse(input["entries"])}
    assert {:ok, reverse_collection} = Collection.evaluate(reversed, c.profile, c.limits)
    assert reverse_collection.data["proposals"] == collection.data["proposals"]
  end

  test "equivalent effects coalesce while preserving every original and step identity", c do
    assert {:ok, collection} =
             Collection.evaluate(
               input(c, [{"a", false, "one"}, {"b", false, "one"}]),
               c.profile,
               c.limits
             )

    assert {:ok, result} = decide(c, collection, 1)
    assert [contributors] = result["selected"]
    assert Enum.sort(Enum.map(contributors, & &1["original"])) == ["original:a", "original:b"]
    assert Enum.sort(Enum.map(result["decisions"], & &1["outcome"])) == ["coalesced", "selected"]
    assert Collection.to_map(collection, c.profile, c.limits) == {:ok, collection.data}
    proposals = put_in(collection.data, ["proposals", Access.at(0), "input"], true)

    assert {:error, %Error{code: :stale_or_forged_collection}} =
             Collection.to_map(%Collection{data: proposals}, c.profile, c.limits)
  end

  test "hard constraints run before overrides and selected overrides do not hide conflicting selections",
       c do
    assert {:ok, collection} =
             Collection.evaluate(
               input(c, [{"a", false, "one"}, {"b", true, "one"}]),
               c.profile,
               c.limits
             )

    [first, second] = collection.data["proposals"]
    ds = dispositions(collection)
    ds = put_in(ds, [first["step_original"], "override"], "selected")
    assert {:ok, result} = Arbitration.decide(collection, ds, 1, c.profile, c.limits)
    assert length(result["selected"]) == 1
    assert Enum.map(result["decisions"], & &1["outcome"]) == ["selected", "override-suppressed"]
    ds = put_in(ds, [first["step_original"], "constraint"], "unknown")
    assert {:ok, result} = Arbitration.decide(collection, ds, 1, c.profile, c.limits)
    assert Enum.map(result["decisions"], & &1["outcome"]) == ["constraint-unknown", "selected"]

    ds =
      dispositions(collection)
      |> put_in([first["step_original"], "override"], "selected")
      |> put_in([second["step_original"], "override"], "selected")

    assert {:ok, result} = Arbitration.decide(collection, ds, 1, c.profile, c.limits)
    assert result["selected"] == []
    assert Enum.all?(result["decisions"], &(&1["outcome"] == "conflict"))
  end

  test "batching follows full-set evaluation and whole-Thing conflict includes different role domains",
       c do
    assert {:ok, collection} =
             Collection.evaluate(
               input(c, [{"a", false, "one"}, {"b", false, "two"}]),
               c.profile,
               c.limits
             )

    assert {:ok, result} = decide(c, collection, 1)
    assert length(result["selected"]) == 1
    assert Enum.map(result["decisions"], & &1["outcome"]) == ["selected", "batch-deferred"]
    input = input(c, [{"a", false, "one"}, {"b", true, "one"}])
    [first, second] = input["entries"]
    program = second["program"]

    context =
      put_in(
        program["context"],
        ["bindings", "output", "resource_roles", "target"],
        "resource:other"
      )

    {:ok, changed} = Compiler.compile(program["source"], context, c.profile, c.limits)

    second = %{
      second
      | "program" => changed.data,
        "event" => %{second["event"] | "program_digest" => changed.data["ir_digest"]},
        "snapshot" => %{
          second["snapshot"]
          | "resource_revisions" => %{"urn:output:one" => 1, "resource:other" => 1}
        }
    }

    input = membership(%{input | "entries" => [first, second]})
    assert {:ok, collection} = Collection.evaluate(input, c.profile, c.limits)
    assert {:ok, result} = decide(c, collection, 1)
    assert result["selected"] == []
  end

  test "membership omissions, duplicates and inconsistent shared bases refuse the complete set",
       c do
    input = input(c, [{"a", false, "one"}, {"b", false, "one"}])
    [first, second] = input["entries"]

    for bad <- [
          %{input | "entries" => [first]},
          %{input | "entries" => [first, first]},
          %{input | "entries" => [first, put_in(second, ["snapshot", "id"], "snapshot:other")]},
          %{
            input
            | "entries" => [
                first,
                put_in(second, ["snapshot", "membership_generation"], "membership:old")
              ]
          },
          %{
            input
            | "entries" => [
                first,
                put_in(second, ["snapshot", "resource_revisions", "resource:one"], 2)
              ]
          },
          %{
            input
            | "entries" => [
                first,
                put_in(second, ["snapshot", "binding_bases", "output", "source_epoch"], "other")
              ]
          },
          %{input | "entries" => [first, Map.put(second, "unknown", true)]}
        ] do
      assert {:error, %Error{}} = Collection.evaluate(bad, c.profile, c.limits)
    end
  end

  test "idle entries still validate complete programs, snapshots and retained originals", c do
    input = input(c, [{"a", false, "one"}])
    [entry] = input["entries"]
    idle = %{input | "entries" => [%{entry | "event" => nil}]}
    assert {:ok, collection} = Collection.evaluate(idle, c.profile, c.limits)
    assert collection.data["proposals"] == []
    assert hd(collection.data["transitions"])["result"] == nil
    forged = put_in(idle, ["entries", Access.at(0), "program", "ir", "steps", "input"], true)
    assert {:error, %Error{}} = Collection.evaluate(forged, c.profile, c.limits)
    malformed = put_in(idle, ["entries", Access.at(0), "prior", "original"], %{})
    assert {:error, %Error{}} = Collection.evaluate(malformed, c.profile, c.limits)
  end

  test "missing/extra dispositions, source priorities, invalid batches and pending bounds refuse",
       c do
    assert {:ok, collection} =
             Collection.evaluate(input(c, [{"a", false, "one"}]), c.profile, c.limits)

    ds = dispositions(collection)
    [id] = Map.keys(ds)

    for bad <- [
          %{},
          Map.put(ds, "extra", ds[id]),
          put_in(ds, [id, "authority"], 100),
          put_in(ds, [id, "constraint"], "maybe")
        ] do
      assert {:error, %Error{}} = Arbitration.decide(collection, bad, 1, c.profile, c.limits)
    end

    for batch <- [0, 65, 1.5, nil] do
      assert {:error, %Error{}} = Arbitration.decide(collection, ds, batch, c.profile, c.limits)
    end

    {:ok, narrow} = Profile.new(%{c.profile.data | "pending_work" => 1})

    assert {:error, %Error{code: :pending_work_bound}} =
             Collection.evaluate(
               input(%{c | profile: narrow}, [{"a", false, "one"}, {"b", false, "two"}]),
               narrow,
               c.limits
             )
  end

  test "active run and whole-set bounds apply independently of the batch size", c do
    {:ok, narrow} = Profile.new(%{c.profile.data | "active_runs" => 1})
    c = %{c | profile: narrow}

    assert {:error, %Error{code: :active_run_bound}} =
             Collection.evaluate(
               input(c, [{"a", false, "one"}, {"b", false, "two"}]),
               narrow,
               c.limits
             )
  end

  test "explicit empty membership yields no decisions without asserting omitted work is safe", c do
    assert {:ok, collection} = Collection.evaluate(input(c, []), c.profile, c.limits)
    assert {:ok, result} = decide(c, collection, 1)
    assert result["selected"] == []
    assert result["decisions"] == []
  end

  defp input(c, definitions) do
    entries = Enum.map(definitions, fn {id, value, target} -> entry(c, id, value, target) end)

    membership(%{
      "entries" => entries,
      "membership" => %{"generation" => "membership:1", "programs" => []},
      "time" => %{
        "epoch" => "boot:1",
        "elapsed_ms" => 20,
        "clock_generation" => "clock:1",
        "utc_low_ms" => nil,
        "utc_high_ms" => nil
      }
    })
  end

  defp entry(c, id, value, target) do
    basis = Enum.at(c.corpus["bases"], 2)

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => id,
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["output"],
      "trigger" => %{"kind" => "manual"},
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{
        "id" => "apply",
        "kind" => "effect",
        "binding" => "output",
        "input" => value,
        "completion" => "reported_match"
      },
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => c.corpus["registry"],
      "bases" => c.corpus["bases"],
      "bindings" => %{
        "output" => %{
          "basis" => Map.take(basis, ~w(id version semantic_digest)),
          "thing_id" => "urn:output:#{target}",
          "resource_roles" => %{"target" => "resource:#{target}"}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)

    %{
      "program" => program.data,
      "event" => %{
        "kind" => "manual",
        "original" => "original:#{id}",
        "program_digest" => program.data["ir_digest"]
      },
      "snapshot" => %{
        "id" => "snapshot:1",
        "membership_generation" => "membership:1",
        "active_programs" => [],
        "resource_revisions" => %{"urn:output:#{target}" => 1, "resource:#{target}" => 1},
        "binding_bases" => %{
          "output" => %{
            "profile_digest" => basis["semantic_digest"],
            "source_id" => "device:#{target}",
            "source_epoch" => "connection:1",
            "source_time_basis" => nil
          }
        },
        "facts" => %{"output" => nil}
      },
      "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
    }
  end

  defp membership(input) do
    digests = Enum.map(input["entries"], & &1["program"]["ir_digest"])

    %{
      input
      | "membership" => %{input["membership"] | "programs" => digests},
        "entries" =>
          Enum.map(input["entries"], &put_in(&1, ["snapshot", "active_programs"], digests))
    }
  end

  defp dispositions(collection),
    do:
      Map.new(
        collection.data["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

  defp decide(c, collection, batch),
    do: Arbitration.decide(collection, dispositions(collection), batch, c.profile, c.limits)
end
