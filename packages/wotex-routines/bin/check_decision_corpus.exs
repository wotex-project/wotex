defmodule Wotex.Routines.DecisionCorpus do
  @moduledoc false

  @functions [
    {"execution", :advance, 6},
    {"edge", :advance, 7},
    {"receipt", :apply, 4},
    {"satisfaction", :apply, 7},
    {"pending", :paths, 5},
    {"collection", :evaluate, 3},
    {"collection", :to_map, 3},
    {"kernel", :advance, 7},
    {"arbitration", :decide, 5}
  ]
  @table :routines_transition_corpus_counts
  @time_mutations %{
    "negative_members" =>
      {"defp entry(state, entry, result) do",
       "defp entry(state, _entry, nil), do: state\n" <>
         "  defp entry(state, _entry, %{\"proposals\" => []}), do: state\n" <>
         "  defp entry(state, entry, result) do"},
    "freshness_inclusive" =>
      {"fact[\"receipt_ms\"] + evidence[\"freshness_ms\"] + 1",
       "fact[\"receipt_ms\"] + evidence[\"freshness_ms\"]"},
    "expiry_exclusive" =>
      {"cut(:elapsed, fact[\"expires_ms\"])", "cut(:elapsed, fact[\"expires_ms\"] + 1)"},
    "fractional_floor" =>
      {"center = DateTime.to_unix(instant, :millisecond)",
       "center = div(DateTime.to_unix(instant, :microsecond), 1000)"},
    "prior_history" =>
      {"[entry[\"prior\"][\"original\"], entry[\"prior\"][\"busy\"], result && result[\"run\"]]",
       "[nil, nil, result && result[\"run\"]]"},
    "utc_high_endpoint" =>
      {"do: inside(cell[\"utc_high\"], time[\"utc_high_ms\"], \"/cell/utc_high\")", "do: :ok"},
    "elapsed_generation" =>
      {"equal(cell[\"clock_generation\"], time[\"clock_generation\"], \"/cell/clock_generation\")",
       ":ok"},
    "clamp_cuts" =>
      {"cut < minimum or cut > maximum -> axis",
       "cut < minimum or cut > maximum -> nearest(axis, max(minimum, min(maximum, cut)))"}
  }

  # Opt-in fresh VM only. Every rewritten module is compiled in memory; no
  # source, BEAM, archive, dependency, temporary build or Docker object is written.
  @spec run() :: no_return()
  def run do
    options = options!()
    Code.require_file("test/test_helper.exs")
    ExUnit.start(autorun: false, seed: 0)
    ExUnit.configure(autorun: false, seed: 0)
    Code.compiler_options(ignore_module_conflict: true)

    # Reuse only the assertion/runtime-error formatter, never the point runner.
    {:__block__, _, [formatter | _]} =
      Code.string_to_quoted!(File.read!("bin/check_transition_corpus.exs"))

    Code.compile_quoted(formatter, "bin/check_transition_corpus.exs")
    ExUnit.configure(formatters: [ExUnit.CLIFormatter, Wotex.Routines.TransitionCorpusFormatter])
    :ets.new(@table, [:named_table, :public])
    :ets.insert(@table, {:corpus_owner, self()})

    for {file, selected} <- Enum.group_by(@functions, &elem(&1, 0), &{elem(&1, 1), elem(&1, 2)}),
        do: instrument(file, selected, false)

    probe_guards()

    success =
      try do
        if options[:time_only] || options[:time_mutant] do
          time_matrix(options[:time_mutant])
        else
          complete_corpus()
        end
      after
        :ets.delete(@table)
      end

    System.halt(if success, do: 0, else: 1)
  end

  defp options! do
    {options, rest, invalid} =
      OptionParser.parse(System.argv(), strict: [time_only: :boolean, time_mutant: :string])

    if rest != [] or invalid != [], do: raise("unsupported decision corpus arguments")

    if options[:time_mutant] && not Map.has_key?(@time_mutations, options[:time_mutant]),
      do: raise("unknown decision time mutant")

    options
  end

  defp complete_corpus do
    Code.require_file("test/wotex/routines/decision_test.exs")
    first = suite("public Decision cases", 15)
    schemas!()
    time_matrix = time_matrix(nil)

    # Prepare through the forward API, then check every successful v2 relation
    # with all guards active, including nested Collection regeneration.
    instrument("collection", [{:evaluate, 3}, {:to_map, 3}], true)
    instrument("arbitration", [{:decide, 5}], true)
    Code.require_file("test/wotex/routines/pending_collection_test.exs")
    Code.require_file("test/wotex/routines/time_basis_test.exs")
    second = suite("existing complete-pending and clock corpus", 26)
    counts = :ets.tab2list(@table) |> Enum.reject(fn {key, _} -> key == :corpus_owner end)

    IO.inspect(Enum.sort(counts),
      label: "Complete decision relations with forward calls disabled during proof"
    )

    first and time_matrix and second and Map.new(counts) == %{collection: 70, arbitration: 7}
  end

  defp time_matrix(mutant) do
    if mutant do
      path = "lib/wotex/routines/decision_cell.ex"
      source = File.read!(path)
      {from, to} = Map.fetch!(@time_mutations, mutant)
      if length(String.split(source, from)) != 2, do: raise("time mutation target drift")
      Code.compile_string(String.replace(source, from, to, global: false), path)
    end

    Code.require_file("test/wotex/routines/decision_time_matrix_test.exs")
    label = "independent public Decision time matrix" <> if(mutant, do: " / " <> mutant, else: "")
    suite(label, 9, mutant != nil)
  end

  defp suite(label, expected, mutant? \\ false) do
    stats = ExUnit.run()

    counts =
      receive do
        {:point_mutation_result, counts} -> counts
      after
        10_000 -> raise "missing decision corpus formatter result"
      end

    IO.inspect({label, stats, counts}, label: "Decision corpus phase")

    caught =
      if mutant?,
        do: counts.assertions > 0 and stats.failures == counts.assertions,
        else: stats.failures == 0 and counts.assertions == 0

    stats.total == expected and stats.skipped == 0 and stats.excluded == 0 and
      counts.errors == 0 and caught
  end

  defp schemas! do
    path =
      Path.join(
        to_string(:code.priv_dir(:wotex_routines)),
        "schemas/wro-02-verified-decision.schema.json"
      )

    raw = path |> File.read!() |> JSON.decode!()

    for grammar <- [1, 2] do
      c = Wotex.Routines.Test.ContinuationFixtures.fixture()

      time =
        if grammar == 1,
          do: c.time,
          else:
            Map.merge(c.time, %{"format" => "wotex.routines.time@2", "utc_generation" => "utc:1"})

      c = %{c | time: time}
      members = Wotex.Routines.Test.DecisionFixtures.members(c, [{"schema", false, "schema"}])
      input = Wotex.Routines.Test.DecisionFixtures.input(c, members)
      collection = Wotex.Routines.Test.DecisionFixtures.collection(c, input)
      decision = Wotex.Routines.Test.DecisionFixtures.decision(c, collection)
      current = Wotex.Routines.Test.DecisionFixtures.context(c, collection)

      checked =
        proof(fn ->
          require_value(Wotex.Routines.Decision.check(decision, current, c.profile, c.limits))
        end)

      for {name, value} <- [
            {"decision", decision.data},
            {"current_context", current},
            {"checked_decision", checked}
          ] do
        schema =
          raw
          |> Map.put("oneOf", [%{"$ref" => "#/definitions/" <> name}])
          |> ExJsonSchema.Schema.resolve()

        if ExJsonSchema.Validator.validate(schema, value) != :ok,
          do:
            raise(ExUnit.AssertionError,
              message: "public decision output does not match frozen schema"
            )
      end
    end

    IO.puts(
      "Six actual decision/context/checked outputs pass frozen schemas across both Time grammars"
    )
  end

  defp instrument(file, functions, relations) do
    path = Path.join("lib/wotex/routines", file <> ".ex")
    ast = Code.string_to_quoted!(File.read!(path))

    ast =
      Macro.postwalk(ast, fn
        {:def, meta, [head, [do: body]]} = definition ->
          {name, _, args} = signature(head)

          if {name, length(args || [])} in functions do
            wrapped = guard(body)
            wrapped = if relations, do: relation(file, name, wrapped, args), else: wrapped
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

  defp guard(body) do
    quote do
      if Process.get(:routines_transition_verifying),
        do:
          raise(ExUnit.AssertionError,
            message: "decision verifier called a prohibited forward function"
          )

      unquote(body)
    end
  end

  defp relation("collection", :evaluate, body, [input, profile, limits]) do
    quote do
      case unquote(body) do
        {:ok,
         %Wotex.Routines.Collection{data: %{"format" => "wotex.routines.collection@2"}} = collection} =
            result ->
          Wotex.Routines.DecisionCorpus.collection!(
            unquote(input),
            collection,
            unquote(profile),
            unquote(limits)
          )

          result

        result ->
          result
      end
    end
  end

  defp relation("arbitration", :decide, body, [collection, dispositions, batch, profile, limits]) do
    quote do
      case unquote(body) do
        {:ok, claim} = result ->
          Wotex.Routines.DecisionCorpus.arbitration!(
            unquote(collection),
            claim,
            unquote(dispositions),
            unquote(batch),
            unquote(profile),
            unquote(limits)
          )

          result

        result ->
          result
      end
    end
  end

  defp relation(_, _, body, _), do: body

  @spec collection!(map(), term(), term(), term()) :: :ok
  def collection!(input, collection, profile, limits) do
    proof(fn ->
      require_ok(Wotex.Routines.Decision.verify_point(input, collection, profile, limits))
      decision = require_value(Wotex.Routines.Decision.new(collection, profile, limits))
      data = require_value(Wotex.Routines.Decision.to_map(decision, profile, limits))

      if data !== decision.data,
        do: raise(ExUnit.AssertionError, message: "decision projection changed point")

      increment(:collection)
    end)
  end

  @spec arbitration!(term(), map(), map(), pos_integer(), term(), term()) :: :ok
  def arbitration!(collection, claim, dispositions, batch, profile, limits) do
    data =
      case collection do
        %Wotex.Routines.Collection{data: data} -> data
        data -> data
      end

    if data["format"] == "wotex.routines.collection@2" do
      proof(fn ->
        decision = require_value(Wotex.Routines.Decision.new(collection, profile, limits))

        context = %{
          "input" => data["input"],
          "dispositions" => dispositions,
          "batch_limit" => batch,
          "arbitration" => claim
        }

        checked = require_value(Wotex.Routines.Decision.check(decision, context, profile, limits))

        if checked["arbitration"] !== claim,
          do: raise(ExUnit.AssertionError, message: "decision changed arbitration claim")

        increment(:arbitration)
      end)
    else
      :ok
    end
  end

  defp proof(fun) do
    Process.put(:routines_transition_verifying, true)

    try do
      fun.()
    after
      Process.delete(:routines_transition_verifying)
    end
  end

  defp require_ok(:ok), do: :ok

  defp require_ok(error),
    do: raise(ExUnit.AssertionError, message: "valid decision relation refused: #{inspect(error)}")

  defp require_value({:ok, value}), do: value
  defp require_value(error), do: require_ok(error)

  defp increment(key) do
    :ets.update_counter(@table, key, 1, {key, 0})
    :ok
  end

  defp probe_guards do
    proof(fn ->
      for {file, name, arity} <- @functions do
        module = Module.concat(Wotex.Routines, Macro.camelize(file))

        try do
          apply(module, name, List.duplicate(nil, arity))
          raise "forward guard did not refuse"
        rescue
          error in ExUnit.AssertionError ->
            if error.message != "decision verifier called a prohibited forward function",
              do: reraise(error, __STACKTRACE__)
        end
      end
    end)

    IO.puts("All #{length(@functions)} forward-call guards refuse before execution")
  end
end

Wotex.Routines.DecisionCorpus.run()
