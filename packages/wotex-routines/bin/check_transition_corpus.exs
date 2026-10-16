defmodule Wotex.Routines.TransitionCorpusFormatter do
  @moduledoc false

  use GenServer

  def init(_), do: {:ok, %{assertions: 0, errors: 0}}

  def handle_cast({:test_finished, %{state: {:failed, failures}}}, state) do
    next =
      Enum.reduce(failures, state, fn
        {:error, %ExUnit.AssertionError{}, _}, s ->
          Map.update!(s, :assertions, &(&1 + 1))

        failure, s ->
          IO.inspect(failure, label: "Transition corpus harness failure", limit: 10)
          Map.update!(s, :errors, &(&1 + 1))
      end)

    {:noreply, next}
  end

  def handle_cast({:test_finished, %{state: {:invalid, _}}}, state),
    do: {:noreply, Map.update!(state, :errors, &(&1 + 1))}

  def handle_cast({:module_finished, %{state: {:failed, _}}}, state),
    do: {:noreply, Map.update!(state, :errors, &(&1 + 1))}

  def handle_cast(event, state) when elem(event, 0) == :suite_finished do
    [{:corpus_owner, owner}] = :ets.lookup(:routines_transition_corpus_counts, :corpus_owner)
    send(owner, {:point_mutation_result, state})
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}
end

