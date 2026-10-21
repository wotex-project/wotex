Code.require_file("../../support/decision_fixtures.exs", __DIR__)
Code.require_file("../../support/decision_reference.exs", __DIR__)
Code.require_file("../../support/decision_bound_reference.exs", __DIR__)

defmodule Wotex.Routines.DecisionBoundsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Collection, Decision, Error, Limits, Program, Transition}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F
  alias Wotex.Routines.Test.DecisionBoundReference, as: Size
  alias Wotex.Routines.Test.DecisionFixtures, as: D
  alias Wotex.Routines.Test.DecisionReference, as: Arbitration

  @operations [:transition, :point, :new, :map, :check]
  @metrics ~w(max_bytes max_depth max_nodes max_string_bytes max_collection_size)
  @clock_cells for grammar <- [1, 2], mode <- [:present, :absent, :ignored], do: {grammar, mode}

  for metric <- @metrics do
    @metric metric
    test "exact and one-under #{metric} selections cover all public verification envelopes" do
      for {grammar, mode} <- @clock_cells do
        original = fixture(@metric, grammar, mode)
        for operation <- @operations, do: boundary(original, operation, @metric)
      end
    end
  end

  test "aggregate nodes count repeated copies even when every argument fits separately" do
    original = fixture("max_nodes")

    for operation <- @operations do
      exact = exact(original, operation, "max_nodes")
      limit = exact.c.limits.data["max_nodes"] - 1
      over = select(original, "max_nodes", limit)
      input = envelope(over, operation)
      assert Size.measure(input)["max_nodes"] > limit

      for child <- Map.values(input) do
        assert Size.measure(child)["max_nodes"] <= limit
      end

      assert {:error, %Error{code: :limit_or_json_error}} = invoke(over, operation, :plain)
    end
  end

  test "certificate output bytes are bounded after an independently fitting input" do
    original = fixture("max_bytes")
    exact = exact(original, :new, "max_bytes")
    amount = exact.c.limits.data["max_bytes"]
    over = select(original, "max_bytes", amount - 1)
    assert Size.measure(envelope(over, :new))["max_bytes"] < amount
    assert Size.measure(over.decision)["max_bytes"] == amount
    assert_success(exact, :new, :native)
    assert {:error, %Error{code: :limit_or_json_error}} = invoke(over, :new, :native)
  end

  test "UTF-8 limits measure bytes while canonical byte counts include escaping" do
    frame = fixture("max_string_bytes")
    id = hd(frame.collection["input"]["entries"])["program"]["source"]["id"]
    assert byte_size(id) == 100
    assert String.length(id) == 80
    assert IO.iodata_length(Size.canonical(id)) == 162

    for operation <- @operations do
      exact = exact(frame, operation, "max_string_bytes")
      assert exact.c.limits.data["max_string_bytes"] == 100
      assert_success(exact, operation, :plain)

      assert {:error, %Error{code: :limit_or_json_error}} =
               invoke(select(frame, "max_string_bytes", 99), operation, :plain)
    end
  end

  defp boundary(original, operation, metric) do
    exact = exact(original, operation, metric)
    amount = requirement(exact, operation, metric)
    assert exact.c.limits.data[metric] == amount

    for form <- [:plain, :native] do
      assert_success(exact, operation, form)
      over = select(original, metric, amount - 1)
      assert requirement(over, operation, metric) > amount - 1

      assert {:error, %Error{code: :limit_or_json_error, path: ""} = error} =
               invoke(over, operation, form)

      assert Map.keys(error) |> Enum.sort() == [:__struct__, :code, :path]
    end
  end

  defp fixture(metric, grammar \\ 1, mode \\ :present) do
    c = F.fixture()
    c = if mode == :ignored, do: D.elapsed(c), else: c

    time =
      if mode == :absent, do: %{c.time | "utc_low_ms" => nil, "utc_high_ms" => nil}, else: c.time

    time =
      if grammar == 2,
        do:
          Map.merge(time, %{
            "format" => "wotex.routines.time@2",
            "utc_generation" => if(mode != :absent, do: "utc:1")
          }),
        else: time

    c = %{c | time: time}

    members =
      if metric == "max_collection_size" do
        D.members(c, Enum.map(1..19, &{"member:#{&1}", false, "domain:#{&1}"}))
      else
        id = if metric == "max_string_bytes", do: String.duplicate("é\"\\\n", 20), else: "member"
        [F.compile(c, %{"id" => id})]
      end

    collection = D.collection(c, D.input(c, members)).data
    decision = D.decision(c, %Collection{data: collection}).data
    frame(c, collection, decision)
  end

  # Rebind only explicit selected Limits, then refresh their enclosing hashes.
  # Source/IR, point transitions, time cells and proposal identities do not
  # change. Exact success independently checks that this remains correspondence;
  # no production constructor must accept an undersized value to prepare it.
  defp select(original, metric, amount) do
    {:ok, limits} = Limits.new(%{original.c.limits.data | metric => amount})
    c = %{original.c | limits: limits}

    collection =
      original.collection
      |> rebind(limits.data)
      |> Size.digest("collection_digest")

    decision =
      original.decision
      |> Map.put("collection", collection)
      |> Size.digest("decision_digest")

    frame(c, collection, decision)
  end

  defp rebind(data, limits) when is_map(data),
    do:
      Map.new(data, fn
        {"json_limits", _} -> {"json_limits", limits}
        {key, value} -> {key, rebind(value, limits)}
      end)

  defp rebind(data, limits) when is_list(data), do: Enum.map(data, &rebind(&1, limits))
  defp rebind(data, _), do: data

  defp frame(c, collection, decision) do
    dispositions =
      Map.new(
        collection["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

    context = %{
      "input" => collection["input"],
      "dispositions" => dispositions,
      "batch_limit" => 1,
      "arbitration" => Arbitration.decide(collection, dispositions, 1)
    }

    %{c: c, collection: collection, decision: decision, context: context}
  end

  defp exact(original, operation, metric) do
    result =
      Enum.reduce_while(1..8, original.c.limits.data[metric], fn _, selected ->
        frame = select(original, metric, selected)
        required = requirement(frame, operation, metric)
        if selected == required, do: {:halt, {:exact, frame}}, else: {:cont, required}
      end)

    case result do
      {:exact, frame} -> frame
      _ -> flunk("independent size selection did not converge")
    end
  end

  defp requirement(frame, operation, metric) do
    [envelope(frame, operation) | outputs(frame, operation)]
    |> Enum.map(&Size.measure(&1)[metric])
    |> Enum.max()
  end

  defp envelope(frame, :transition) do
    {entry, result} = transition(frame)

    selected(frame, %{
      "program" => entry["program"],
      "event" => entry["event"],
      "snapshot" => entry["snapshot"],
      "time" => frame.collection["input"]["time"],
      "prior" => entry["prior"],
      "claimed_result" => result
    })
  end

  defp envelope(frame, :point),
    do: selected(frame, %{"input" => frame.collection["input"], "collection" => frame.collection})

  defp envelope(frame, :new), do: selected(frame, %{"collection" => frame.collection})
  defp envelope(frame, :map), do: selected(frame, %{"decision" => frame.decision})

  defp envelope(frame, :check),
    do: selected(frame, %{"decision" => frame.decision, "context" => frame.context})

  defp selected(frame, values),
    do:
      Map.merge(values, %{"profile" => frame.c.profile.data, "json_limits" => frame.c.limits.data})

  defp outputs(frame, operation) when operation in [:new, :map], do: [frame.decision]
  defp outputs(frame, :check), do: [checked(frame)]
  defp outputs(_, _), do: []

  defp checked(frame) do
    %{
      "format" => "wotex.routines.checked-decision@1",
      "scope" => "provided_membership_time_cell_only",
      "decision_digest" => frame.decision["decision_digest"],
      "collection_digest" => frame.collection["collection_digest"],
      "point_time" => frame.collection["input"]["time"],
      "checked_time" => frame.context["input"]["time"],
      "transitions" => frame.collection["transitions"],
      "proposal_states" => frame.collection["proposal_states"],
      "arbitration" => frame.context["arbitration"]
    }
  end

  defp transition(frame) do
    entry = hd(frame.collection["input"]["entries"])

    claim =
      Enum.find(
        frame.collection["transitions"],
        &(&1["program_digest"] == entry["program"]["ir_digest"])
      )

    {entry, claim["result"]}
  end

  defp invoke(frame, operation, form) do
    c = frame.c
    collection = if form == :native, do: %Collection{data: frame.collection}, else: frame.collection
    decision = if form == :native, do: %Decision{data: frame.decision}, else: frame.decision

    D.proof(fn ->
      case operation do
        :transition ->
          {entry, result} = transition(frame)
          program = if form == :native, do: %Program{data: entry["program"]}, else: entry["program"]

          Transition.verify(
            program,
            entry["event"],
            entry["snapshot"],
            frame.collection["input"]["time"],
            entry["prior"],
            result,
            c.profile,
            c.limits
          )

        :point ->
          Decision.verify_point(frame.collection["input"], collection, c.profile, c.limits)

        :new ->
          Decision.new(collection, c.profile, c.limits)

        :map ->
          Decision.to_map(decision, c.profile, c.limits)

        :check ->
          Decision.check(decision, frame.context, c.profile, c.limits)
      end
    end)
  end

  defp assert_success(frame, operation, form) do
    case {operation, invoke(frame, operation, form)} do
      {operation, :ok} when operation in [:point, :transition] -> :ok
      {:new, {:ok, %Decision{data: data}}} -> assert data === frame.decision
      {:map, {:ok, data}} -> assert data === frame.decision
      {:check, {:ok, data}} -> assert data === checked(frame)
      {_, other} -> flunk("exact public bound refused: #{inspect(other)}")
    end
  end
end
