Code.require_file("../../support/decision_fixtures.exs", __DIR__)
Code.require_file("../../support/decision_reference.exs", __DIR__)

defmodule Wotex.Routines.DecisionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{
    Collection,
    Decision,
    DecisionArbitration,
    Error,
    Limits,
    Profile,
    Validation
  }

  alias Wotex.Routines.Test.{ContinuationFixtures, DecisionFixtures, DecisionReference}

  test "all public seams retain exact point data under both Time grammars" do
    for grammar <- [1, 2] do
      c = ContinuationFixtures.fixture() |> DecisionFixtures.elapsed()
      c = if grammar == 2, do: %{c | time: time2(c.time)}, else: c

      input =
        DecisionFixtures.input(
          c,
          DecisionFixtures.members(c, [{"b", false, "b"}, {"a", true, "a"}])
        )

      collection = DecisionFixtures.collection(c, input)
      assert :ok == proof(fn -> Decision.verify_point(input, collection, c.profile, c.limits) end)
      decision = DecisionFixtures.decision(c, collection)
      assert {:ok, data} = proof(fn -> Decision.to_map(decision, c.profile, c.limits) end)
      assert {:ok, ^data} = proof(fn -> Decision.to_map(data, c.profile, c.limits) end)
      current = DecisionFixtures.context(c, collection)
      current = put_in(current, ["input", "time", "elapsed_ms"], 21)
      assert {:ok, checked} = check(c, decision, current)

      assert Map.keys(checked) |> Enum.sort() ==
               ~w(arbitration checked_time collection_digest decision_digest format point_time proposal_states scope transitions)

      assert checked["transitions"] === collection.data["transitions"]
      assert checked["point_time"] === c.time
      assert checked["checked_time"] === current["input"]["time"]
      assert checked["proposal_states"] === collection.data["proposal_states"]
      assert data["cell"]["elapsed"] == %{"min" => 20, "max" => 1019}
    end
  end

  test "empty provided membership remains empty without discovering host members" do
    c = ContinuationFixtures.fixture()
    input = DecisionFixtures.input(c, [])
    collection = DecisionFixtures.collection(c, input)
    decision = DecisionFixtures.decision(c, collection)
    assert decision.data["cell"]["utc_mode"] == "ignored"
    assert {:ok, checked} = check(c, decision, DecisionFixtures.context(c, collection))
    assert checked["transitions"] == []
    assert checked["arbitration"]["selected"] == []
    assert checked["scope"] == "provided_membership_time_cell_only"
  end

  test "legacy collections and forged native wrappers refuse without repair" do
    c = ContinuationFixtures.fixture()
    input = DecisionFixtures.input(c, DecisionFixtures.members(c, [{"a", false, "a"}]))
    legacy = Map.delete(input, "format")
    {:ok, collection1} = Collection.evaluate(legacy, c.profile, c.limits)

    assert {:error, %Error{code: :unsupported_decision_scope}} =
             proof(fn -> Decision.new(collection1, c.profile, c.limits) end)

    assert {:error, %Error{code: :unsupported_decision_scope}} =
             proof(fn -> Decision.verify_point(legacy, collection1, c.profile, c.limits) end)

    collection = DecisionFixtures.collection(c, input)
    decision = DecisionFixtures.decision(c, collection)

    assert {:error, %Error{code: :unsupported_decision_scope}} =
             proof(fn ->
               Decision.to_map(
                 %{decision.data | "format" => "wotex.routines.decision@2"},
                 c.profile,
                 c.limits
               )
             end)

    for value <- [Map.put(collection, :extra, true), decision, self(), [nil | :bad]] do
      assert {:error, %Error{}} = proof(fn -> Decision.new(value, c.profile, c.limits) end)
    end

    for value <- [Map.put(decision, :extra, true), collection, self(), [nil | :bad]] do
      assert {:error, %Error{}} = proof(fn -> Decision.to_map(value, c.profile, c.limits) end)
    end

    for key <- Map.keys(decision.data) do
      assert {:error, %Error{}} =
               proof(fn -> Decision.to_map(Map.delete(decision.data, key), c.profile, c.limits) end)
    end
  end

  test "every member participates in the time cell before a selected batch" do
    c = ContinuationFixtures.fixture() |> DecisionFixtures.elapsed()

    a =
      ContinuationFixtures.compile(c, %{
        "id" => "delayed",
        "steps" => ContinuationFixtures.delayed_effect()
      })

    b =
      ContinuationFixtures.compile(c, %{
        "id" => "ready",
        "steps" => ContinuationFixtures.effect("other", true)
      })

    input = DecisionFixtures.input(c, [a, b])
    collection = DecisionFixtures.collection(c, input)
    assert length(collection.data["proposals"]) == 1
    decision = DecisionFixtures.decision(c, collection)
    assert decision.data["cell"]["elapsed"] == %{"min" => 20, "max" => 119}
    context = DecisionFixtures.context(c, collection)
    assert {:ok, _} = check(c, decision, put_in(context, ["input", "time", "elapsed_ms"], 119))

    assert {:error, %Error{code: :stale_decision_time}} =
             check(c, decision, put_in(context, ["input", "time", "elapsed_ms"], 120))

    assert :ok == proof(fn -> Decision.verify_point(input, collection, c.profile, c.limits) end)
    fresh_input = put_in(DecisionFixtures.retained(collection), ["time", "elapsed_ms"], 120)
    fresh = DecisionFixtures.collection(c, fresh_input)
    fresh_decision = DecisionFixtures.decision(c, fresh)
    fresh_context = DecisionFixtures.context(c, fresh)
    assert {:ok, checked} = check(c, fresh_decision, fresh_context)
    assert Enum.all?(checked["arbitration"]["decisions"], &(&1["outcome"] == "conflict"))
    assert Enum.all?(checked["transitions"], &(&1["result"]["run"]["start_ms"] == 20))
  end

  test "irrelevant UTC loss and replacement preserve elapsed-only reuse" do
    c = ContinuationFixtures.fixture() |> DecisionFixtures.elapsed()
    c = %{c | time: time2(c.time)}

    collection =
      DecisionFixtures.collection(
        c,
        DecisionFixtures.input(c, DecisionFixtures.members(c, [{"a", false, "a"}]))
      )

    decision = DecisionFixtures.decision(c, collection)
    context = DecisionFixtures.context(c, collection)
    assert decision.data["cell"]["utc_mode"] == "ignored"

    for time <- [
          %{
            c.time
            | "utc_generation" => "utc:replacement",
              "utc_low_ms" => -100,
              "utc_high_ms" => 100
          },
          %{c.time | "utc_generation" => nil, "utc_low_ms" => nil, "utc_high_ms" => nil}
        ] do
      assert {:ok, _} = check(c, decision, put_in(context, ["input", "time"], time))
    end

    for time <- [
          %{c.time | "elapsed_ms" => 19},
          %{c.time | "epoch" => "boot:other"},
          %{c.time | "clock_generation" => "elapsed:other"},
          Map.drop(c.time, ~w(format utc_generation))
        ] do
      assert {:error, %Error{code: :stale_decision_time}} =
               check(c, decision, put_in(context, ["input", "time"], time))
    end
  end

  test "relevant UTC identity, absence and both full endpoints constrain reuse" do
    c = ContinuationFixtures.fixture(sensor: true) |> ContinuationFixtures.compile()
    sample = ContinuationFixtures.sample(c, 1, 20, 3000)
    c = %{c | time: time2(c.time), snapshot: sample.snapshot}
    collection = DecisionFixtures.collection(c, DecisionFixtures.input(c, [c]))
    decision = DecisionFixtures.decision(c, collection)
    cell = decision.data["cell"]
    assert cell["utc_mode"] == "present"
    context = DecisionFixtures.context(c, collection)

    for time <- [
          %{c.time | "utc_generation" => "utc:other"},
          %{c.time | "utc_generation" => nil, "utc_low_ms" => nil, "utc_high_ms" => nil},
          %{c.time | "utc_low_ms" => cell["utc_low"]["min"] - 1},
          %{c.time | "utc_high_ms" => cell["utc_high"]["max"] + 1}
        ] do
      assert {:error, %Error{code: :stale_decision_time}} =
               check(c, decision, put_in(context, ["input", "time"], time))
    end

    for key <- ~w(utc_low utc_high) do
      axis = key <> "_ms"

      for endpoint <- ~w(min max) do
        time = %{c.time | axis => cell[key][endpoint]}

        if time["utc_low_ms"] <= time["utc_high_ms"],
          do: assert({:ok, _} = check(c, decision, put_in(context, ["input", "time"], time)))
      end
    end
  end

  test "canonical cell narrowing, widening, rehashing and full digest mutations refuse" do
    c = ContinuationFixtures.fixture()

    collection =
      DecisionFixtures.collection(
        c,
        DecisionFixtures.input(c, DecisionFixtures.members(c, [{"a", false, "a"}]))
      )

    decision = DecisionFixtures.decision(c, collection)

    for offset <- [-1, 1] do
      wrong =
        update_in(decision.data, ["cell", "elapsed", "max"], &(&1 + offset))
        |> rehash("decision_digest", c)

      assert {:error, %Error{code: :invalid_collection_decision}} =
               proof(fn -> Decision.to_map(wrong, c.profile, c.limits) end)
    end

    for key <- Map.keys(decision.data["cell"]) do
      wrong =
        update_in(decision.data, ["cell"], &Map.delete(&1, key)) |> rehash("decision_digest", c)

      assert {:error, %Error{code: :invalid_collection_decision}} =
               proof(fn -> Decision.to_map(wrong, c.profile, c.limits) end)
    end
  end

  test "independently supplied input defeats rehashed member, pending and transition omissions" do
    c = ContinuationFixtures.fixture()

    input =
      DecisionFixtures.input(c, DecisionFixtures.members(c, [{"a", false, "a"}, {"b", true, "b"}]))

    collection = DecisionFixtures.collection(c, input)

    kept = hd(input["entries"])["program"]["ir_digest"]
    proposals = Enum.filter(collection.data["proposals"], &(&1["program_digest"] == kept))
    originals = Enum.map(proposals, & &1["step_original"])

    incomplete =
      %{
        collection.data
        | "input" => %{input | "entries" => [hd(input["entries"])]},
          "transitions" =>
            Enum.filter(collection.data["transitions"], &(&1["program_digest"] == kept)),
          "proposals" => proposals,
          "proposal_states" =>
            Enum.filter(collection.data["proposal_states"], &(&1["step_original"] in originals))
      }
      |> rehash("collection_digest", c)

    assert {:error, %Error{code: :invalid_collection_decision}} =
             proof(fn -> Decision.new(incomplete, c.profile, c.limits) end)

    for key <- ~w(proposals proposal_states transitions) do
      wrong = update_in(collection.data, [key], &tl/1) |> rehash("collection_digest", c)

      assert {:error, %Error{}} =
               proof(fn -> Decision.verify_point(input, wrong, c.profile, c.limits) end)
    end

    wrong =
      update_in(collection.data, ["input", "entries"], &tl/1) |> rehash("collection_digest", c)

    assert {:error, %Error{code: :invalid_collection_decision}} =
             proof(fn -> Decision.verify_point(input, wrong, c.profile, c.limits) end)

    wrong =
      put_in(
        collection.data,
        ["transitions", Access.at(0), "result", "basis", "time", "elapsed_ms"],
        21
      )
      |> rehash("collection_digest", c)

    assert {:error, %Error{code: :invalid_transition}} =
             proof(fn -> Decision.verify_point(input, wrong, c.profile, c.limits) end)
  end

  test "all current non-time input compares exactly before time or arbitration" do
    c = ContinuationFixtures.fixture(sensor: true) |> ContinuationFixtures.compile()
    sample = ContinuationFixtures.sample(c, 1, 20, 3000)
    c = %{c | snapshot: sample.snapshot}
    collection = DecisionFixtures.collection(c, DecisionFixtures.input(c, [c]))
    decision = DecisionFixtures.decision(c, collection)
    context = DecisionFixtures.context(c, collection)

    wrong =
      put_in(
        context,
        ["input", "entries", Access.at(0), "snapshot", "facts", "sensor", "value"],
        3000.0
      )

    assert {:error, %Error{code: :stale_decision_input}} = check(c, decision, wrong)
    wrong = put_in(wrong, ["input", "time", "elapsed_ms"], 0)
    assert {:error, %Error{code: :stale_decision_input}} = check(c, decision, wrong)
    bad_point = put_in(decision.data, ["cell", "elapsed", "max"], 0) |> rehash("decision_digest", c)
    assert {:error, %Error{code: :invalid_collection_decision}} = check(c, bad_point, wrong)
  end

  test "reserved equivalent contributors survive selection without renewed charge" do
    c = ContinuationFixtures.fixture()

    first =
      DecisionFixtures.collection(
        c,
        DecisionFixtures.input(
          c,
          DecisionFixtures.members(c, [{"a", false, "shared"}, {"b", false, "shared"}])
        )
      )

    next = DecisionFixtures.retained(first)
    entry = hd(next["entries"])

    event =
      Map.merge(entry["event"], %{
        "kind" => "admission",
        "path" => [],
        "ref" => "held:1",
        "outcome" => "held"
      })

    held = DecisionFixtures.collection(c, put_in(next, ["entries", Access.at(0), "event"], event))
    decision = DecisionFixtures.decision(c, held)
    assert {:ok, checked} = check(c, decision, DecisionFixtures.context(c, held))
    assert Enum.sort(Enum.map(checked["proposal_states"], & &1["status"])) == ~w(proposed reserved)
    assert [group] = checked["arbitration"]["selected"]
    assert length(group) == 2
    assert checked["transitions"] === held.data["transitions"]
  end

  test "full arbitration matches an independent all-pairs policy matrix before cutoff" do
    c = ContinuationFixtures.fixture()

    defs = [
      {"a", false, "shared"},
      {"b", true, "shared"},
      {"c", false, "other"},
      {"d", false, "other"}
    ]

    collection =
      DecisionFixtures.collection(c, DecisionFixtures.input(c, DecisionFixtures.members(c, defs)))

    decision = DecisionFixtures.decision(c, collection)

    choices =
      for constraint <- ~w(allowed refused unknown),
          override <- ~w(none selected suppressed),
          do: %{"constraint" => constraint, "override" => override}

    ids = Enum.map(collection.data["proposals"], & &1["step_original"])

    for seed <- 0..80, batch <- [1, 3] do
      dispositions =
        ids
        |> Enum.with_index()
        |> Map.new(fn {id, i} ->
          {id, Enum.at(choices, rem(div(seed, Integer.pow(3, rem(i, 3))) + i * seed, 9))}
        end)

      expected = DecisionReference.decide(collection.data, dispositions, batch)

      context = %{
        "input" => collection.data["input"],
        "dispositions" => dispositions,
        "batch_limit" => batch,
        "arbitration" => expected
      }

      assert :ok ==
               proof(fn ->
                 DecisionArbitration.verify(collection.data, context, c.profile, c.limits)
               end)

      if rem(seed, 9) == 0, do: assert({:ok, _} = check(c, decision, context))

      for key <- ~w(selected decisions) do
        wrong = put_in(context, ["arbitration", key], [nil])
        assert {:error, %Error{code: :stale_decision_arbitration}} = check(c, decision, wrong)
      end
    end
  end

  test "changed current policy and forged full arbitration refuse" do
    c = ContinuationFixtures.fixture()

    collection =
      DecisionFixtures.collection(
        c,
        DecisionFixtures.input(
          c,
          DecisionFixtures.members(c, [{"a", false, "one"}, {"b", true, "one"}, {"c", false, "two"}])
        )
      )

    decision = DecisionFixtures.decision(c, collection)
    context = DecisionFixtures.context(c, collection)
    assert {:ok, _} = check(c, decision, context)

    for wrong <- [
          %{context | "batch_limit" => 2},
          put_in(
            context,
            ["dispositions", hd(collection.data["proposals"])["step_original"], "constraint"],
            "refused"
          ),
          put_in(
            context,
            ["arbitration", "collection_digest"],
            "sha256:" <> String.duplicate("0", 64)
          ),
          put_in(context, ["arbitration", "selected"], [])
        ] do
      assert {:error, %Error{code: :stale_decision_arbitration}} = check(c, decision, wrong)
    end
  end

  test "all 1024 pending contributors and a final supplied conflict precede batching" do
    c = ContinuationFixtures.fixture()
    input = capacity_input(c)
    collection = DecisionFixtures.collection(c, input)
    assert length(collection.data["proposals"]) == 1024
    decision = DecisionFixtures.decision(c, collection)

    dispositions =
      Map.new(
        collection.data["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

    arbitration = DecisionReference.decide(collection.data, dispositions, 16)

    context = %{
      "input" => input,
      "dispositions" => dispositions,
      "batch_limit" => 16,
      "arbitration" => arbitration
    }

    assert {:ok, checked} = check(c, decision, context)
    assert length(checked["arbitration"]["selected"]) == 16
    assert Enum.count(arbitration["decisions"], &(&1["outcome"] == "conflict")) == 32
    assert Enum.count(arbitration["decisions"], &(&1["outcome"] == "batch-deferred")) == 46 * 16
    assert length(checked["proposal_states"]) == 1024

    {:ok, narrow} = Profile.new(%{c.profile.data | "pending_work" => 1023})
    limited = %{c | profile: narrow}
    over = DecisionFixtures.claimed(limited, capacity_input(limited))

    assert {:error, %Error{code: :pending_work_bound}} =
             proof(fn -> Decision.new(over, narrow, c.limits) end)
  end

  test "coherence, aggregate active runs and hidden nil continuation cannot be rehashed away" do
    c = ContinuationFixtures.fixture()

    input =
      DecisionFixtures.input(
        c,
        DecisionFixtures.members(c, [{"a", false, "shared"}, {"b", false, "shared"}])
      )

    for {path, value} <- [
          {["id"], "other"},
          {["resource_revisions", "resource:shared"], 2},
          {["binding_bases", "actuator", "source_epoch"], "other"}
        ] do
      wrong = put_in(input, ["entries", Access.at(0), "snapshot"] ++ path, value)
      claimed = DecisionFixtures.claimed(c, wrong)

      assert {:error, %Error{code: :incoherent_collection_snapshot}} =
               proof(fn -> Decision.new(claimed, c.profile, c.limits) end)
    end

    {:ok, narrow} = Profile.new(%{c.profile.data | "active_runs" => 1})
    limited = %{c | profile: narrow}

    over =
      DecisionFixtures.claimed(
        limited,
        DecisionFixtures.input(
          limited,
          DecisionFixtures.members(limited, [{"a", false, "a"}, {"b", false, "b"}])
        )
      )

    assert {:error, %Error{code: :active_run_bound}} =
             proof(fn -> Decision.new(over, narrow, c.limits) end)

    collection = DecisionFixtures.collection(c, input)
    next = put_in(DecisionFixtures.retained(collection), ["entries", Access.at(0), "event"], nil)
    wrong = %{collection.data | "input" => next}

    assert {:error, %Error{code: :incomplete_run_continuation}} =
             proof(fn -> Decision.verify_point(next, wrong, c.profile, c.limits) end)
  end

  test "every public decision argument envelope obeys exact and one-under byte bounds" do
    for operation <- [:point, :new, :map, :check] do
      exact =
        Enum.reduce_while(1..5, 1_000_000, fn _, candidate ->
          {c, collection, decision, context} = bounded_fixture(candidate, operation)
          envelope = bound_envelope(c, collection, decision, context, operation)
          output = if operation == :new, do: decision.data, else: nil
          maximum = max(json_size(envelope, c), if(output, do: json_size(output, c), else: 0))
          if maximum == candidate, do: {:halt, maximum}, else: {:cont, maximum}
        end)

      frame = bounded_fixture(exact, operation)
      result = invoke(frame, operation)
      assert result == :ok or match?({:ok, _}, result)

      assert {:error, %Error{code: :limit_or_json_error}} =
               invoke(bounded_fixture(exact - 1, operation, false), operation)
    end
  end

  defp capacity_input(c) do
    members =
      Enum.map(1..64, fn index ->
        value = index == 64
        domain = if value, do: "1", else: Integer.to_string(index)

        parallel = %{
          "id" => "all",
          "kind" => "parallel",
          "branches" =>
            Enum.map(0..3, fn group ->
              %{
                "id" => "group:#{group}",
                "kind" => "parallel",
                "branches" =>
                  Enum.map(0..3, &ContinuationFixtures.effect("effect:#{group}:#{&1}", value))
              }
            end)
        }

        [member] =
          DecisionFixtures.members(c, [{"member:#{index}", value, domain}], %{"steps" => parallel})

        member
      end)

    DecisionFixtures.input(c, members)
  end

  defp bounded_fixture(maximum, operation, measuring \\ true) do
    base = ContinuationFixtures.fixture()
    {:ok, limits} = Limits.new(%{base.limits.data | "max_bytes" => maximum})
    c = %{base | limits: limits}

    collection =
      DecisionFixtures.collection(
        c,
        DecisionFixtures.input(c, DecisionFixtures.members(c, [{"a", false, "a"}]))
      )

    needed = operation in [:map, :check] or (operation == :new and measuring)
    decision = if needed, do: DecisionFixtures.decision(c, collection)
    context = if operation == :check, do: DecisionFixtures.context(c, collection)
    {c, collection, decision, context}
  end

  defp bound_envelope(c, collection, decision, context, operation) do
    body =
      case operation do
        :point -> %{"input" => collection.data["input"], "collection" => collection.data}
        :new -> %{"collection" => collection.data}
        :map -> %{"decision" => decision.data}
        :check -> %{"decision" => decision.data, "context" => context}
      end

    Map.merge(body, %{"profile" => c.profile.data, "json_limits" => c.limits.data})
  end

  defp invoke({c, collection, decision, context}, operation) do
    proof(fn ->
      case operation do
        :point -> Decision.verify_point(collection.data["input"], collection, c.profile, c.limits)
        :new -> Decision.new(collection, c.profile, c.limits)
        :map -> Decision.to_map(decision, c.profile, c.limits)
        :check -> Decision.check(decision, context, c.profile, c.limits)
      end
    end)
  end

  defp json_size(value, c) do
    {:ok, bytes} = Wotex.JSON.encode(value, Validation.json_options(c.limits.data))
    byte_size(bytes)
  end

  defp time2(time),
    do: Map.merge(time, %{"format" => "wotex.routines.time@2", "utc_generation" => "utc:1"})

  defp check(c, decision, context),
    do: proof(fn -> Decision.check(decision, context, c.profile, c.limits) end)

  defp proof(fun), do: DecisionFixtures.proof(fun)

  defp rehash(map, key, c) do
    {:ok, digest} = Validation.hash(Map.delete(map, key), c.limits)
    Map.put(map, key, digest)
  end
end
