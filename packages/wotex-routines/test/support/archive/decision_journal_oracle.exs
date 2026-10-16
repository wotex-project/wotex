defmodule DecisionConsumerJournal do
  @moduledoc false

  # Explicit host-owned trace tables, not a source interpreter. Every expected
  # row, eligibility decision and receipt comes from the consumer's script.
  @slots ~w(admission handoff local_queue protocol_response correlated_report reported_match terminal)

  @spec open(map()) :: map()
  def open(input), do: %{revision: 0, input: input, captures: [], references: [], charges: []}

  @spec capture(map()) :: {map(), map()}
  def capture(owner) do
    token = %{revision: owner.revision, input: owner.input}
    {%{owner | captures: [token | owner.captures]}, token}
  end

  @spec tick(map(), map()) :: map()
  def tick(owner, time) do
    old = owner.input["time"]
    input = %{owner.input | "time" => time}
    identity = ~w(format epoch clock_generation)

    if Map.take(old, identity) === Map.take(time, identity) and
         time["elapsed_ms"] >= old["elapsed_ms"],
       do: %{owner | input: input},
       else: replace(owner, input)
  end

  @spec replace(map(), map()) :: map()
  def replace(owner, input), do: %{owner | revision: owner.revision + 1, input: input}

  @spec commit_inert(map(), map(), map(), map()) :: {:ok, map()} | {:error, atom()}
  def commit_inert(owner, token, claimed, expected) do
    charges = charges(expected)
    actual = charges(claimed)

    cond do
      token not in owner.captures or owner.revision != token.revision or
          Map.delete(owner.input, "time") !== Map.delete(token.input, "time") ->
        {:error, :stale}

      expected["input"] !== token.input ->
        {:error, :wrong_relation}

      not known_history?(owner, token.input) ->
        {:error, :stale_history}

      Enum.any?(owner.charges, &(&1 not in actual)) ->
        {:error, :lost_charge}

      claimed !== expected ->
        {:error, :wrong_relation}

      true ->
        {:ok,
         %{
           owner
           | revision: owner.revision + 1,
             captures: [],
             references: expected["transitions"],
             charges: Enum.uniq(owner.charges ++ charges)
         }}
    end
  end

  defp charges(collection) do
    Enum.flat_map(collection["transitions"], fn row ->
      case row["result"] do
        %{"run" => run} when is_map(run) -> run["spent"]
        _ -> []
      end
    end)
  end

  defp known_history?(owner, input) do
    known = Map.new(owner.references, &{&1["program_digest"], &1["result"]})

    Enum.all?(input["entries"], fn entry ->
      case known[entry["program"]["ir_digest"]] do
        %{"run" => run, "edge" => edge} when is_map(run) ->
          entry["prior"] === %{"original" => run, "busy" => nil, "edge" => edge}

        _ ->
          entry["prior"]["original"] == nil
      end
    end)
  end

  @spec dump(map()) :: String.t()
  def dump(owner) do
    JSON.encode!(%{
      "revision" => owner.revision,
      "input" => owner.input,
      "references" => owner.references,
      "charges" => owner.charges
    })
  end

  @spec restore(String.t()) :: map()
  def restore(bytes) do
    data = JSON.decode!(bytes)

    %{
      revision: data["revision"],
      input: data["input"],
      captures: [],
      references: data["references"],
      charges: data["charges"]
    }
  end

  @spec retained(map()) :: map()
  def retained(owner) do
    by_program = Map.new(owner.references, &{&1["program_digest"], &1["result"]})

    update_in(owner.input, ["entries"], fn entries ->
      Enum.map(entries, fn entry ->
        previous = by_program[entry["program"]["ir_digest"]]
        run = previous["run"]

        event = %{
          "kind" => "resume",
          "program_digest" => run["program_digest"],
          "original" => run["original"]
        }

        %{
          entry
          | "event" => event,
            "prior" => %{"original" => run, "busy" => nil, "edge" => previous["edge"]}
        }
      end)
    end)
  end

  @spec point(map(), map(), map()) :: map()
  def point(c, prior, plan) do
    before = prior["original"]
    start = Map.get(plan, :start, if(before, do: before["start_ms"], else: c.time["elapsed_ms"]))

    format =
      Map.get(
        plan,
        :format,
        if(c.time["format"] == "wotex.routines.time@2",
          do: "wotex.routines.run@2",
          else: "wotex.routines.run@1"
        )
      )

    slots = if format == "wotex.routines.run@2", do: ["satisfied" | @slots], else: @slots
    history = Map.get(plan, :receipts, %{})

    steps =
      Enum.map(plan.rows, fn {path, kind, status, started, deadline, branch} ->
        %{
          "path" => path,
          "kind" => kind,
          "original" => original(c, path),
          "status" => status,
          "started_ms" => started,
          "deadline_ms" => deadline,
          "branch" => branch,
          "receipts" => Map.merge(Map.new(slots, &{&1, nil}), Map.get(history, path, %{}))
        }
      end)

    spent =
      Enum.flat_map(steps, fn record ->
        case record["receipts"]["admission"] do
          %{"outcome" => "held", "ref" => ref} ->
            [%{"original" => record["original"], "ref" => ref}]

          _ ->
            []
        end
      end)

    run = %{
      "format" => format,
      "original" => c.event["original"],
      "program_digest" => c.program.data["ir_digest"],
      "source_digest" => c.program.data["source_digest"],
      "compiler_basis" => c.context["compiler_basis"],
      "epoch" => c.time["epoch"],
      "clock_generation" => c.time["clock_generation"],
      "start_ms" => start,
      "last_ms" => Map.get(plan, :last, c.time["elapsed_ms"]),
      "deadline_ms" => Map.get(plan, :deadline, start + c.source["run_ms"]),
      "window" => Map.get(plan, :window),
      "status" => plan.status,
      "reason" => Map.get(plan, :reason),
      "steps" => steps,
      "spent" => spent
    }

    run =
      if format == "wotex.routines.run@2",
        do: Map.put(run, "time_format", Map.get(c.time, "format", "wotex.routines.time@1")),
        else: run

    proposals = Enum.map(Map.get(plan, :new, []), fn {path, input} -> proposal(c, path, input) end)

    %{
      "run" => run,
      "proposals" => proposals,
      "outcome" => plan.status,
      "edge" => Map.get(plan, :edge, prior["edge"]),
      "basis" => basis(c, prior)
    }
  end

  @spec basis(map(), map()) :: map()
  def basis(c, prior),
    do: %{
      "program_digest" => c.program.data["ir_digest"],
      "source_digest" => c.program.data["source_digest"],
      "compiler_basis" => c.context["compiler_basis"],
      "event" => c.event,
      "prior" => prior,
      "snapshot" => c.snapshot,
      "time" => c.time
    }

  @spec proposal(map(), list(), boolean()) :: map()
  def proposal(c, path, input) do
    binding = c.context["bindings"]["output"]
    basis = Enum.find(c.context["bases"], &(&1["id"] == binding["basis"]["id"]))

    %{
      "original" => c.event["original"],
      "step_original" => original(c, path),
      "program_digest" => c.program.data["ir_digest"],
      "path" => path,
      "binding" => "output",
      "input" => input,
      "installed_basis" => binding["basis"],
      "thing_id" => binding["thing_id"],
      "resource_roles" => binding["resource_roles"],
      "resource_domains" =>
        Enum.sort(Enum.uniq([binding["thing_id"] | Map.values(binding["resource_roles"])])),
      "operation" => basis["affordance"]["operation"],
      "completion" => "reported_match",
      "evidence_contract" => basis["evidence"]["report_contract"]
    }
  end

  @spec original(map(), list()) :: String.t()
  def original(c, path),
    do:
      hash(%{
        "original" => c.event["original"],
        "path" => path,
        "program_digest" => c.program.data["ir_digest"]
      })

  @spec receipt(map()) :: map()
  def receipt(event) do
    value =
      case event["kind"] do
        "handoff" -> "marked"
        "satisfied" -> "matched"
        _ -> event["outcome"]
      end

    %{"digest" => hash(event), "ref" => event["ref"], "outcome" => value}
  end

  @spec edge(map(), map()) :: map()
  def edge(c, memory) do
    value = %{
      "format" => "wotex.routines.edge@1",
      "program_digest" => c.program.data["ir_digest"],
      "binding" => "measurement",
      "binding_basis" => c.snapshot["binding_bases"]["measurement"],
      "epoch" => c.time["epoch"],
      "clock_generation" => c.time["clock_generation"],
      "last_elapsed_ms" => c.time["elapsed_ms"],
      "last_receipt_ms" => nil,
      "last_sequence" => nil,
      "last_fact_id" => nil,
      "last_fact_digest" => nil,
      "baseline" => nil,
      "candidate_since_ms" => nil,
      "cooldown_until_ms" => 0,
      "last_original" => nil
    }

    value =
      if c.time["format"] == "wotex.routines.time@2",
        do:
          Map.merge(value, %{
            "format" => "wotex.routines.edge@2",
            "time_format" => "wotex.routines.time@2"
          }),
        else: value

    Map.merge(value, memory)
  end

  @spec collection(map(), [map()], [map()], [map()], map(), map()) :: map()
  def collection(input, transitions, pending, states, profile, limits) do
    data = %{
      "format" => "wotex.routines.collection@2",
      "input" => input,
      "transitions" => transitions,
      "proposals" => pending,
      "proposal_states" => states,
      "profile" => profile,
      "json_limits" => limits
    }

    Map.put(data, "collection_digest", hash(data))
  end

  @spec hash(term()) :: String.t()
  def hash(data) do
    {:ok, bytes} =
      Wotex.JSON.encode(data,
        max_bytes: 67_108_864,
        max_depth: 64,
        max_nodes: 2_000_000,
        max_collection_size: 8192,
        max_string_bytes: 65_536
      )

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  end

  @spec arbitrate([map()], map(), pos_integer(), String.t()) :: map()
  def arbitrate(owned, dispositions, limit, digest) do
    allowed = Enum.filter(owned, &(dispositions[&1["step_original"]]["constraint"] == "allowed"))

    chosen_overrides =
      Enum.filter(allowed, &(dispositions[&1["step_original"]]["override"] == "selected"))

    live =
      Enum.filter(allowed, fn p ->
        case dispositions[p["step_original"]]["override"] do
          "selected" ->
            true

          "suppressed" ->
            false

          "none" ->
            not Enum.any?(chosen_overrides, fn other ->
              overlaps?(p, other) and operation(p) !== operation(other)
            end)
        end
      end)

    resources =
      Enum.reduce(live, %{}, fn p, index ->
        Enum.reduce(p["resource_domains"], index, fn domain, index ->
          Map.update(index, domain, MapSet.new([operation(p)]), &MapSet.put(&1, operation(p)))
        end)
      end)

    order = Enum.uniq_by(live, &operation/1)

    blocked =
      MapSet.new(
        Enum.filter(order, fn p ->
          Enum.any?(p["resource_domains"], &(MapSet.size(resources[&1]) > 1))
        end),
        &operation/1
      )

    winners =
      order
      |> Enum.reject(&MapSet.member?(blocked, operation(&1)))
      |> Enum.take(limit)

    eligible = MapSet.new(live, & &1["step_original"])
    selected = Map.new(winners, &{operation(&1), &1["step_original"]})

    decisions =
      Enum.map(owned, fn p ->
        id = p["step_original"]
        d = dispositions[id]
        key = operation(p)

        outcome =
          cond do
            d["constraint"] == "refused" -> "constraint-refused"
            d["constraint"] == "unknown" -> "constraint-unknown"
            not MapSet.member?(eligible, id) -> "override-suppressed"
            MapSet.member?(blocked, key) -> "conflict"
            not Map.has_key?(selected, key) -> "batch-deferred"
            selected[key] == id -> "selected"
            true -> "coalesced"
          end

        %{"step_original" => id, "outcome" => outcome}
      end)

    groups =
      Enum.map(winners, fn first -> Enum.filter(live, &(operation(&1) === operation(first))) end)

    %{
      "collection_digest" => digest,
      "dispositions" => dispositions,
      "batch_limit" => limit,
      "selected" => groups,
      "decisions" => decisions
    }
  end

  defp operation(p),
    do: %{
      basis: p["installed_basis"],
      target: {p["thing_id"], p["resource_roles"], p["resource_domains"]},
      operation: {p["operation"], p["input"], p["completion"]},
      evidence: p["evidence_contract"]
    }

  defp overlaps?(a, b), do: Enum.any?(a["resource_domains"], &(&1 in b["resource_domains"]))
end
