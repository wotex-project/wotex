Code.require_file("../../support/continuation_fixtures.exs", __DIR__)

defmodule Wotex.Routines.TransitionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Edge, Error, Event, Limits, Run, Snapshot, Time, Transition, Validation}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  test "all structural instruction forms verify under both time grammars" do
    effect = F.effect("effect")

    forms =
      [
        %{"id" => "noop", "kind" => "noop"},
        effect,
        %{"id" => "delay", "kind" => "delay", "duration_ms" => 5},
        %{"id" => "wait", "kind" => "wait", "condition" => literal(false), "timeout_ms" => 7},
        %{
          "id" => "sequence",
          "kind" => "sequence",
          "steps" => [%{"id" => "noop", "kind" => "noop"}, effect]
        },
        %{"id" => "parallel", "kind" => "parallel", "branches" => [effect, F.effect("other", true)]}
      ] ++
        Enum.map([true, false, "unknown"], fn truth ->
          %{
            "id" => "conditional",
            "kind" => "if",
            "condition" => literal(truth),
            "then" => effect,
            "else" => %{"id" => "noop", "kind" => "noop"}
          }
        end)

    for steps <- forms, grammar <- [1, 2] do
      c = F.fixture() |> F.compile(%{"steps" => steps})
      c = if grammar == 2, do: %{c | time: time2(c.time)}, else: c
      assert :ok == verify(frame(c))
    end
  end

  test "latched delay continuation, cancellation, loss and removed membership verify" do
    c = F.fixture() |> F.compile(%{"steps" => F.delayed_effect()})
    first = frame(c)
    assert :ok == verify(first)
    run = first.result["run"]

    for time <- [
          %{c.time | "elapsed_ms" => 119},
          %{c.time | "elapsed_ms" => 120},
          %{c.time | "elapsed_ms" => 1020},
          %{c.time | "elapsed_ms" => 19},
          %{c.time | "epoch" => "boot:other"},
          %{c.time | "clock_generation" => "elapsed:other"}
        ] do
      next = frame(%{F.resume(c) | time: time}, run)
      assert :ok == verify(next)
    end

    cancelled = frame(%{c | event: %{c.event | "kind" => "cancel"}}, run)
    assert :ok == verify(cancelled)
    assert :ok == verify(frame(F.resume(c), cancelled.result["run"]))

    assert :ok ==
             verify(frame(%{F.resume(c) | snapshot: %{c.snapshot | "active_programs" => []}}, run))
  end

  test "every ordered receipt stage verifies full history and newly reached effects" do
    c =
      F.fixture()
      |> F.compile(%{
        "steps" => %{
          "id" => "sequence",
          "kind" => "sequence",
          "steps" => [F.effect("one"), F.effect("two")]
        }
      })

    initial = frame(c)
    run = initial.result["run"]
    contract = hd(c.context["bases"])["evidence"]["report_contract"]

    events =
      [
        receipt(c, "admission", %{"ref" => "charge", "outcome" => "held"}),
        receipt(c, "handoff", %{"ref" => "handoff"})
      ] ++
        Enum.map(~w(local_queue protocol_response correlated_report reported_match), fn stage ->
          contract = if stage in ~w(correlated_report reported_match), do: contract, else: nil

          receipt(c, "result", %{
            "ref" => "result:" <> stage,
            "stage" => stage,
            "outcome" => "accepted",
            "report_contract" => contract
          })
        end)

    final =
      Enum.reduce(events, run, fn event, run ->
        f = frame(%{c | event: event}, run)
        assert :ok == verify(f)
        duplicate = frame(%{c | event: event}, f.result["run"])
        assert :ok == verify(duplicate)
        f.result["run"]
      end)

    assert Enum.at(final["steps"], 2)["status"] == "proposed"
  end

  test "direct refusal and cancellation of an already terminal original remain exact" do
    c = F.fixture() |> F.compile()
    first = frame(c)
    refused = receipt(c, "admission", %{"path" => [], "ref" => "refused", "outcome" => "refused"})
    next = frame(%{c | event: refused}, first.result["run"])
    assert next.result["outcome"] == "refused"
    assert :ok == verify(next)
    cancel = frame(%{c | event: %{c.event | "kind" => "cancel"}}, next.result["run"])
    assert cancel.result["outcome"] == "cancelled"
    assert :ok == verify(cancel)
  end

  test "native values are normalized while forged native members and non-JSON claims refuse" do
    c = F.fixture() |> F.compile()
    f = frame(c)
    {:ok, event} = Event.new(c.event, c.limits)
    {:ok, snapshot} = Snapshot.new(c.snapshot, c.program, c.profile, c.limits)
    {:ok, time} = Time.new(c.time, c.limits)
    args = [c.program, event, snapshot, time, f.prior, f.result, c.profile, c.limits]
    assert :ok == apply(Transition, :verify, args)

    for index <- [0, 1, 2, 3, 6, 7] do
      bad = Map.put(Enum.at(args, index), :extra, true)
      assert {:error, %Error{}} = apply(Transition, :verify, List.replace_at(args, index, bad))
    end

    for proposals <- [[[] | :improper], [self()]] do
      assert {:error, %Error{}} = verify(%{f | result: %{f.result | "proposals" => proposals}})
    end
  end

  test "late held admission, failure and partial uncertainty preserve their exact point relation" do
    c = F.fixture() |> F.compile(%{"run_ms" => 20_000})
    first = frame(c)
    admission = receipt(c, "admission", %{"path" => [], "ref" => "charge", "outcome" => "held"})

    late =
      frame(%{c | event: admission, time: %{c.time | "elapsed_ms" => 15_020}}, first.result["run"])

    assert late.result["outcome"] == "expired"
    assert :ok == verify(late)

    held = frame(%{c | event: admission}, first.result["run"])
    handoff = receipt(c, "handoff", %{"path" => [], "ref" => "handoff"})
    sent = frame(%{c | event: handoff}, held.result["run"])

    for outcome <- ~w(failed unknown) do
      event =
        receipt(c, "result", %{
          "path" => [],
          "ref" => "result",
          "stage" => "protocol_response",
          "outcome" => outcome,
          "report_contract" => nil
        })

      result = frame(%{c | event: event}, sent.result["run"])
      assert :ok == verify(result)
    end
  end

  test "a failed parallel wait stops unsent work and preserves its original motion fields" do
    steps = %{
      "id" => "all",
      "kind" => "parallel",
      "branches" => [
        F.effect("effect"),
        %{"id" => "wait", "kind" => "wait", "condition" => literal(false), "timeout_ms" => 7}
      ]
    }

    c = F.fixture() |> F.compile(%{"steps" => steps})
    first = frame(c)
    next = frame(%{F.resume(c) | time: %{c.time | "elapsed_ms" => 27}}, first.result["run"])
    assert next.result["run"]["reason"] == "wait_timeout"
    assert :ok == verify(first)
    assert :ok == verify(next)
  end

  test "busy rejection has no run and cannot hide an original's required history" do
    c = F.fixture() |> F.compile()
    first = frame(c)
    other = %{c | event: %{c.event | "original" => "different"}}
    skipped = frame(other, nil, nil, first.result["run"])
    assert skipped.result["outcome"] == "skipped-busy"
    assert :ok == verify(skipped)

    assert {:error, %Error{code: :missing_original}} =
             Transition.verify(
               c.program,
               c.event,
               c.snapshot,
               c.time,
               skipped.prior,
               skipped.result,
               c.profile,
               c.limits
             )
  end

  test "a valid edge shape cannot forge its first baseline or current qualification" do
    trigger = %{
      "kind" => "edge",
      "binding" => "sensor",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 20,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    c = F.fixture(sensor: true) |> F.compile(%{"trigger" => trigger})
    first = frame(F.sample(c, 1, 20, 1000))
    assert first.result["outcome"] == "no-edge"
    assert :ok == verify(first)
    wrong = put_in(first.result, ["edge", "baseline"], true)
    assert {:ok, _} = Edge.new(wrong["edge"], c.program, c.profile, c.limits)
    assert {:error, %Error{code: :invalid_transition}} = verify(%{first | result: wrong})

    high = F.sample(c, 2, 30, 3000)
    assert :ok == verify(frame(high, nil, first.result["edge"]))
    stale = %{high | snapshot: put_in(high.snapshot, ["facts", "sensor", "quality"], "stale")}
    assert :ok == verify(frame(stale, nil, first.result["edge"]))
  end

  test "every scalar result leaf and missing complete result member refuses" do
    c = F.fixture() |> F.compile()
    initial = frame(c)

    held =
      frame(
        %{
          c
          | event: receipt(c, "admission", %{"path" => [], "ref" => "charge", "outcome" => "held"})
        },
        initial.result["run"]
      )

    for f <- [initial, held] do
      for path <- leaves(f.result) do
        bad = update(f.result, path, &mutate/1)
        checked = verify(%{f | result: bad})
        assert match?({:error, %Error{}}, checked), inspect(path)
      end

      for key <- Map.keys(f.result) do
        assert {:error, %Error{}} = verify(%{f | result: Map.delete(f.result, key)})
      end
    end
  end

  test "a rehashed receipt and a plausible altered motion field are not correspondence" do
    c = F.fixture() |> F.compile()
    first = frame(c)
    event = receipt(c, "admission", %{"path" => [], "ref" => "charge", "outcome" => "held"})
    held = frame(%{c | event: event}, first.result["run"])
    {:ok, hash} = Validation.hash(%{event | "ref" => "forged"}, c.limits)

    wrong =
      put_in(held.result, ["run", "steps", Access.at(0), "receipts", "admission"], %{
        "ref" => "forged",
        "digest" => hash,
        "outcome" => "held"
      })

    wrong = put_in(wrong, ["run", "spent", Access.at(0), "ref"], "forged")
    assert {:ok, _} = Run.new(wrong["run"], c.program, c.profile, c.limits)
    assert {:error, %Error{code: :invalid_transition}} = verify(%{held | result: wrong})

    wrong = put_in(first.result, ["run", "steps", Access.at(0), "deadline_ms"], 1000)
    assert {:error, %Error{}} = verify(%{first | result: wrong})

    assert {:error, %Error{code: :invalid_transition}} =
             verify(%{first | result: %{first.result | "proposals" => []}})

    resumed = frame(%{F.resume(c) | time: %{c.time | "elapsed_ms" => 100}}, first.result["run"])
    wrong = put_in(resumed.result, ["run", "steps", Access.at(0), "started_ms"], 21)
    assert {:ok, _} = Run.new(wrong["run"], c.program, c.profile, c.limits)
    assert {:error, %Error{code: :invalid_transition}} = verify(%{resumed | result: wrong})
  end

  test "combined JSON byte bounds count all argument and retained-result copies" do
    base = F.fixture()
    candidate = 9_000
    selected = %{base.limits.data | "max_bytes" => candidate}
    {:ok, seed} = Limits.new(selected)
    c = F.compile(%{base | limits: seed})
    f = frame(c)

    envelope = %{
      "program" => c.program.data,
      "event" => c.event,
      "snapshot" => c.snapshot,
      "time" => c.time,
      "prior" => f.prior,
      "claimed_result" => f.result,
      "profile" => c.profile.data,
      "json_limits" => selected
    }

    {:ok, bytes} = Wotex.JSON.encode(envelope, Validation.json_options(c.limits.data))
    maximum = byte_size(bytes)
    assert byte_size(Integer.to_string(maximum)) == byte_size(Integer.to_string(candidate))
    {:ok, exact} = Limits.new(%{selected | "max_bytes" => maximum})
    {:ok, under} = Limits.new(%{selected | "max_bytes" => maximum - 1})
    assert :ok == verify(frame(F.compile(%{base | limits: exact})))

    assert {:error, %Error{code: :limit_or_json_error}} =
             verify(frame(F.compile(%{base | limits: under})))
  end

  defp frame(c, before \\ nil, edge \\ nil, busy \\ nil) do
    prior = %{"original" => before, "busy" => busy, "edge" => edge}
    {:ok, result} = F.advance(c, before, edge, busy)
    %{c: c, prior: prior, result: result}
  end

  defp verify(%{c: c} = f) do
    previous = Process.put(:routines_transition_verifying, true)

    try do
      Transition.verify(
        c.program,
        c.event,
        c.snapshot,
        c.time,
        f.prior,
        f.result,
        c.profile,
        c.limits
      )
    after
      if previous == nil,
        do: Process.delete(:routines_transition_verifying),
        else: Process.put(:routines_transition_verifying, previous)
    end
  end

  defp receipt(c, kind, fields),
    do: Map.merge(c.event, Map.merge(%{"kind" => kind, "path" => [0]}, fields))

  defp literal(value), do: %{"op" => "literal", "value" => value}

  defp time2(time),
    do: Map.merge(time, %{"format" => "wotex.routines.time@2", "utc_generation" => "utc:1"})

  defp leaves(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> Enum.map(leaves(value), &[key | &1]) end)

  defp leaves(list) when is_list(list),
    do:
      list
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, i} -> Enum.map(leaves(value), &[i | &1]) end)

  defp leaves(_), do: [[]]
  defp update(value, [], fun), do: fun.(value)

  defp update(map, [key | rest], fun) when is_map(map),
    do: Map.update!(map, key, &update(&1, rest, fun))

  defp update(list, [i | rest], fun), do: List.update_at(list, i, &update(&1, rest, fun))
  defp mutate(value) when is_integer(value), do: value + 1
  defp mutate(value) when is_binary(value), do: value <> ":forged"
  defp mutate(value) when is_boolean(value), do: not value
  defp mutate(nil), do: "forged"
end
