Code.require_file("decision_inputs.exs", __DIR__)
Code.require_file("decision_journal_oracle.exs", __DIR__)

defmodule DecisionJournalBoundsConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias DecisionArchiveInputs, as: Input
  alias DecisionConsumerJournal, as: Oracle
  alias Wotex.Routines.{Collection, Decision, Error, Limits, Program, Transition}

  @operations [:transition, :point, :new, :map, :check]
  @metrics ~w(max_bytes max_depth max_nodes max_string_bytes max_collection_size)

  for metric <- @metrics, grammar <- [1, 2], mode <- [:present, :absent, :ignored] do
    @tag limits_metric: metric, time_grammar: grammar, clock_mode: mode
    test "journal bounds #{metric} / Time@#{grammar} / #{mode}", context do
      assert measure(%{})["max_depth"] == 1
      assert measure(%{"empty" => []})["max_depth"] == 2
      metric = context.limits_metric
      original = fixture(metric, context.time_grammar, context.clock_mode)

      for operation <- @operations do
        exact = exact(original, operation, metric)
        amount = needed(exact, operation, metric)
        assert exact.c.limits.data[metric] == amount
        short = select(original, metric, amount - 1)
        assert needed(short, operation, metric) > amount - 1

        for form <- [:native, :plain] do
          success(exact, operation, form)

          assert {:error, %Error{code: :limit_or_json_error, path: ""} = error} =
                   invoke(short, operation, form)

          assert Enum.sort(Map.keys(error)) == [:__struct__, :code, :path]
        end
      end
    end
  end

  test "journal counts repeated copies across the whole argument envelope" do
    original = fixture("max_nodes")

    for operation <- @operations do
      exact = exact(original, operation, "max_nodes")
      limit = exact.c.limits.data["max_nodes"] - 1
      short = select(original, "max_nodes", limit)
      all = envelope(short, operation)
      assert measure(all)["max_nodes"] > limit

      for child <- Map.values(all), do: assert(measure(child)["max_nodes"] <= limit)

      assert {:error, %Error{code: :limit_or_json_error}} =
               invoke(short, operation, :plain)
    end
  end

  test "journal checks the complete certificate output after fitting its input" do
    original = fixture("max_bytes")
    exact = exact(original, :new, "max_bytes")
    amount = exact.c.limits.data["max_bytes"]
    short = select(original, "max_bytes", amount - 1)
    assert measure(envelope(short, :new))["max_bytes"] < amount
    assert measure(short.decision)["max_bytes"] == amount
    success(exact, :new, :native)
    assert {:error, %Error{code: :limit_or_json_error}} = invoke(short, :new, :native)
  end

  test "journal distinguishes Unicode bytes, characters and escaped representation" do
    original = fixture("max_string_bytes")
    id = hd(original.collection["input"]["entries"])["program"]["source"]["id"]
    assert String.length(id) == 80
    assert byte_size(id) == 100
    assert byte_size(JSON.encode!(id)) == 162

    for operation <- @operations do
      exact = exact(original, operation, "max_string_bytes")
      assert exact.c.limits.data["max_string_bytes"] == 100
      success(exact, operation, :plain)

      assert {:error, %Error{code: :limit_or_json_error}} =
               invoke(select(original, "max_string_bytes", 99), operation, :plain)
    end
  end

  defp fixture(metric, grammar \\ 1, mode \\ :present) do
    base = Input.base()
    time = if grammar == 1, do: Map.drop(base.time, ~w(format utc_generation)), else: base.time

    time =
      if mode == :absent,
        do: Map.merge(time, %{"utc_low_ms" => nil, "utc_high_ms" => nil}),
        else: time

    time = if grammar == 2 and mode == :absent, do: %{time | "utc_generation" => nil}, else: time
    base = %{base | time: time}
    count = if metric == "max_collection_size", do: 19, else: 1

    members =
      Enum.map(1..count, fn index ->
        id =
          if metric == "max_string_bytes",
            do: String.duplicate("é\"\\\n", 20),
            else: "journal:limits:#{index}"

        member =
          Input.compile(base, id,
            sensor: true,
            source_time: mode != :ignored,
            target: "bound:#{index}"
          )

        sampled = Input.sample(member, 1, 3000, 20)
        event = %{member.event | "original" => "bounds:original:#{index}"}
        %{sampled | event: event}
      end)

    collection = Input.collection(base, Input.input(base, members)).data

    for {member, transition} <-
          Enum.zip(Enum.sort_by(members, & &1.program.data["ir_digest"]), collection["transitions"]) do
      member = %{
        member
        | snapshot:
            hd(
              Enum.filter(
                collection["input"]["entries"],
                &(&1["program"]["ir_digest"] == member.program.data["ir_digest"])
              )
            )["snapshot"]
      }

      claim = transition["result"]

      plan = %{
        status: "running",
        rows: [{[], "effect", "proposed", 20, 1020, nil}],
        new: [{[], false}]
      }

      expected = Oracle.point(member, Input.prior(), plan)
      assert claim === expected
    end

    decision = Input.decision(base, %Collection{data: collection}).data
    frame(base, collection, decision)
  end

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
      "arbitration" =>
        Oracle.arbitrate(collection["proposals"], dispositions, 1, collection["collection_digest"])
    }

    %{c: c, collection: collection, decision: decision, context: context}
  end

  defp select(original, metric, amount) do
    {:ok, limits} = Limits.new(%{original.c.limits.data | metric => amount})

    collection =
      original.collection
      |> rebind(limits.data)
      |> Input.rehash("collection_digest")

    decision =
      original.decision
      |> rebind(limits.data)
      |> Map.put("collection", collection)
      |> Input.rehash("decision_digest")

    frame(%{original.c | limits: limits}, collection, decision)
  end

  defp rebind(value, limits) when is_map(value) do
    Map.new(value, fn
      {"json_limits", _} -> {"json_limits", limits}
      {key, child} -> {key, rebind(child, limits)}
    end)
  end

  defp rebind(value, limits) when is_list(value), do: Enum.map(value, &rebind(&1, limits))
  defp rebind(value, _), do: value

  defp exact(original, operation, metric) do
    result =
      Enum.reduce_while(1..8, original.c.limits.data[metric], fn _, amount ->
        selected = select(original, metric, amount)
        required = needed(selected, operation, metric)
        if amount == required, do: {:halt, {:exact, selected}}, else: {:cont, required}
      end)

    case result do
      {:exact, selected} -> selected
      _ -> flunk("independent exact bound did not converge")
    end
  end

  defp needed(frame, operation, metric) do
    [envelope(frame, operation) | outputs(frame, operation)]
    |> Enum.map(&measure(&1)[metric])
    |> Enum.max()
  end

  defp envelope(frame, operation) do
    body =
      case operation do
        :transition ->
          {entry, result} = transition(frame)

          %{
            "program" => entry["program"],
            "event" => entry["event"],
            "snapshot" => entry["snapshot"],
            "time" => frame.collection["input"]["time"],
            "prior" => entry["prior"],
            "claimed_result" => result
          }

        :point ->
          %{"input" => frame.collection["input"], "collection" => frame.collection}

        :new ->
          %{"collection" => frame.collection}

        :map ->
          %{"decision" => frame.decision}

        :check ->
          %{"decision" => frame.decision, "context" => frame.context}
      end

    Map.merge(body, %{"profile" => frame.c.profile.data, "json_limits" => frame.c.limits.data})
  end

  defp outputs(frame, operation) when operation in [:new, :map], do: [frame.decision]
  defp outputs(frame, :check), do: [checked(frame)]
  defp outputs(_, _), do: []

  defp checked(frame) do
    frame.collection
    |> Map.take(~w(transitions proposal_states))
    |> Map.merge(%{
      "format" => "wotex.routines.checked-decision@1",
      "scope" => "provided_membership_time_cell_only",
      "decision_digest" => frame.decision["decision_digest"],
      "collection_digest" => frame.collection["collection_digest"],
      "point_time" => frame.collection["input"]["time"],
      "checked_time" => frame.context["input"]["time"],
      "arbitration" => frame.context["arbitration"]
    })
  end

  defp transition(frame) do
    entry = hd(frame.collection["input"]["entries"])

    claimed =
      Enum.find(
        frame.collection["transitions"],
        &(&1["program_digest"] == entry["program"]["ir_digest"])
      )

    {entry, claimed["result"]}
  end

  defp invoke(frame, operation, form) do
    collection = if form == :native, do: %Collection{data: frame.collection}, else: frame.collection
    decision = if form == :native, do: %Decision{data: frame.decision}, else: frame.decision
    c = frame.c

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
  end

  defp success(frame, operation, form) do
    case {operation, invoke(frame, operation, form)} do
      {name, :ok} when name in [:transition, :point] -> :ok
      {:new, {:ok, %Decision{data: value}}} -> assert value === frame.decision
      {:map, {:ok, value}} -> assert value === frame.decision
      {:check, {:ok, value}} -> assert value === checked(frame)
      {_, other} -> flunk("exact bound refused: #{inspect(other)}")
    end
  end

  # Bottom-up journal accounting composes heights and encoded scalar lengths.
  defp measure(value) do
    {entries, keys, encoded} =
      cond do
        is_map(value) ->
          pairs = Enum.map(value, fn {key, child} -> {key, measure(child)} end)

          bytes =
            Enum.reduce(pairs, 2 + max(map_size(value) - 1, 0), fn {key, child}, size ->
              size + byte_size(JSON.encode!(key)) + 1 + child["max_bytes"]
            end)

          {Enum.map(pairs, &elem(&1, 1)), Map.keys(value), bytes}

        is_list(value) ->
          parts = Enum.map(value, &measure/1)
          bytes = 2 + max(length(parts) - 1, 0) + Enum.sum(Enum.map(parts, & &1["max_bytes"]))
          {parts, [], bytes}

        true ->
          {[], [], byte_size(JSON.encode!(value))}
      end

    own_strings = if is_binary(value), do: [value | keys], else: keys
    string_width = Enum.reduce(own_strings, 0, fn text, width -> max(width, byte_size(text)) end)
    container = is_map(value) or is_list(value)
    width = if is_map(value), do: map_size(value), else: length(entries)
    max_child = fn key -> Enum.reduce(entries, 0, fn child, bound -> max(bound, child[key]) end) end

    %{
      "max_bytes" => encoded,
      "max_nodes" => 1 + Enum.sum(Enum.map(entries, & &1["max_nodes"])),
      "max_depth" => if(container, do: 1 + max_child.("max_depth"), else: 0),
      "max_collection_size" => max(width, max_child.("max_collection_size")),
      "max_string_bytes" => max(string_width, max_child.("max_string_bytes"))
    }
  end
end
