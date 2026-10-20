defmodule Wotex.Routines.Check.DecisionConsumers do
  @moduledoc false

  @spec run(Path.t(), keyword(Path.t()), Path.t()) :: :ok
  def run(archive, paths, temporary) do
    IO.puts("decision workspace: " <> temporary)

    for family <- ~w(source journal) do
      consumer = Path.join(temporary, "decision-" <> family)
      tests = Path.join(consumer, "test")
      File.mkdir_p!(tests)
      project!(paths, consumer)

      for file <- ["decision_inputs.exs", "decision_#{family}_oracle.exs"] do
        copy!("test/support/archive/" <> file, Path.join(tests, file))
      end

      copy!(
        "test/support/archive/decision_#{family}_consumer.exs",
        Path.join(tests, "decision_consumer_test.exs")
      )

      copy!("test/support/archive/decision_identity_consumer.exs", Path.join(tests, "identity.exs"))
      script = Path.join(consumer, "decision_mutations.exs")
      copy!("test/support/archive/decision_mutation_consumer.exs", script)
      IO.puts("decision mutation runner sha256: " <> sha256(__ENV__.file))

      environment = [
        {"WOTEX_PATH_DEPS", nil},
        {"MIX_ENV", "test"},
        {"MIX_BUILD_PATH", nil},
        {"MIX_BUILD_ROOT", nil},
        {"MIX_DEPS_PATH", nil},
        {"WOTEX_ROUTINES_CONSUMER_ROOT", consumer},
        {"WOTEX_ROUTINES_COMPILER_BASIS", "sha256:" <> sha256(archive)}
      ]

      IO.puts("decision consumer: " <> family)
      command!(["deps.get"], consumer, environment)
      command!(["compile", "--warnings-as-errors"], consumer, environment)
      baseline = execute(consumer, environment, script, "baseline")
      verify!(baseline, 8, false, family <> "/baseline")

      IO.puts(
        family <> " decision consumer lock sha256: " <> sha256(Path.join(consumer, "mix.lock"))
      )

      # Each VM changes only its own in-memory module. Finish all children before
      # returning a refusal so the parent's archive cleanup cannot race a child.
      replacements = replacements!(paths, consumer)

      results =
        replacements
        |> Task.async_stream(
          fn {name, replacement} ->
            {name, execute(consumer, environment, script, replacement)}
          end,
          max_concurrency: 2,
          timeout: :infinity
        )
        |> Enum.to_list()

      for {:ok, {name, result}} <- results do
        verify!(result, 7, true, family <> "/" <> name)
      end

      unless Enum.all?(results, &match?({:ok, _}, &1)),
        do: refuse("decision mutation worker failed")
    end

    :ok
  end

  defp project!(paths, consumer) do
    dependencies =
      Enum.map(paths, fn {app, path} -> {app, [path: path, env: :prod, override: true]} end)

    File.write!(Path.join(consumer, "mix.exs"), """
    defmodule DecisionArchiveConsumer.MixProject do
      use Mix.Project
      def project, do: [app: :decision_archive_consumer, version: "0.0.0",
        elixir: "~> 1.18", deps: #{inspect(dependencies, limit: :infinity)}]
      def application, do: [extra_applications: []]
    end
    """)
  end

  defp execute(consumer, environment, script, replacement) do
    {output, status} =
      System.cmd("mix", ["run", "--no-start", "--no-compile", script, replacement],
        cd: consumer,
        env: environment,
        stderr_to_stdout: true
      )

    %{output: output, status: status}
  end

  defp verify!(result, count, mutant?, label) do
    case validate(result.output, result.status, count, mutant?) do
      {:ok, counts} ->
        IO.puts(label <> ": " <> JSON.encode!(counts))

      {:error, reason} ->
        IO.write(result.output)
        refuse(label <> ": " <> reason)
    end
  end

  @doc false
  @spec validate(String.t(), integer(), pos_integer(), boolean()) ::
          {:ok, map()} | {:error, String.t()}
  def validate(output, status, total, mutant?) do
    with {:ok, result} <- marker(output, "DECISION_RESULT="),
         {:ok, assertions} <- marker(output, "DECISION_ASSERTIONS="),
         true <- valid_counts?(result, assertions, total, status, mutant?) do
      {:ok, Map.merge(result, assertions)}
    else
      _ -> {:error, "invalid counts, marker, process status or assertion-only mutation result"}
    end
  end

  defp marker(output, prefix) do
    case Enum.filter(String.split(output, "\n"), &String.starts_with?(&1, prefix)) do
      [line] -> JSON.decode(String.replace_prefix(line, prefix, ""))
      _ -> {:error, :marker}
    end
  end

  defp valid_counts?(result, assertions, total, status, mutant?)
       when is_map(result) and is_map(assertions) do
    keys = ~w(total failures skipped excluded)

    Enum.sort(Map.keys(result)) == Enum.sort(keys) and
      Enum.sort(Map.keys(assertions)) == ~w(assertions errors) and
      Enum.all?(Map.values(result) ++ Map.values(assertions), &(is_integer(&1) and &1 >= 0)) and
      result["total"] == total and result["skipped"] == 0 and result["excluded"] == 0 and
      assertions["errors"] == 0 and
      if mutant? do
        status == 1 and result["failures"] in 1..total and
          assertions["assertions"] == result["failures"]
      else
        status == 0 and result["failures"] == 0 and assertions["assertions"] == 0
      end
  end

  defp valid_counts?(_, _, _, _, _), do: false

  defp replacements!(paths, consumer) do
    for {name, file, from, to} <- mutations() do
      source =
        File.read!(Path.join(Keyword.fetch!(paths, :wotex_routines), "lib/wotex/routines/" <> file))

      unless length(String.split(source, from)) == 2,
        do: refuse("decision mutation site changed: " <> name)

      replacement = Path.join(consumer, name <> ".ex")
      File.write!(replacement, String.replace(source, from, to, global: false))
      {name, replacement}
    end
  end

  defp mutations do
    [
      {"expiry_before_receipt", "transition_run.ex", "reason = expiry(initial, c.time, records)",
       "reason = expiry(initial, c.time, Enum.take(records, 0))"},
      {"false_edge", "transition_edge.ex", "TransitionChecks.fields(claimed, changed, \"/edge\")",
       "TransitionChecks.fields(claimed, Map.drop(changed, ~w(baseline candidate_since_ms)), \"/edge\")"},
      {"refunded_spend", "transition_receipts.ex",
       "TransitionChecks.equal(record[\"receipts\"], receipts, \"/run/steps/receipts\")",
       "TransitionChecks.equal(Map.delete(record[\"receipts\"], \"admission\"), Map.delete(receipts, \"admission\"), \"/run/steps/receipts\")"},
      {"negative_member", "decision_cell.ex",
       "entry(state, entry, results[entry[\"program\"][\"ir_digest\"]])",
       "result = results[entry[\"program\"][\"ir_digest\"]]\n        if result && result[\"proposals\"] != [], do: entry(state, entry, result), else: state"},
      {"widened_cell", "decision.ex", ":ok <- equal(data[\"cell\"], cell, \"/cell\"),",
       ":ok <- equal(cell, cell, \"/cell\"),"},
      {"cutoff_omission", "decision_arbitration.ex",
       "domains = domain_index(Enum.map(groups, fn {key, [first | _]} -> {first, key} end))",
       "domains = domain_index(Enum.map(Enum.take(groups, batch), fn {key, [first | _]} -> {first, key} end))"}
    ]
  end

  defp command!(args, directory, environment) do
    {output, status} =
      System.cmd("mix", args, cd: directory, env: environment, stderr_to_stdout: true)

    IO.write(output)
    if status != 0, do: refuse("decision build command failed")
  end

  defp copy!(relative, destination) do
    source = Path.expand("../" <> relative, __DIR__)
    File.cp!(source, destination)
    IO.puts(relative <> " consumer source sha256: " <> sha256(source))
  end

  defp sha256(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp refuse(message), do: throw({:archive, message})
end
