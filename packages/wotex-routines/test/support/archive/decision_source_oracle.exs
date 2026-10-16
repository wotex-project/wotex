defmodule DecisionSourceOracle do
  @moduledoc false

  # Independent finite source relation: raw source/definitions and an oracle-owned
  # previous Run only. No compiled tree or production semantic helper is read.
  @slots ~w(admission handoff local_queue protocol_response correlated_report reported_match terminal)

  @spec advance(map(), map() | nil) :: map()
  def advance(c, previous \\ nil) do
    ordinary_profile!(c, previous)
    nodes = layout(c.source["steps"], [], c.context["definitions"])
    records = if previous, do: previous["steps"], else: templates(c, nodes)
    now = c.time["elapsed_ms"]
    deadline = if previous, do: previous["deadline_ms"], else: now + c.source["run_ms"]

    state = %{
      c: c,
      records: Map.new(records, &{&1["path"], &1}),
      nodes: Map.new(nodes),
      paths: [],
      blocked: false
    }

    state =
      if literal(c.source["condition"]) == true,
        do: walk(c.source["steps"], [], deadline, state),
        else: %{state | blocked: true}

    root = state.records[[]]["status"]

    status =
      cond do
        root == "completed" -> "completed"
        state.blocked -> "blocked"
        true -> "running"
      end

    run =
      if previous,
        do: %{previous | "last_ms" => max(previous["last_ms"], now)},
        else: header(c, deadline)

    run = %{
      run
      | "steps" => Enum.map(nodes, fn {path, _} -> state.records[path] end),
        "status" => status,
        "reason" => if(status == "blocked", do: "condition_blocked", else: nil)
    }

    paths = Enum.reverse(state.paths)
    proposals = Enum.map(paths, &proposal(c, run, &1, state.nodes[&1]))
    result(c, previous, run, proposals)
  end

  @spec result(map(), map() | nil, map(), [map()]) :: map()
  def result(c, before, run, proposals) do
    %{
      "run" => run,
      "proposals" => proposals,
      "outcome" => run["status"],
      "edge" => nil,
      "basis" => %{
        "program_digest" => c.program.data["ir_digest"],
        "source_digest" => c.program.data["source_digest"],
        "compiler_basis" => c.context["compiler_basis"],
        "event" => c.event,
        "prior" => %{"original" => before, "busy" => nil, "edge" => nil},
        "snapshot" => c.snapshot,
        "time" => c.time
      }
    }
  end

  @spec receipt(map()) :: map()
  def receipt(event) do
    outcome =
      case event["kind"] do
        "satisfied" -> "matched"
        "handoff" -> "marked"
        _ -> event["outcome"]
      end

    %{"ref" => event["ref"], "digest" => hash(event), "outcome" => outcome}
  end

  @spec receipt_run(map(), map(), String.t(), String.t()) :: map()
  def receipt_run(c, before, slot, status) do
    receipt = receipt(c.event)

    steps =
      Enum.map(before["steps"], fn record ->
        if record["path"] == c.event["path"],
          do: %{
            record
            | "receipts" => Map.put(record["receipts"], slot, receipt),
              "status" => status
          },
          else: record
      end)

    spent =
      if slot == "admission" and c.event["outcome"] == "held" and
           not Enum.any?(before["spent"], &(&1["ref"] == c.event["ref"])),
         do:
           Enum.concat(
             before["spent"],
             [%{"original" => identity(c, c.event["path"]), "ref" => c.event["ref"]}]
           ),
         else: before["spent"]

    %{
      before
      | "steps" => steps,
        "spent" => spent,
        "last_ms" => max(before["last_ms"], c.time["elapsed_ms"])
    }
  end

  @spec stopped(map(), map(), String.t(), String.t()) :: map()
  def stopped(c, run, status, reason) do
    steps =
      Enum.map(run["steps"], fn record ->
        next =
          case record["status"] do
            s when s in ~w(unsent proposed reserved waiting) -> "cancelled"
            "handed_off" -> "unknown"
            other -> other
          end

        %{record | "status" => next}
      end)

    %{
      run
      | "steps" => steps,
        "status" => status,
        "reason" => reason,
        "last_ms" => max(run["last_ms"], c.time["elapsed_ms"])
    }
  end

  @spec satisfied(map(), map()) :: map()
  def satisfied(c, before) do
    promoted =
      before
      |> Map.put("format", "wotex.routines.run@2")
      |> Map.put("time_format", Map.get(c.time, "format", "wotex.routines.time@1"))

    promoted =
      update_in(promoted, ["steps"], fn steps ->
        Enum.map(
          steps,
          &update_in(&1, ["receipts"], fn receipts -> Map.put_new(receipts, "satisfied", nil) end)
        )
      end)

    run = receipt_run(c, promoted, "satisfied", "completed")
    run = %{run | "status" => "completed", "reason" => nil}
    result(c, before, run, [])
  end

  @spec identity(map(), list()) :: String.t()
  def identity(c, path),
    do:
      hash(%{
        "program_digest" => c.program.data["ir_digest"],
        "original" => c.event["original"],
        "path" => path
      })

  @spec hash(term()) :: String.t()
  def hash(data) do
    {:ok, bytes} = Wotex.JSON.encode(data)
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  end

  @spec arbitrate([map()], map(), pos_integer(), String.t()) :: map()
  def arbitrate(proposals, dispositions, maximum, digest) do
    allowed =
      Enum.filter(proposals, &(dispositions[&1["step_original"]]["constraint"] == "allowed"))

    explicit = Enum.filter(allowed, &(dispositions[&1["step_original"]]["override"] == "selected"))

    eligible =
      Enum.filter(allowed, fn proposal ->
        case dispositions[proposal["step_original"]]["override"] do
          "selected" -> true
          "suppressed" -> false
          "none" -> not Enum.any?(explicit, &incompatible?(proposal, &1))
        end
      end)

    grouped = Enum.group_by(eligible, &key/1)
    keys = Enum.map(eligible, &key/1)
    order = Enum.uniq(keys)
    indices = Enum.with_index(order)

    conflicts =
      for {left, i} <- indices,
          {right, j} <- indices,
          i < j,
          incompatible?(hd(grouped[left]), hd(grouped[right])),
          reduce: MapSet.new() do
        found -> MapSet.put(MapSet.put(found, left), right)
      end

    nonconflicting = Enum.reject(order, &MapSet.member?(conflicts, &1))
    chosen = Enum.take(nonconflicting, maximum)
    eligible_ids = MapSet.new(eligible, & &1["step_original"])

    decisions =
      Enum.map(proposals, fn proposal ->
        id = proposal["step_original"]
        disposition = dispositions[id]
        k = key(proposal)

        value =
          cond do
            disposition["constraint"] == "refused" -> "constraint-refused"
            disposition["constraint"] == "unknown" -> "constraint-unknown"
            not MapSet.member?(eligible_ids, id) -> "override-suppressed"
            MapSet.member?(conflicts, k) -> "conflict"
            k not in chosen -> "batch-deferred"
            hd(grouped[k])["step_original"] == id -> "selected"
            true -> "coalesced"
          end

        %{"step_original" => id, "outcome" => value}
      end)

    %{
      "collection_digest" => digest,
      "dispositions" => dispositions,
      "batch_limit" => maximum,
      "selected" => Enum.map(chosen, &grouped[&1]),
      "decisions" => decisions
    }
  end

  defp key(p),
    do:
      Enum.map(
        ~w(installed_basis operation input thing_id resource_roles resource_domains completion evidence_contract),
        &p[&1]
      )

  defp incompatible?(a, b),
    do: key(a) !== key(b) and Enum.any?(a["resource_domains"], &(&1 in b["resource_domains"]))

  defp layout(node, path, definitions) do
    [
      {path, node}
      | Enum.flat_map(children(node, definitions), fn {index, child} ->
          layout(child, Enum.concat(path, [index]), definitions)
        end)
    ]
  end

  defp children(%{"kind" => "sequence", "steps" => children}, _),
    do: Enum.map(Enum.with_index(children), fn {child, i} -> {i, child} end)

  defp children(%{"kind" => "parallel", "branches" => children}, _),
    do: Enum.map(Enum.with_index(children), fn {child, i} -> {i, child} end)

  defp children(%{"kind" => "if"} = node, _), do: [{0, node["then"]}, {1, node["else"]}]

  defp children(%{"kind" => "invoke"} = node, definitions),
    do: [{0, definition(node, definitions)["steps"]}]

  defp children(_, _), do: []

  defp definition(node, definitions),
    do:
      Enum.find(
        definitions,
        &(&1["id"] == node["routine_id"] and &1["revision"] == node["revision"])
      )

  defp templates(c, nodes) do
    slots = if c.time["format"] == "wotex.routines.time@2", do: ["satisfied" | @slots], else: @slots

    Enum.map(nodes, fn {path, node} ->
      %{
        "path" => path,
        "kind" => node["kind"],
        "original" => identity(c, path),
        "status" => "unsent",
        "started_ms" => nil,
        "deadline_ms" => nil,
        "branch" => nil,
        "receipts" => Map.new(slots, &{&1, nil})
      }
    end)
  end

  defp header(c, deadline) do
    run = %{
      "format" => "wotex.routines.run@1",
      "original" => c.event["original"],
      "program_digest" => c.program.data["ir_digest"],
      "source_digest" => c.program.data["source_digest"],
      "compiler_basis" => c.context["compiler_basis"],
      "epoch" => c.time["epoch"],
      "clock_generation" => c.time["clock_generation"],
      "start_ms" => c.time["elapsed_ms"],
      "last_ms" => c.time["elapsed_ms"],
      "deadline_ms" => deadline,
      "window" => window(c.event),
      "status" => "running",
      "reason" => nil,
      "steps" => [],
      "spent" => []
    }

    if c.time["format"] == "wotex.routines.time@2",
      do:
        Map.merge(run, %{
          "format" => "wotex.routines.run@2",
          "time_format" => "wotex.routines.time@2"
        }),
      else: run
  end

  # Expiry, receipts and terminal restoration use explicit oracle-owned ledger
  # cases above. Never silently treat those as ordinary source execution.
  defp ordinary_profile!(_, nil), do: :ok

  defp ordinary_profile!(c, previous) do
    now = c.time["elapsed_ms"]

    outside =
      previous["status"] not in ~w(running blocked) or
        not same_basis?(c, previous) or previous["window"] != nil or now < previous["last_ms"] or
        now >= previous["deadline_ms"] or
        Enum.any?(previous["steps"], fn record ->
          record["status"] != "completed" and is_integer(record["deadline_ms"]) and
            now >= record["deadline_ms"]
        end)

    if outside, do: raise(ArgumentError, "outside ordinary source oracle profile"), else: :ok
  end

  defp same_basis?(c, previous) do
    previous["epoch"] == c.time["epoch"] and
      previous["clock_generation"] == c.time["clock_generation"] and
      previous["program_digest"] == c.program.data["ir_digest"] and
      Map.get(previous, "time_format", "wotex.routines.time@1") ==
        Map.get(c.time, "format", "wotex.routines.time@1")
  end

  defp window(%{"kind" => "due"} = event),
    do:
      Map.take(
        event,
        ~w(schedule_id schedule_basis due_ms late_window_ms clock_generation time_zone_basis)
      )

  defp window(_), do: nil

  defp walk(node, path, inherited, state) do
    record = state.records[path]

    if record["status"] == "completed" do
      state
    else
      start = record["started_ms"] || state.c.time["elapsed_ms"]
      deadline = record["deadline_ms"] || inherited
      record = %{record | "started_ms" => start, "deadline_ms" => deadline}
      state = %{state | records: Map.put(state.records, path, record)}
      instruction(node, path, inherited, state)
    end
  end

  defp instruction(%{"kind" => "noop"}, path, _, state), do: status(state, path, "completed")

  defp instruction(%{"kind" => "effect"} = node, path, inherited, state) do
    record = state.records[path]

    if record["status"] == "unsent" do
      binding = state.c.context["bindings"][node["binding"]]
      basis = Enum.find(state.c.context["bases"], &(&1["id"] == binding["basis"]["id"]))
      deadline = min(inherited, state.c.time["elapsed_ms"] + basis["timing"]["deadline_ms"])
      record = %{record | "status" => "proposed", "deadline_ms" => deadline}
      %{state | records: Map.put(state.records, path, record), paths: [path | state.paths]}
    else
      state
    end
  end

  defp instruction(%{"kind" => "delay", "duration_ms" => duration}, path, _, state),
    do:
      status(
        state,
        path,
        if(state.c.time["elapsed_ms"] >= state.records[path]["started_ms"] + duration,
          do: "completed",
          else: "waiting"
        )
      )

  defp instruction(%{"kind" => "wait"} = node, path, inherited, state) do
    record = state.records[path]
    deadline = min(inherited, record["started_ms"] + node["timeout_ms"])
    state = %{state | records: Map.put(state.records, path, %{record | "deadline_ms" => deadline})}
    status(state, path, if(literal(node["condition"]) == true, do: "completed", else: "waiting"))
  end

  defp instruction(%{"kind" => "sequence", "steps" => children}, path, inherited, state) do
    state =
      children
      |> Enum.with_index()
      |> Enum.reduce_while(state, fn {node, i}, state ->
        next = walk(node, Enum.concat(path, [i]), inherited, state)

        if next.records[Enum.concat(path, [i])]["status"] == "completed",
          do: {:cont, next},
          else: {:halt, next}
      end)

    join(state, path, Enum.map(0..(length(children) - 1), &Enum.concat(path, [&1])))
  end

  defp instruction(%{"kind" => "parallel", "branches" => children}, path, inherited, state) do
    state =
      children
      |> Enum.with_index()
      |> Enum.reduce(state, fn {node, i}, state ->
        walk(node, Enum.concat(path, [i]), inherited, state)
      end)

    join(state, path, Enum.map(0..(length(children) - 1), &Enum.concat(path, [&1])))
  end

  defp instruction(%{"kind" => "if"} = node, path, inherited, state) do
    record = state.records[path]

    selected =
      record["branch"] ||
        case literal(node["condition"]) do
          true -> "then"
          false -> "else"
          "unknown" -> nil
        end

    if selected do
      index = if selected == "then", do: 0, else: 1
      record = %{record | "branch" => selected}
      state = %{state | records: Map.put(state.records, path, record)}
      state = walk(node[selected], Enum.concat(path, [index]), inherited, state)
      join(state, path, [Enum.concat(path, [index])])
    else
      %{state | blocked: true}
    end
  end

  defp instruction(%{"kind" => "invoke"} = node, path, inherited, state) do
    child = definition(node, state.c.context["definitions"])
    record = state.records[path]
    deadline = min(inherited, record["started_ms"] + child["run_ms"])
    state = %{state | records: Map.put(state.records, path, %{record | "deadline_ms" => deadline})}

    state =
      if literal(child["condition"]) == true,
        do: walk(child["steps"], Enum.concat(path, [0]), deadline, state),
        else: %{state | blocked: true}

    join(state, path, [Enum.concat(path, [0])])
  end

  defp join(state, path, children),
    do:
      status(
        state,
        path,
        if(Enum.all?(children, &(state.records[&1]["status"] == "completed")),
          do: "completed",
          else: "waiting"
        )
      )

  defp status(state, path, value),
    do: %{state | records: Map.update!(state.records, path, &%{&1 | "status" => value})}

  defp literal(%{"op" => "literal", "value" => value}), do: value

  defp proposal(c, run, path, node) do
    binding = c.context["bindings"][node["binding"]]
    basis = Enum.find(c.context["bases"], &(&1["id"] == binding["basis"]["id"]))

    %{
      "original" => run["original"],
      "step_original" => identity(c, path),
      "program_digest" => c.program.data["ir_digest"],
      "path" => path,
      "binding" => node["binding"],
      "installed_basis" => binding["basis"],
      "thing_id" => binding["thing_id"],
      "resource_roles" => binding["resource_roles"],
      "resource_domains" =>
        Enum.sort(Enum.uniq([binding["thing_id"] | Map.values(binding["resource_roles"])])),
      "operation" => basis["affordance"]["operation"],
      "input" => node["input"],
      "completion" => node["completion"],
      "evidence_contract" => basis["evidence"]["report_contract"]
    }
  end
end