defmodule Wotex.Routines.TransitionCorpus do
  @moduledoc false

  @files ~w(
    kernel_test edge_test satisfaction_test receipt_deadline_test
    continuation_test pending_collection_test time_basis_test
    input_execution_test correspondence_test transition_test
  )

  @mutations %{
    "receipt_relation" => {"transition_receipts", {:call, :equal, "/run/steps/receipts"}},
    "tree_motion" => {"transition_tree", {:function, :motion, 5}},
    "point_basis" => {"transition", {:function, :basis, 6}},
    "proposal_set" => {"transition_tree", {:function, :proposals, 1}},
    "edge_fields" => {"transition_edge", {:call, :fields, "/edge"}},
    "old_step_expiry" => {"transition_run", :step_expiry}
  }

  # This opt-in test VM changes only loaded code. It never writes source,
  # BEAMs, archives or extracted dependencies. Forward fixture preparation
  # remains available; every point proof then has all forward seams disabled.
  def run do
    {opts, rest, invalid} = OptionParser.parse(System.argv(), strict: [mutant: :string])
    if rest != [] or invalid != [], do: raise("unsupported transition corpus arguments")
    mutant = opts[:mutant]

    if mutant != nil and not Map.has_key?(@mutations, mutant),
      do: raise("unknown transition mutant")

    Code.require_file("test/test_helper.exs")
    ExUnit.start(autorun: false, seed: 0)
    ExUnit.configure(autorun: false, seed: 0)
    Code.compiler_options(ignore_module_conflict: true)
    :ets.new(:routines_transition_corpus_counts, [:named_table, :public])
    :ets.insert(:routines_transition_corpus_counts, {:corpus_owner, self()})

    formatters =
      if mutant,
        do: [Wotex.Routines.TransitionCorpusFormatter],
        else: [ExUnit.CLIFormatter, Wotex.Routines.TransitionCorpusFormatter]

    ExUnit.configure(formatters: formatters)

    functions = [
      {"execution", :advance, 6},
      {"edge", :advance, 7},
      {"receipt", :apply, 4},
      {"satisfaction", :apply, 7},
      {"pending", :paths, 5},
      {"collection", :evaluate, 3},
      {"collection", :to_map, 3},
      {"kernel", :advance, 7}
    ]

    for {file, selected} <- Enum.group_by(functions, &elem(&1, 0), &{elem(&1, 1), elem(&1, 2)}) do
      instrument(file, selected)
    end

    verify_guards(functions)
    if mutant, do: mutate(mutant)

    for file <- if(mutant, do: ["transition_test"], else: @files),
        do: Code.require_file(Path.join("test/wotex/routines", file <> ".exs"))

    results = ExUnit.run()
    failure_counts = await_counts()

    success =
      if mutant do
        mutation_result(mutant, results, failure_counts)
      else
        counts =
          :ets.tab2list(:routines_transition_corpus_counts)
          |> Enum.reject(fn {key, _} -> key == :corpus_owner end)
          |> Enum.sort()

        IO.inspect(counts, label: "Verified point corpus (forward calls disabled during proof)")

        results.failures == 0 and results.total > 0 and results.skipped == 0 and
          results.excluded == 0 and failure_counts.errors == 0 and failure_counts.assertions == 0
      end

    :ets.delete(:routines_transition_corpus_counts)
    System.halt(if(success, do: 0, else: 1))
  end

  defp await_counts do
    receive do
      {:point_mutation_result, counts} -> counts
    after
      10_000 -> raise "missing transition corpus result"
    end
  end

  defp mutation_result(name, results, counts) do
    IO.puts(
      "POINT_MUTANT " <>
        JSON.encode!(%{
          name: name,
          assertions: counts.assertions,
          errors: counts.errors,
          tests: results.total,
          failures: results.failures
        })
    )

    counts.assertions > 0 and counts.errors == 0 and results.total == 12 and
      results.failures > 0 and results.skipped == 0 and results.excluded == 0
  end

  defp mutate(name) do
    {file, rule} = Map.fetch!(@mutations, name)
    path = Path.join("lib/wotex/routines", file <> ".ex")
    ast = Code.string_to_quoted!(File.read!(path))

    {ast, count} =
      Macro.prewalk(ast, 0, fn node, count ->
        case mutation(node, rule) do
          nil -> {node, count}
          replacement -> {replacement, count + 1}
        end
      end)

    if count != 1, do: raise("transition mutation no longer selects one expression")
    Code.compile_quoted(ast, path)
  end

  defp mutation({:defp, meta, [head, [do: _]]}, {:function, name, arity}) do
    {function, _, args} = signature(head)

    if function == name and length(args || []) == arity do
      body =
        quote do
          _ = {unquote_splicing(args)}
          :ok
        end

      {:defp, meta, [head, [do: body]]}
    end
  end

  defp mutation(
         {{:., _, [{:__aliases__, _, [:TransitionChecks]}, fun]}, _, [left, right, path]},
         {:call, fun, path}
       ) do
    quote do
      _ = {unquote(left), unquote(right)}
      :ok
    end
  end

  defp mutation(
         {{:., _, [{:__aliases__, _, [:Enum]}, :any?]}, _, [{:records, _, _} = records, _]},
         :step_expiry
       ),
       do: quote(do: is_atom(unquote(records)))

  defp mutation(_, _), do: nil

  defp verify_guards(functions) do
    Process.put(:routines_transition_verifying, true)

    try do
      for {file, name, arity} <- functions do
        module = Module.concat(Wotex.Routines, Macro.camelize(file))

        try do
          apply(module, name, List.duplicate(nil, arity))
          raise "forward instrumentation did not refuse"
        rescue
          error in ExUnit.AssertionError ->
            if error.message != "point verifier called a prohibited forward function",
              do: reraise(error, __STACKTRACE__)
        end
      end
    after
      Process.delete(:routines_transition_verifying)
    end

    IO.puts("All #{length(functions)} forward-call guards refuse before execution")
  end

  defp instrument(file, functions) do
    path = Path.join("lib/wotex/routines", file <> ".ex")
    ast = Code.string_to_quoted!(File.read!(path))

    ast =
      Macro.postwalk(ast, fn
        {:def, meta, [head, [do: body]]} = definition ->
          {function, _, args} = signature(head)

          if {function, length(args || [])} in functions do
            wrapped = guarded(body)

            wrapped =
              case file do
                "kernel" -> prove(wrapped, args)
                "edge" -> prove_edge(wrapped, args)
                _ -> wrapped
              end

            {:def, meta, [head, [do: wrapped]]}
          else
            definition
          end

        other ->
          other
      end)

    Code.compile_quoted(ast, path)
  end

  defp signature({:when, _, [head | _]}), do: head
  defp signature(head), do: head

  defp guarded(body) do
    quote do
      if Process.get(:routines_transition_verifying) do
        raise ExUnit.AssertionError, message: "point verifier called a prohibited forward function"
      end

      unquote(body)
    end
  end

  defp prove_edge(body, [program, event, snapshot, time, prior, profile, limits]) do
    quote do
      case unquote(body) do
        {:ok, edge_result} = success ->
          Wotex.Routines.TransitionCorpus.edge_point!(
            unquote(program),
            unquote(event),
            unquote(snapshot),
            unquote(time),
            unquote(prior),
            edge_result,
            unquote(profile),
            unquote(limits)
          )

          success

        refusal ->
          refusal
      end
    end
  end

  def edge_point!(program, event, snapshot, time, prior, result, profile, limits) do
    {:ok, limits} = Wotex.Routines.Limits.new(limits)
    {:ok, program} = Wotex.Routines.Compiler.to_map(program, profile, limits)
    {:ok, snapshot} = Wotex.Routines.Snapshot.to_map(snapshot, program, profile, limits)
    {:ok, event} = Wotex.Routines.Event.to_map(event, limits)
    {:ok, time} = Wotex.Routines.Time.to_map(time, limits)

    prior =
      if prior do
        {:ok, data} = Wotex.Routines.Edge.to_map(prior, program, profile, limits)
        data
      end

    c = %{
      program: program,
      snapshot: snapshot,
      event: event,
      time: time,
      prior: %{"edge" => prior},
      limits: limits,
      values: Wotex.Routines.TransitionObservation.values(program, snapshot, time, limits)
    }

    Process.put(:routines_transition_verifying, true)

    try do
      if Wotex.Routines.TransitionEdge.verify(c, result["edge"]) != {:ok, result["eligible"]},
        do: raise(ExUnit.AssertionError, message: "edge relation refused a valid prepared edge")

      key = {:edge_proof, result["edge"]["format"]}
      :ets.update_counter(:routines_transition_corpus_counts, key, 1, {key, 0})
    after
      Process.delete(:routines_transition_verifying)
    end
  end

  defp prove(body, [program, event, snapshot, time, prior, profile, limits]) do
    quote do
      case unquote(body) do
        {:ok, point_result} = success ->
          Process.put(:routines_transition_verifying, true)

          try do
            checked =
              Wotex.Routines.Transition.verify(
                unquote(program),
                unquote(event),
                unquote(snapshot),
                unquote(time),
                unquote(prior),
                point_result,
                unquote(profile),
                unquote(limits)
              )

            bounded =
              match?({:error, %Wotex.Routines.Error{code: :limit_or_json_error}}, checked) and
                not Wotex.Routines.TransitionCorpus.envelope_fits?(
                  unquote(program),
                  point_result,
                  unquote(profile),
                  unquote(limits)
                )

            if checked != :ok and not bounded do
              raise ExUnit.AssertionError,
                message: "point verifier refused a valid prepared transition: #{inspect(checked)}"
            end

            keys =
              if bounded,
                do: [{:bounded_refusal, "combined_argument_envelope"}],
                else: [
                  {:event, point_result["basis"]["event"]["kind"]},
                  {:outcome, point_result["outcome"]},
                  {:time,
                   Map.get(point_result["basis"]["time"], "format", "wotex.routines.time@1")},
                  {:run, point_result["run"] && point_result["run"]["format"]}
                ]

            for key <- keys do
              :ets.update_counter(:routines_transition_corpus_counts, key, 1, {key, 0})
            end

            success
          after
            Process.delete(:routines_transition_verifying)
          end

        refusal ->
          refusal
      end
    end
  end

  def envelope_fits?(program, result, profile, limits) do
    {:ok, program} = Wotex.Routines.Compiler.to_map(program, profile, limits)
    {:ok, profile} = Wotex.Routines.Profile.to_map(profile)
    {:ok, selected} = Wotex.Routines.Limits.new(limits)

    envelope =
      Map.merge(Map.take(result["basis"], ~w(event snapshot time prior)), %{
        "program" => program,
        "claimed_result" => result,
        "profile" => profile,
        "json_limits" => selected.data
      })

    Wotex.Routines.Validation.bounded(envelope, selected) == :ok
  end
end

Wotex.Routines.TransitionCorpus.run()
