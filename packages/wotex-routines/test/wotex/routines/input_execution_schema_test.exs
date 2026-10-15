defmodule Wotex.Routines.InputExecutionSchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  setup_all do
    root = :wotex_routines |> :code.priv_dir() |> List.to_string()
    read = fn path -> root |> Path.join(path) |> File.read!() |> JSON.decode!() end
    corpus = read.("vectors/wro-05-input-execution.json")
    entry = read.("schemas/wro-05-input-execution.schema.json")
    %{root: root, corpus: corpus, entry: ExJsonSchema.Schema.resolve(entry)}
  end

  test "entry grammar distinguishes exact/floor clocks and legacy/external bindings", c do
    join = c.corpus["join"]
    clock = join["mapping"]["receipt_clock"]
    binding = join["expected_binding_basis"]

    for value <- [
          clock,
          Map.drop(clock, ~w(format projection)),
          binding,
          Map.take(binding, ~w(profile_digest source_id source_epoch source_time_basis))
        ] do
      assert :ok = ExJsonSchema.Validator.validate(c.entry, value)
    end
  end

  test "floor clock grammar rejects implicit mode, malformed coordinates and mixed fields", c do
    clock = c.corpus["join"]["mapping"]["receipt_clock"]

    for changed <-
          [
            Map.delete(clock, "format"),
            Map.delete(clock, "projection"),
            Map.put(clock, "format", "wotex.routines.receipt-clock@2"),
            Map.put(clock, "projection", "nearest"),
            Map.put(clock, "extra", true),
            Map.put(clock, "source_epoch", String.duplicate("F", 32)),
            Map.put(clock, "target_epoch", <<0>>),
            Map.put(clock, "target_origin_ms", -1),
            Map.put(clock, "target_origin_ms", 9_223_372_036_854_775_808)
          ] ++
            Enum.map(~w(-0 +0 01 1.0), &Map.put(clock, "source_origin_us", &1)) do
      assert {:error, _} = ExJsonSchema.Validator.validate(c.entry, changed)
    end
  end

  test "every external binding member is required and the embedded mapping stays closed", c do
    binding = c.corpus["join"]["expected_binding_basis"]

    for key <- Map.keys(binding) do
      assert {:error, _} = ExJsonSchema.Validator.validate(c.entry, Map.delete(binding, key))
    end

    for changed <- [
          Map.put(binding, "extra", false),
          Map.put(binding, "input_mapping", nil),
          Map.put(binding, "profile_digest", String.duplicate("a", 64)),
          Map.put(binding, "source_epoch", "source:unqualified"),
          put_in(binding, ["input_mapping", "extra"], true)
        ] do
      assert {:error, _} = ExJsonSchema.Validator.validate(c.entry, changed)
    end
  end

  test "all embedded Fact schemas retain explicit null UTC while rejecting omission and bad types",
       c do
    fact = c.corpus["join"]["expected_fact"]
    assert fact["received_at"] == nil

    for path <- Path.wildcard(Path.join(c.root, "schemas/*.json")),
        schema = path |> File.read!() |> JSON.decode!(),
        Map.has_key?(Map.get(schema, "definitions", %{}), "fact") do
      schema = definition(schema, "fact")
      assert :ok = ExJsonSchema.Validator.validate(schema, fact), path

      for changed <- [
            Map.delete(fact, "received_at"),
            Map.put(fact, "received_at", true),
            Map.put(fact, "received_at", "not-a-time"),
            Map.put(fact, "extra", nil)
          ] do
        assert {:error, _} = ExJsonSchema.Validator.validate(schema, changed), path
      end
    end
  end

  test "new clock is accepted only as its complete nested mapping variant", c do
    path = Path.join(c.root, "schemas/wro-05-input.schema.json")
    schema = path |> File.read!() |> JSON.decode!() |> ExJsonSchema.Schema.resolve()
    mapping = c.corpus["join"]["mapping"]
    assert :ok = ExJsonSchema.Validator.validate(schema, mapping)

    for key <- ~w(format projection source_epoch source_origin_us target_epoch target_origin_ms) do
      changed = update_in(mapping, ["receipt_clock"], &Map.delete(&1, key))
      assert {:error, _} = ExJsonSchema.Validator.validate(schema, changed)
    end
  end

  test "snapshot and retained edge schemas preserve the complete external binding", c do
    binding = c.corpus["join"]["expected_binding_basis"]
    fact = c.corpus["join"]["expected_fact"]

    snapshot = %{
      "id" => "snapshot:external",
      "membership_generation" => "membership:1",
      "active_programs" => ["sha256:" <> String.duplicate("7", 64)],
      "resource_revisions" => %{fact["thing_id"] => 1},
      "binding_bases" => %{"sensor" => binding},
      "facts" => %{"sensor" => fact}
    }

    edge = %{
      "format" => "wotex.routines.edge@1",
      "program_digest" => "sha256:" <> String.duplicate("7", 64),
      "binding" => "sensor",
      "binding_basis" => binding,
      "epoch" => fact["receipt_epoch"],
      "clock_generation" => "clock:1",
      "last_elapsed_ms" => fact["receipt_ms"],
      "last_receipt_ms" => nil,
      "last_sequence" => nil,
      "last_fact_id" => nil,
      "last_fact_digest" => nil,
      "baseline" => nil,
      "candidate_since_ms" => nil,
      "cooldown_until_ms" => 0,
      "last_original" => nil
    }

    for path <- Path.wildcard(Path.join(c.root, "schemas/*.json")),
        schema = path |> File.read!() |> JSON.decode!(),
        {name, value} <- [{"snapshot", snapshot}, {"edge", edge}],
        Map.has_key?(Map.get(schema, "definitions", %{}), name) do
      resolved = definition(schema, name)
      assert :ok = ExJsonSchema.Validator.validate(resolved, value), inspect({path, name})
    end
  end

  defp definition(schema, name) do
    schema
    |> Map.take(["$schema", "definitions"])
    |> Map.put("$ref", "#/definitions/" <> name)
    |> ExJsonSchema.Schema.resolve()
  end
end
